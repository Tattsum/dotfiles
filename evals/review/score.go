// Command score は、dotfiles-code-review を claude -p で回した出力を、評価ケースの期待値と照合する。
//
// Usage:
//
//	go run score.go -case <case.json> -variant defect|clean -output <claude.json>
//	go run score.go summary <results dir>
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// lineTolerance は、期待する行の範囲の外側で許す行数。完全一致にしないのは、サブエージェントが行を数行ずらすことがあるため。
const lineTolerance = 3

type expectation struct {
	Path        string   `json:"path"`
	Lines       [2]int   `json:"lines"`
	MinSeverity string   `json:"min_severity"`
	Keywords    []string `json:"keywords"`
}

type caseSpec struct {
	Focus       string `json:"focus"`
	Perspective string `json:"perspective"`
	Summary     string `json:"summary"`
	Defect      struct {
		Expect []expectation `json:"expect"`
	} `json:"defect"`
	Clean struct {
		Paths []string `json:"paths"`
	} `json:"clean"`
}

type claudeOutput struct {
	Result       string  `json:"result"`
	IsError      bool    `json:"is_error"`
	Subtype      string  `json:"subtype"`
	TotalCostUSD float64 `json:"total_cost_usd"`
}

type finding struct {
	Severity    string `json:"severity"`
	Path        string `json:"path"`
	Line        int    `json:"line"`
	EndLine     int    `json:"end_line"`
	Perspective string `json:"perspective"`
	Text        string `json:"text"`
}

type result struct {
	Case     string    `json:"case"`
	Variant  string    `json:"variant"`
	Pass     bool      `json:"pass"`
	Reasons  []string  `json:"reasons"`
	Findings []finding `json:"findings"`
	CostUSD  float64   `json:"cost_usd"`
}

var (
	// 見出しを太字で包む（`- **[path:line] …**`）出力もあるので、`[` の前の `**` を許す。
	findingLine = regexp.MustCompile(`^\s*-\s*(?:\*\*)?\[([^\]\s]+?):(\d+)(?:-(\d+))?\]\s*(?:\(([^)]*)\))?\s*(.*)$`)
	countValue  = regexp.MustCompile(`^\s*(\d+)\s*件`)
	listedCount = regexp.MustCompile(`リスト\s*(\d+)\s*件`)
)

var severityRank = map[string]int{"Nice": 1, "Should": 2, "Must": 3}

func severityOfHeading(line string) string {
	switch {
	case strings.Contains(line, "Must"):
		return "Must"
	case strings.Contains(line, "Should"):
		return "Should"
	case strings.Contains(line, "Nice"):
		return "Nice"
	}
	return ""
}

// parseFindings は、重要度別の節にある `- [path:line] (観点) 本文` を取り出す。
func parseFindings(text string) []finding {
	var findings []finding
	severity := ""
	for _, line := range strings.Split(text, "\n") {
		if strings.HasPrefix(line, "## ") {
			severity = severityOfHeading(line)
			continue
		}
		if severity == "" {
			continue
		}
		if m := findingLine.FindStringSubmatch(line); m != nil {
			start, _ := strconv.Atoi(m[2])
			end := start
			if m[3] != "" {
				end, _ = strconv.Atoi(m[3])
			}
			findings = append(findings, finding{
				Severity:    severity,
				Path:        m[1],
				Line:        start,
				EndLine:     end,
				Perspective: strings.TrimSpace(m[4]),
				Text:        m[5],
			})
			continue
		}
		if len(findings) > 0 && strings.TrimSpace(line) != "" && (strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t")) {
			last := &findings[len(findings)-1]
			last.Text += "\n" + strings.TrimSpace(line)
		}
	}
	return findings
}

// perspectiveRan は、観点別カウントの行で、対象の観点が件数付きで実行され、失敗・未実行の注記が無いかを見る。
// --focus では横断とセカンドオピニオンが正当に未実行になるので、行全体ではなく対象の観点の区切りだけを見る。
func perspectiveRan(text, perspective string) (bool, string) {
	countLine := countLineOf(text)
	if countLine == "" {
		return false, "観点別カウントの行が無い（レビューが最後まで動いていない可能性）"
	}
	key := perspective + ":"
	idx := strings.Index(countLine, key)
	if idx < 0 {
		return false, fmt.Sprintf("観点別カウントに %s が無い", perspective)
	}
	segment := segmentUntilComma(countLine[idx+len(key):])
	if strings.Contains(segment, "失敗") || strings.Contains(segment, "未実行") {
		return false, fmt.Sprintf("%s が実行されていない: %s", perspective, strings.TrimSpace(segment))
	}
	if !countValue.MatchString(segment) {
		return false, fmt.Sprintf("%s の件数が読めない: %s", perspective, strings.TrimSpace(segment))
	}
	return true, ""
}

func countLineOf(text string) string {
	for _, line := range strings.Split(text, "\n") {
		if strings.Contains(line, "観点別カウント:") {
			return line
		}
	}
	return ""
}

// parsedAllListed は、観点別カウントの行の「リストN件」と、読み取れた指摘の数が合うかを見る。
// 合わないのは指摘の書式がずれたときで、そのまま採点すると clean が誤検知を見落として合格になりうる。
func parsedAllListed(text string, parsed int) (bool, string) {
	m := listedCount.FindStringSubmatch(countLineOf(text))
	if m == nil {
		return false, "採点できない: 観点別カウントの行に「リストN件」が無い"
	}
	listed, _ := strconv.Atoi(m[1])
	if listed != parsed {
		return false, fmt.Sprintf("採点できない: リストは%d件なのに、読み取れた指摘は%d件（指摘の書式のずれ）", listed, parsed)
	}
	return true, ""
}

// segmentUntilComma は、括弧の外にある最初の読点またはカンマまでを返す。失敗の注記は括弧の中にカンマを含みうる。
func segmentUntilComma(s string) string {
	depth := 0
	for i, r := range s {
		switch r {
		case '（', '(':
			depth++
		case '）', ')':
			if depth > 0 {
				depth--
			}
		case ',', '、':
			if depth == 0 {
				return s[:i]
			}
		}
	}
	return s
}

func containsAnyFold(text string, keywords []string) bool {
	if len(keywords) == 0 {
		return true
	}
	lower := strings.ToLower(text)
	for _, k := range keywords {
		if strings.Contains(lower, strings.ToLower(k)) {
			return true
		}
	}
	return false
}

func matches(f finding, exp expectation, perspective string) bool {
	if f.Path != exp.Path {
		return false
	}
	if f.EndLine < exp.Lines[0]-lineTolerance || f.Line > exp.Lines[1]+lineTolerance {
		return false
	}
	if perspective != "" && !strings.Contains(f.Perspective, perspective) {
		return false
	}
	if exp.MinSeverity != "" && severityRank[f.Severity] < severityRank[exp.MinSeverity] {
		return false
	}
	return containsAnyFold(f.Text, exp.Keywords)
}

func evaluate(spec caseSpec, variant string, out claudeOutput) result {
	r := result{Variant: variant, CostUSD: out.TotalCostUSD, Reasons: []string{}, Findings: parseFindings(out.Result)}
	if r.Findings == nil {
		r.Findings = []finding{}
	}
	if out.IsError || strings.TrimSpace(out.Result) == "" {
		r.Reasons = append(r.Reasons, fmt.Sprintf("claude の実行が失敗した（subtype=%s）", out.Subtype))
		return r
	}
	if ok, reason := perspectiveRan(out.Result, spec.Perspective); !ok {
		r.Reasons = append(r.Reasons, reason)
		return r
	}
	if ok, reason := parsedAllListed(out.Result, len(r.Findings)); !ok {
		r.Reasons = append(r.Reasons, reason)
		return r
	}
	switch variant {
	case "defect":
		for _, exp := range spec.Defect.Expect {
			found := false
			for _, f := range r.Findings {
				if matches(f, exp, spec.Perspective) {
					found = true
					break
				}
			}
			if !found {
				r.Reasons = append(r.Reasons, fmt.Sprintf("見つけるべき指摘が無い: %s:%d-%d", exp.Path, exp.Lines[0], exp.Lines[1]))
			}
		}
	case "clean":
		targets := map[string]bool{}
		for _, p := range spec.Clean.Paths {
			targets[p] = true
		}
		for _, f := range r.Findings {
			if targets[f.Path] {
				r.Reasons = append(r.Reasons, fmt.Sprintf("誤検知: [%s:%d] (%s) %s", f.Path, f.Line, f.Perspective, f.Text))
			}
		}
	default:
		r.Reasons = append(r.Reasons, fmt.Sprintf("variant が不明: %s", variant))
	}
	r.Pass = len(r.Reasons) == 0
	return r
}

func readJSON(path string, v any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, v)
}

func scoreOne(args []string) error {
	fset := flag.NewFlagSet("score", flag.ContinueOnError)
	casePath := fset.String("case", "", "case.json のパス")
	variant := fset.String("variant", "", "defect か clean")
	outputPath := fset.String("output", "", "claude -p --output-format json の出力")
	if err := fset.Parse(args); err != nil {
		return err
	}
	if *casePath == "" || *variant == "" || *outputPath == "" {
		return fmt.Errorf("-case・-variant・-output はすべて必須")
	}
	var spec caseSpec
	if err := readJSON(*casePath, &spec); err != nil {
		return fmt.Errorf("case.json を読めない: %w", err)
	}
	var out claudeOutput
	if err := readJSON(*outputPath, &out); err != nil {
		out = claudeOutput{IsError: true, Subtype: "unreadable-output"}
	}
	r := evaluate(spec, *variant, out)
	r.Case = filepath.Base(filepath.Dir(*casePath))
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(r)
}

type tally struct {
	Case    string  `json:"case"`
	Variant string  `json:"variant"`
	Runs    int     `json:"runs"`
	Passes  int     `json:"passes"`
	CostUSD float64 `json:"cost_usd"`
}

func summarize(dir string) ([]tally, error) {
	byKey := map[string]*tally{}
	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || d.Name() != "score.json" {
			return err
		}
		var r result
		if err := readJSON(path, &r); err != nil {
			return fmt.Errorf("%s を読めない: %w", path, err)
		}
		key := r.Case + "/" + r.Variant
		t, ok := byKey[key]
		if !ok {
			t = &tally{Case: r.Case, Variant: r.Variant}
			byKey[key] = t
		}
		t.Runs++
		if r.Pass {
			t.Passes++
		}
		t.CostUSD += r.CostUSD
		return nil
	})
	if err != nil {
		return nil, err
	}
	tallies := make([]tally, 0, len(byKey))
	for _, t := range byKey {
		tallies = append(tallies, *t)
	}
	sort.Slice(tallies, func(i, j int) bool {
		if tallies[i].Case != tallies[j].Case {
			return tallies[i].Case < tallies[j].Case
		}
		return tallies[i].Variant < tallies[j].Variant
	})
	return tallies, nil
}

func printSummary(dir string) error {
	tallies, err := summarize(dir)
	if err != nil {
		return err
	}
	total := 0.0
	fmt.Printf("%-24s %-7s %5s %6s %10s\n", "case", "variant", "runs", "passes", "cost_usd")
	for _, t := range tallies {
		fmt.Printf("%-24s %-7s %5d %6d %10.2f\n", t.Case, t.Variant, t.Runs, t.Passes, t.CostUSD)
		total += t.CostUSD
	}
	fmt.Printf("total cost_usd: %.2f\n", total)
	data, err := json.MarshalIndent(tallies, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "summary.json"), append(data, '\n'), 0o644)
}

func main() {
	var err error
	if len(os.Args) > 2 && os.Args[1] == "summary" {
		err = printSummary(os.Args[2])
	} else {
		err = scoreOne(os.Args[1:])
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
}

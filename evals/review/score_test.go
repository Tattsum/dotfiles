package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const reviewWithFinding = "観点別カウント: ts/storage: 1件, 横断: 未実行, second opinion: 未実行 (合計1件) → 重複統合0件 → 反証取り下げ0件 → リスト1件\n" +
	"## 📊 レビューサマリー\n" +
	"| ts/storage | 0 | 1 | 0 | 1 |\n" +
	"## 🔴 Must（必ず修正）\n" +
	"## 🟡 Should（できれば修正）\n" +
	"- [src/entries/save-draft.ts:15] (ts/storage) 一意制約は下書きのテーブルだけなのに、公開済みのテーブルまで重複として弾く → 下書きだけを見る\n" +
	"  - 補足: 編集中の下書きは公開版と同じ slug を持つ\n" +
	"## 🟢 Nice to have（提案）\n" +
	"## 📁 レビュー範囲\n" +
	"- ts/storage Focus A: 実行\n"

const reviewWithoutFinding = "観点別カウント: ts/storage: 0件, 横断: 未実行, second opinion: 未実行 (合計0件) → 重複統合0件 → 反証取り下げ0件 → リスト0件\n" +
	"## 🔴 Must（必ず修正）\n" +
	"## 🟡 Should（できれば修正）\n" +
	"## 🟢 Nice to have（提案）\n" +
	"全観点でレビューの指摘はありません\n" +
	"## 📁 レビュー範囲\n" +
	"- src/entries/save-draft.ts\n"

func storageSpec() caseSpec {
	var spec caseSpec
	spec.Focus = "storage"
	spec.Perspective = "ts/storage"
	spec.Defect.Expect = []expectation{{
		Path:        "src/entries/save-draft.ts",
		Lines:       [2]int{9, 23},
		MinSeverity: "Should",
		Keywords:    []string{"公開", "published"},
	}}
	spec.Clean.Paths = []string{"src/entries/save-draft.ts"}
	return spec
}

func TestParseFindingsReadsOnlySeveritySections(t *testing.T) {
	findings := parseFindings(reviewWithFinding)
	if len(findings) != 1 {
		t.Fatalf("want 1 finding, got %d: %+v", len(findings), findings)
	}
	got := findings[0]
	if got.Severity != "Should" || got.Path != "src/entries/save-draft.ts" || got.Line != 15 || got.Perspective != "ts/storage" {
		t.Errorf("unexpected finding: %+v", got)
	}
	if !containsAnyFold(got.Text, []string{"編集中の下書き"}) {
		t.Errorf("continuation line should be part of the finding text: %q", got.Text)
	}
}

func TestParseFindingsReadsLineRanges(t *testing.T) {
	findings := parseFindings("## 🔴 Must（必ず修正）\n- [app/layout.tsx:9-15] (ts/security) 説明\n")
	if len(findings) != 1 || findings[0].Line != 9 || findings[0].EndLine != 15 {
		t.Fatalf("want a 9-15 range, got %+v", findings)
	}
}

func TestParseFindingsReadsBoldHeadings(t *testing.T) {
	findings := parseFindings("## 🔴 Must（必ず修正）\n- **[app/admin/drafts/page.tsx:7] (ts/security: Focus D: 認可と API 契約) admin ロールを確かめていない（CWE-862）**\n")
	if len(findings) != 1 || findings[0].Path != "app/admin/drafts/page.tsx" || findings[0].Line != 7 || findings[0].Perspective != "ts/security: Focus D: 認可と API 契約" {
		t.Fatalf("want the bold heading read as a finding, got %+v", findings)
	}
}

func TestPerspectiveRan(t *testing.T) {
	tests := []struct {
		name string
		text string
		want bool
	}{
		{"counted with zero findings", "観点別カウント: ts/test: 0件, 横断: 未実行 (合計0件)", true},
		{"counted with findings while cross-cutting is skipped", "観点別カウント: ts/test: 2件, 横断: 未実行, second opinion: 未実行 (合計2件)", true},
		{"a failed focus is not a run", "観点別カウント: ts/test: 1件（失敗: focus B, focus A）, 横断: 未実行 (合計1件)", false},
		{"a skipped perspective is not a run", "観点別カウント: ts/test: 未実行, 横断: 未実行", false},
		{"missing count line means the review did not finish", "## 🔴 Must（必ず修正）", false},
		{"another perspective does not count", "観点別カウント: ts/state: 0件 (合計0件)", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, reason := perspectiveRan(tt.text, "ts/test")
			if got != tt.want {
				t.Errorf("got %v (%s), want %v", got, reason, tt.want)
			}
		})
	}
}

func TestEvaluate(t *testing.T) {
	tests := []struct {
		name    string
		variant string
		out     claudeOutput
		want    bool
	}{
		{"defect passes when the expected finding is reported", "defect", claudeOutput{Result: reviewWithFinding}, true},
		{"defect fails when nothing is reported", "defect", claudeOutput{Result: reviewWithoutFinding}, false},
		{"defect fails when the finding misses every keyword", "defect", claudeOutput{Result: strings.ReplaceAll(reviewWithFinding, "公開", "別")}, false},
		{"defect fails when the finding is far from the expected lines", "defect", claudeOutput{Result: strings.ReplaceAll(reviewWithFinding, "save-draft.ts:15]", "save-draft.ts:40]")}, false},
		{"defect fails when the severity is below the minimum", "defect", claudeOutput{Result: strings.ReplaceAll(reviewWithFinding, "## 🟡 Should（できれば修正）\n", "## 🟢 Nice to have（提案）\n")}, false},
		{"clean passes when the target file gets no finding", "clean", claudeOutput{Result: reviewWithoutFinding}, true},
		{"clean fails on a finding in the target file", "clean", claudeOutput{Result: reviewWithFinding}, false},
		{"clean fails when the review did not run", "clean", claudeOutput{Result: "このスキルはメインセッションから起動してください"}, false},
		{"clean fails when a listed finding is in an unreadable format", "clean", claudeOutput{Result: strings.ReplaceAll(reviewWithFinding, "- [src/entries/save-draft.ts:15]", "- src/entries/save-draft.ts:15")}, false},
		{"clean fails when the count line has no list total", "clean", claudeOutput{Result: strings.ReplaceAll(reviewWithoutFinding, " → リスト0件", "")}, false},
		{"an errored claude run fails", "clean", claudeOutput{IsError: true, Subtype: "error_max_budget_usd"}, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := evaluate(storageSpec(), tt.variant, tt.out)
			if got.Pass != tt.want {
				t.Errorf("got pass=%v, want %v; reasons=%v", got.Pass, tt.want, got.Reasons)
			}
		})
	}
}

func TestSummarizeCountsPassesPerCaseAndVariant(t *testing.T) {
	dir := t.TempDir()
	write := func(rel, body string) {
		path := filepath.Join(dir, rel)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("a/defect/run-1/score.json", `{"case":"a","variant":"defect","pass":true,"cost_usd":1.5}`)
	write("a/defect/run-2/score.json", `{"case":"a","variant":"defect","pass":false,"cost_usd":0.5}`)
	write("a/clean/run-1/score.json", `{"case":"a","variant":"clean","pass":true,"cost_usd":1}`)

	tallies, err := summarize(dir)
	if err != nil {
		t.Fatal(err)
	}
	want := []tally{
		{Case: "a", Variant: "clean", Runs: 1, Passes: 1, CostUSD: 1},
		{Case: "a", Variant: "defect", Runs: 2, Passes: 1, CostUSD: 2},
	}
	if len(tallies) != len(want) {
		t.Fatalf("got %+v, want %+v", tallies, want)
	}
	for i := range want {
		if tallies[i] != want[i] {
			t.Errorf("tally %d: got %+v, want %+v", i, tallies[i], want[i])
		}
	}
}

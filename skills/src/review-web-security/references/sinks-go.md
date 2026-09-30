# Go Sink 表

差分が Go のときにセキュリティ担当が読む。表は Sink を探す**検索の入口**であって判定ではない。ヒットしたら、信頼できない Source が届くかを `output-discipline.md` の手順でたどる。バージョン表記は Go 本体またはライブラリの導入版で、pkg.go.dev・`go doc`・`api/go1.xx.txt` で確認したもの。

## A インジェクション

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `db.Query` / `QueryRow` / `Exec`、gorm の `Raw` / `Exec` / `Where` / `Order` に `fmt.Sprintf` や `+` で組み立てた SQL を渡す | プレースホルダ（`?` / `$1`）と引数で渡す。ORDER BY や列名は `map[string]string` で許可列へ変換する |
| `exec.Command("sh", "-c", s)` / `bash -c` に外部入力を連結した文字列を渡す | `exec.Command(bin, args...)` はシェルを経由しない。利用者の値は1つのオペランドとして渡し、`-` 始まりは拒否するか `--` で終端する |
| `exec.Cmd.Env` を設定しない | `Env` が nil だと親プロセスの環境変数（秘密を含む）を継承する。必要な値だけを明示する。timeout は `exec.CommandContext` |
| `template.New(...).Parse(userInput)`（`text/template` / `html/template` のどちらも） | テンプレートの Source は `embed` した固定ファイルなどから読み、利用者の値は `Execute` のデータとして渡す。テンプレート名は許可リストで選ぶ |
| `encoding/xml` | 外部エンティティや DTD は解決しない（DOCTYPE は Directive トークンとして返るだけ）。`Decoder.Strict`（既定 true）を切らない。深い入れ子などの資源枯渇は別問題なので入力サイズを制限する。cgo の libxml2 バインディング等を使うなら、そのオプションを確認する |
| `encoding/gob` に信頼できない入力を渡す | gob は敵対的な入力に対して堅牢化されておらず、入力サイズの上限も設定できないと doc に明記されている。外部入力には使わない |
| `gopkg.in/yaml.v3` | 宛先の Go 型にデコードするだけで任意の型を生成しないが、alias 展開による資源枯渇があるため入力サイズを制限する。上流の go-yaml/yaml は 2025-04 にアーカイブされ unmaintained |
| `log.Printf("... %s", userInput)`、`fmt.Sprintf` で組み立てたログ行 | `log/slog` の属性（`slog.String("user", name)`）で渡し、`slog.JSONHandler` で出力する |

## B XSS とクライアントサイド

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `template.HTML(v)` / `template.JS(v)` / `template.URL(v)` / `template.CSS(v)` への変換 | これらの型は `html/template` の文脈別自動エスケープを迂回する。利用者由来の値を変換しない。HTML が要件なら bluemonday の許可リストでサニタイズしてから |
| `text/template` で HTML を出力する | `text/template` は HTML をエスケープしない。HTML には `html/template` を使う |
| `w.Write([]byte("<p>" + v))`、`fmt.Fprintf(w, "<a href=...%s>", v)` | `html/template` で出力する |
| `http.Redirect(w, r, r.URL.Query().Get("next"), ...)` | `url.Parse` 後に `Scheme` と `Host` が空で `/` から始まり、`//` や `\` で始まらないことを確認する。外部 URL は host の完全一致 |
| `w.Header().Set("Access-Control-Allow-Origin", r.Header.Get("Origin"))`、Origin を常に許可する CORS ミドルウェア設定 | 許可 Origin の完全一致リストで照合し、`w.Header().Add("Vary", "Origin")` を付ける |

## C 認証とセッション

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `sha256.Sum256(pw)` / `md5.Sum(pw)` でパスワードを保存する | `golang.org/x/crypto/bcrypt`（72 バイトを超える入力は `ErrPasswordTooLong`。長い入力の扱いを決める）か `golang.org/x/crypto/argon2.IDKey`（Argon2id） |
| `math/rand` / `math/rand/v2` でトークンを生成する | `crypto/rand`。math/rand は doc でセキュリティ用途に使うべきでないと明記されている |
| トークンを `==` で比較する | `crypto/subtle.ConstantTimeCompare`（長さの違いは漏れる） |
| `http.Cookie` の `Secure` / `HttpOnly` / `SameSite` 未設定 | 3 つを明示する。ローカル用に Secure を切る設定が本番の既定値にならないようにする |
| Cookie 認証の状態変更に CSRF 検査が無い | Go 1.25 の `http.CrossOriginProtection` は Sec-Fetch-Site、または Origin と Host の比較で非安全メソッドのクロスオリジン要求を拒否する（両ヘッダーが無い要求は非ブラウザとみなして許可）。それ以前の版はトークン検証のミドルウェア |
| golang-jwt の `jwt.Parse` の Keyfunc でアルゴリズムを確認しない | `jwt.WithValidMethods` / `WithIssuer` / `WithAudience`（v5.0.0〜）、`WithExpirationRequired`（v5.1.0〜。指定しないと exp は任意） |
| `r.Host` からパスワードリセット URL を組み立てる | 設定値のベース URL を使う |

## D 認可と API 契約

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `db.First(&obj, id)` / `repo.Get(ctx, id)` の直後に所有者・テナントの確認が無い | `WHERE id = ? AND owner_id = ?` のように取得条件へ含めるか、取得直後に認可関数を呼ぶ |
| `json.NewDecoder(r.Body).Decode(&entity)` で DB のエンティティへ直接デコードする | 更新できる項目だけを持つリクエスト用の型へデコードし、サーバーが決める値（所有者・状態）は代入しない。`Decoder.DisallowUnknownFields`（struct 宛てのみ有効） |
| `json.Marshal(dbModel)` / `c.JSON(200, model)` で DB の構造体を返す | レスポンス用の型でフィールドを明示する。`json:"-"` 頼みは列の追加に弱い |
| ルーターのグループに認可ミドルウェアが無い新しいルート | ルート登録と認可ミドルウェアの対応を確認する |

## E 状態と業務ロジック

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `UPDATE ... SET status = ? WHERE id = ?`（遷移元の状態を見ない） | `WHERE id = ? AND status = ?` にして `res.RowsAffected()` が 1 のときだけ成功扱いにする。`sql.Tx` 内の `SELECT ... FOR UPDATE` |
| 一意制約違反を握りつぶす | MySQL の 1062 / PostgreSQL の `23505` を判定して利用者向けエラーへ変換する |
| 通知・課金などの副作用を `tx.Commit()` の前に実行する | コミット成功後に実行する（outbox 等） |
| 認可・在庫確認の `err != nil` で許可を返す | 失敗時は拒否側に倒す |

## F SSRF と外部 I/O

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `http.Get(userURL)`、`http.NewRequest(method, userURL, ...)` | 論理 ID から固定宛先へ変換する。任意 URL が必要なら scheme・host・port・解決後の IP を検証する |
| `http.DefaultClient` / `http.Client{}`（Timeout 0 は無制限） | `http.Client{Timeout: ...}` を明示する（接続・リダイレクト・本文の読み取りを含む全体の制限） |
| リダイレクトを既定のまま追う（最大 10 回） | `CheckRedirect` で `http.ErrUseLastResponse` を返すと追わない。追うなら各ホップを再検証する |
| 名前解決前のホスト名だけで宛先を判定する | `net.Dialer.ControlContext`（Go 1.20〜）/ `Control` は解決後の `IP:port` を受け取るので、接続直前に `net/netip` の `IsLoopback` / `IsPrivate` / `IsLinkLocalUnicast` / `IsUnspecified` で検査する。IPv4-mapped IPv6 は `Unmap()` してから判定する |
| `tls.Config{InsecureSkipVerify: true}` | TLS 検証を無効化しない |
| `r.Body` をそのまま読む、`io.ReadAll(resp.Body)` | `http.MaxBytesReader` で受信ボディを、`io.LimitReader` で外部レスポンスを制限する |
| `http.ListenAndServe` / `http.Server{}` で timeout を設定しない | `ReadHeaderTimeout` を明示する（0 なら `ReadTimeout` を使い、両方 0 以下なら無制限） |
| `strconv.Atoi` のエラーを無視して既定値にする、`r.FormValue`（同名パラメータの先頭だけ返す） | 変換失敗は 400 にする。PATCH の未指定と空を `*string` などで区別する。値の取得元（`URL.Query()` / `PostForm`）を明示する |

## G ファイル

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `filepath.Join(base, userPath)`、`filepath.Clean` で安全化したつもりになる | どちらも `..` による脱出を防がない。`filepath.IsLocal`（Go 1.20〜。字句だけの判定で symlink は考慮しない）で検証するか、`os.OpenRoot(base)` の `os.Root`（Go 1.24〜。root 外を指す `..`・絶対パス・symlink をエラーにする。bind mount や /proc の横断は防がない）経由で開く |
| `strings.HasPrefix(p, base)` で親子判定する | 前方一致では `/srv/files-backup` が通る。`os.Root` か `filepath.Rel` の結果で判定する |
| `http.ServeFile(w, r, userPath)` | 利用者の値をパスとしてそのまま渡さない。ID から保存名を引く |
| `multipart.FileHeader.Filename` を保存パスや拡張子の判定に使う | 保存名はサーバーで生成する。形式は `http.DetectContentType`（先頭 512 バイト）と `image.DecodeConfig`（デコード前に寸法を確認）で判定する |
| `archive/zip` の `File.Name` を検証せずに展開先と結合する | `ErrInsecurePath` は GODEBUG `zipinsecurepath=0` のときだけ返る（既定は 1 で安全でないパスも受理する）。各エントリ名を `filepath.IsLocal` で検証し、合計サイズとファイル数を制限する。tar も同様（`tarinsecurepath`） |
| `os.Remove(old)` を `tx.Commit()` の前に実行する | 新規保存 → DB 更新 → コミット後に旧ファイル削除、の順にする |

## H 情報露出・ログ・本番設定

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `http.Error(w, err.Error(), 500)`、`err.Error()` を JSON で返す | 一般化したメッセージとリクエスト ID を返し、詳細はログへ出す |
| `import _ "net/http/pprof"` | `/debug/pprof/` 配下が `DefaultServeMux` に登録される。公開ポートで `DefaultServeMux` を使わない |
| `r.Header.Get("X-Forwarded-For")` / `X-Forwarded-Proto` を直接使う | 信頼する proxy の段数か CIDR を決めてから取り出す |
| `r.Host` から絶対 URL・リダイレクト先を作る | 設定値か許可 Host の一覧を使う |
| `fmt.Sprintf("%+v", cfg)` で設定を出力する、`httputil.DumpRequest` の結果をログへ流す | 秘匿値の型に `slog.LogValuer` / `String()` を実装してマスクする。リクエストを丸ごと記録しない |

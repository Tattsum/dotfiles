# PHP / Laravel Sink 表

差分が PHP のときにセキュリティ担当が読む。表は Sink を探す**検索の入口**であって判定ではない。ヒットしたら、信頼できない Source が届くかを `output-discipline.md` の手順でたどる。バージョン表記は php.net・laravel.com/docs・laravel/framework のソースで確認したもの（Laravel はタグの存在からの範囲推定を含む）。

## A インジェクション

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `DB::raw` / `whereRaw` / `selectRaw` / `orderByRaw` / `havingRaw` / `DB::select` / `DB::statement` に変数を連結・埋め込む | バインド（`?` と配列）かクエリビルダを使う。`orderBy` の列名は `in_array($col, $allowed, true)` などの許可リストで選ぶ |
| `exec` / `shell_exec` / `system` / `passthru` / `proc_open` / バッククォート / `Process::fromShellCommandline` に外部入力を連結する | Symfony Process（Laravel の `Process` ファサード）を配列で渡すとシェルを経由しない。配列でも `-` 始まりの値はオプションとして解釈され得るので `--` や許可リストで対処する |
| `escapeshellarg` / `escapeshellcmd` で安全化したつもりになる | シェルのメタ文字を扱うだけで、`-` 始まりのオプション注入は防げない。第一選択にしない |
| `Blade::render($userString)`、`view($request->input('v'))`、`include $var` | テンプレートの Source とテンプレート名は固定値か許可リスト。利用者の値はビューのデータとして渡す |
| `simplexml_load_string` / `DOMDocument::loadXML` / `XMLReader` に `LIBXML_NOENT` / `LIBXML_DTDLOAD` を指定する | libxml 2.9.0 以降はエンティティ置換が既定で無効。`LIBXML_NOENT` は XXE を招き得るので付けない。`libxml_disable_entity_loader` は PHP 8.0 で非推奨。PHP 8.4 + libxml 2.13 以降は `LIBXML_NO_XXE` も使える |
| `unserialize($input)` | 信頼できない入力には使わず JSON にする（php.net が明記）。使うなら `['allowed_classes' => false]` と `max_depth` |
| Symfony Yaml の `Yaml::PARSE_OBJECT` | オブジェクトのパースは既定で無効。`PARSE_OBJECT` を付けると `!php/object` が PHP のデシリアライズになるため、信頼できない YAML では付けない |
| `Log::info("login: " . $username)` | ログの context 配列で渡す（`Log::info('login', ['user' => $username])`） |

## B XSS とクライアントサイド

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| Blade の `{!! $value !!}`、`new HtmlString($value)` | `{{ }}` は htmlspecialchars を通す。HTML が要件なら HTMLPurifier の許可リストでサニタイズしてから |
| `<script>` 内に `{{ }}` や `json_encode` で値を埋め込む | `Js::from($value)`（HTML 引用内にも安全に埋め込める JSON を生成する） |
| `redirect($request->input('next'))`、`redirect()->away($url)` | 相対パスに限定するか host を許可リストで照合する。認証後の遷移は `redirect()->intended()` |
| `parse_url` を使わず `explode` や文字列操作で URL を分解する、外部値を URL パラメータへそのまま埋め込む | `parse_url` で分解して scheme を許可リストで確認する。パラメータは `http_build_query` / `rawurlencode` で組み立てる |
| `config/cors.php` の `allowed_origins => ['*']` と `supports_credentials => true` の組み合わせ、緩い `allowed_origins_patterns` | 許可 Origin を完全一致で列挙する。Laravel 11 以降は `php artisan config:publish cors` で生成したファイルを確認する（既定は `allowed_origins => ['*']`、`supports_credentials => false`） |
| CSP でインライン script を許可する | Vite を使うなら `Vite::useCspNonce()` でレスポンスごとの nonce を付ける |

## C 認証とセッション

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `md5()` / `sha1()` / `hash('sha256', $pw)` でパスワードを保存する | `Hash::make` / `password_hash`。ログイン成功後に `Hash::needsRehash` / `password_needs_rehash` で再ハッシュする |
| トークンを `==` / `===` で比較する | `hash_equals($known, $user)`（第 1 引数が既知の値。長さの違いは漏れる） |
| パスワード検証ルールが長さだけ | `Password::min(...)->uncompromised()`（漏えい済みパスワードの照合） |
| ログイン後に `$request->session()->regenerate()` が無い | ログイン成功時に regenerate する。ログアウトは `Auth::logout()` + `session()->invalidate()` + `session()->regenerateToken()` |
| 重要操作に再認証が無い | `password.confirm` ミドルウェア。他端末のセッション失効は `Auth::logoutOtherDevices`（`AuthenticateSession` が前提） |
| CSRF の除外を足す（Laravel 11 以降は `bootstrap/app.php` の `$middleware->validateCsrfTokens(except: [...])`、10 以前は `VerifyCsrfToken::$except`） | 除外するルートには署名検証などの代替認証を同じ差分で入れる |
| `config/session.php` の `secure` / `http_only` / `same_site` が緩い、`SESSION_SECURE_COOKIE` を環境で落とせる | 本番の既定値を安全側にする |
| `firebase/php-jwt` の `JWT::decode` | v6 以降は `new Key($key, 'HS256')` のようにアルゴリズムを固定する。iss / aud / exp を確認する |
| `$request->getHost()` や `url()` からリセット URL を作る（Host ヘッダーを信頼している） | `APP_URL` / `URL::forceRootUrl()` と許可 Host（`trustHosts`）で固定する |

## D 認可と API 契約

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `Model::find($id)` / `findOrFail($id)` の直後に Policy・所有者の確認が無い | `$this->authorize()` / `Gate::authorize()` / Policy。取得条件に含めるなら `$request->user()->posts()->findOrFail($id)`、scoped route binding |
| マルチテナントのクエリに `tenant_id` 条件が無い | グローバルスコープかリポジトリで必ず付ける |
| 存在を隠す対象の 403 / 404 がばらつく | Policy の戻り値に `Response::denyAsNotFound()`（Laravel 9.10 には無く 9.20 にはある。`Gate::denyAsNotFound` というメソッドは無い） |
| `Model::create($request->all())` / `update($request->all())` / `fill($request->all())`、`$guarded = []` | `$request->validated()` / `safe()->only([...])` だけを渡す。`$fillable` を明示する。開発時は `Model::preventSilentlyDiscardingAttributes()` |
| `return $user;` / `toArray()` でモデルを返し `$hidden` に頼る | `JsonResource` でフィールドを明示する |
| ルートに `can:` / `auth` ミドルウェアが付いていない | ルート定義とミドルウェアの対応を確認する |
| 非公開ファイルの URL を推測困難な名前だけで守る | 認可付きのダウンロードルートか、認可後の `Storage::temporaryUrl()` |

## E 状態と業務ロジック

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `->where('id', $id)->update(['status' => 'accepted'])`（遷移元の状態を見ない） | `->where('status', 'pending')` を条件に含め、`update()` の戻り値（更新件数）を確認する。`DB::transaction` 内で `lockForUpdate()` |
| 一意制約違反を握りつぶす | `UniqueConstraintViolationException`（Laravel 10.17 には無く 10.20 にはある）を捕まえて利用者向けエラーへ変換する |
| 通知・ジョブをトランザクションのコミット前に送る | `afterCommit` を付けたジョブ・イベントにする |
| `$request->input('unit_price')` / `total` を使う | サーバー側の価格表から再計算する |
| `catch (\Throwable $e) { return true; }`、catch-all で例外を握りつぶす | 失敗時は拒否側に倒し、例外の粒度を保つ |

## F SSRF と外部 I/O

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `Http::get($request->url)`、Guzzle の `request`、`file_get_contents($url)`、`curl_exec` に利用者の URL を渡す | 論理 ID から固定宛先へ変換する。任意 URL が必要なら名前解決後の IP を検査する |
| `filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE \| FILTER_FLAG_NO_RES_RANGE)` だけで内部宛先を弾いたつもりになる | ループバックは RES 側に含まれる。IPv6 の範囲は PHP のバージョンで違い得る。名前解決後の IP に対して検査し、リダイレクトの各ホップも再検査する |
| リダイレクトを既定のまま追う（Guzzle の `allow_redirects` は既定で最大 5 回追従） | `Http::withoutRedirecting()` / `allow_redirects => false` |
| timeout 未設定（Guzzle の `timeout` / `connect_timeout` は既定 0 = 無制限） | `Http::timeout()` / `Http::connectTimeout()` を明示する |
| `'verify' => false` | TLS 検証を無効化しない |
| `FormRequest` を使わず `$request->input()` をそのまま使う、`$request->input()`（query と body を統合して取得） | サーバー側の `FormRequest` で検証する。値の取得元を `query()` / `post()` で明示し、同名パラメータの配列化を拒否する |
| `(int) $request->input('limit')` のような黙ったキャスト、`in_array` の非 strict 比較 | 型変換の失敗は 422 にする。`in_array($v, $list, true)` |
| TrimStrings の対象 | Laravel 11 以降はフレームワーク側で `password` / `password_confirmation` / `current_password` を既定で除外する（10 以前はアプリ側の `TrimStrings.php`）。パスワード系の項目を追加するなら除外に含める |

## G ファイル

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `getClientOriginalName()` / `getClientOriginalExtension()` / `getClientMimeType()` を保存名や形式の判定に使う | どれもクライアント申告値（docs も unsafe と明記）。保存は `store()`（一意な名前を生成し、拡張子は内容から決める）か `hashName()` / `extension()` |
| `mimes` ルールだけで拡張子も確認したつもりになる | `mimes` / `mimetypes` は内容から MIME を推定するが、利用者が付けた拡張子との一致は見ない（必要なら `extensions` ルール）。画像は `dimensions` で寸法を制限する |
| `Storage::path($request->input('path'))`、`response()->download($userPath)`、`unlink($path)` | ID から DB のレコードを引き、サーバーが管理する保存名を使う。自前で結合するなら `realpath()`（false を返し得る）の結果を、区切り文字を付けた基準パスで前方一致判定する |
| `public/` 直下や `storage:link` の公開範囲に利用者ファイルを置く | 非公開ディスクに置き、認可付きのルートか `Storage::temporaryUrl()` で配信する。直接アップロードは `Storage::temporaryUploadUrl()`（9.5x〜）の対象キーと期限を絞る |
| `ZipArchive::extractTo` をエントリ名の検証なしに呼ぶ | 展開前に各エントリ名（`..`・絶対パス）と合計サイズ・ファイル数を検証する |
| `Storage::delete($old)` を `DB::transaction` のコミット前に実行する | コミット後に旧ファイルを削除する |

## H 情報露出・ログ・本番設定

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| 例外ハンドラで `$e->getMessage()` やスタックトレースをレスポンスに返す、`APP_DEBUG=true` を本番に残す | 一般化したエラーとリクエスト ID を返す。本番で `APP_DEBUG=false` を起動時に確認する。Telescope / Debugbar の公開範囲を確認する |
| `trustProxies(at: '*')`（Laravel 11 以降の `bootstrap/app.php`。10 以前は `TrustProxies` ミドルウェア） | 信頼する proxy を具体的に指定し、アプリへの直接経路を閉じる |
| `trustHosts` が未設定のまま Host から URL を生成する | `$middleware->trustHosts(at: [...])` で許可 Host を明示する |
| `Log::info('req', $request->all())`、例外に SQL や認証情報を含めたまま記録する | 項目名と理由コードだけを残し、`Authorization` / `Cookie` / トークン / パスワードを出さない |
| 平文のアクセストークン・API キーを配列や文字列のまま持ち回る | 値オブジェクトで包み、`__toString` / `__debugInfo` でマスクしてログやダンプへの平文の漏えいを防ぐ |
| Blade に `config('services.x.secret')` を埋め込む、`VITE_*` に秘密を入れる | ブラウザへ配る値は公開される前提で、公開用のキーだけにする |

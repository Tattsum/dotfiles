# TypeScript / Node / Vue / React / Next Sink 表

差分が TS / JS / Vue のときにセキュリティ担当が読む。表は Sink を探す**検索の入口**であって判定ではない。ヒットしたら、信頼できない Source が届くかを `output-discipline.md` の手順でたどる。バージョン表記は nodejs.org・各フレームワークの公式ドキュメント・各パッケージの README / CHANGELOG で確認したもの。

## A インジェクション

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| Prisma の `$queryRawUnsafe` / `$executeRawUnsafe`、`Prisma.raw` に外部入力を連結する | `$queryRaw` / `$executeRaw` のタグ付きテンプレートか `Prisma.sql`（構造と値を分ける）。IN 句は `Prisma.join`。`Prisma.raw` は完全に信頼できる文字列だけ |
| knex の `raw` / `whereRaw` / `orderByRaw`、`sequelize.query`、`sequelize.literal` に連結した文字列を渡す | バインド（`?` と配列、`replacements`）を使う。orderBy の列名は許可リスト |
| `child_process.exec` / `execSync`、`spawn` の `shell: true` に外部入力を連結する | `execFile` / `spawn` は既定でシェルを起動しない。引数は配列で渡す。shell 付きの spawn に args を渡す形は非推奨（DEP0190）。Windows の .bat/.cmd は shell 未指定だと EINVAL（CVE-2024-27980 の修正。18.20.2 / 20.12.2 / 21.7.3） |
| `ejs.render(userStr)` / `Handlebars.compile(userStr)` / `_.template(userStr)` / `nunjucks.renderString(userStr)` / `pug.compile(userStr)`、`res.render(req.query.view)` | テンプレートの Source と名前は固定値か許可リスト。利用者の値はデータとして渡す |
| libxmljs の `replaceEntities: true`（旧名 `noent: true`） | エンティティ置換は XXE の原因になる。既定の false のまま使う |
| fast-xml-parser | 外部エンティティ（SYSTEM）は解決しないが、`processEntities` は既定 true で DOCTYPE 内部の ENTITY を展開する（展開量には上限あり）。信頼できない XML では `processEntities: false`。xml2js は下位の sax が DTD のエンティティを扱わない |
| `node-serialize` などの関数を復元するシリアライザー、`eval` / `new Function` / `vm` での復元 | JSON にする。js-yaml は v4 以降 `load` が既定で安全なスキーマ（関数などを生成しない）。v3 系の `load` は安全でない |
| `console.log(\`login ${username}\`)`、文字列連結のログ行 | pino などの構造化ロガーにオブジェクトで渡す |

## B XSS とクライアントサイド

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| Vue の `v-html`、React の `dangerouslySetInnerHTML` | 自動エスケープを迂回する。利用者由来・外部由来の値は DOMPurify でサニタイズしてから（Trusted Types のポリシー内では `RETURN_TRUSTED_TYPE: false`） |
| `innerHTML` / `outerHTML` / `insertAdjacentHTML` / `document.write` | textContent・createElement・フレームワークのバインディングにする |
| `eval` / `new Function` / 文字列を渡す `setTimeout` / `setInterval` | 関数を渡す。設定の読み込みは `JSON.parse`（結果を別の Sink へ渡すなら、その文脈の対策は別途要る） |
| 利用者の値を `href` / `src` / `window.open` / `location.href` / `router.push` に入れる | `new URL(v, base)` の `protocol` を `http:` / `https:` の許可リストで確認する。React は 16.9.0 で `javascript:` URL を警告、19.0.0 で例外を投げる関数に置き換えるが、scheme の検証は別途必要。Vue は `javascript:` を防がない |
| `fetch(location.hash.slice(1))`、`fetch(params.get('url'), { credentials: 'include' })` | 操作名から固定の method / path への対応表にする（client-side CSRF） |
| `window.addEventListener('message', ...)` で `event.origin` を確認しない、`postMessage(data, '*')` | 受信側は `event.origin` を完全一致で確認してから `event.data` の型を検証する。送信側は具体的な targetOrigin |
| `localStorage.setItem('token', ...)`、`localStorage.getItem('role')` で権限の表示・分岐をする | トークンは httpOnly Cookie。Storage の値を認可の根拠にしない |
| 自作の再帰 merge、lodash の `merge` / `mergeWith` / `defaultsDeep` / `set` / `setWith` / `zipObjectDeep` / `unset` / `omit` に信頼できないキーやパスを渡す | 許可キーで取り出す。任意キーの辞書は `Map` か `Object.create(null)`。lodash の修正版は CVE ごとに違う（merge 系 4.17.11、defaultsDeep 4.17.12、set 系 4.17.19、unset / omit 4.17.23 と 4.18.0）ので最新へ更新する |
| `<iframe sandbox="allow-scripts allow-same-origin">`、埋め込み先 host を利用者が選べる | 最も厳しい sandbox から始める。埋め込み先は許可リスト |
| `cors({ origin: true, credentials: true })`、末尾一致の RegExp（`/example\.com$/`） | `origin: true` と RegExp は一致したリクエストの Origin をそのまま返す。完全一致の配列で許可する |
| helmet の CSP に `'unsafe-inline'` / `'unsafe-eval'` を足す、Next の `headers()` で CSP を緩める | helmet は既定で CSP・nosniff・Referrer-Policy 等を付ける。緩めるのではなく nonce（Next はリクエストごとに生成）を使う |
| socket.io の `cors` だけで WebSocket の Origin を守ったつもりになる | socket.io の `cors` はブラウザの HTTP long-polling にだけ効き、WebSocket 接続には効かない。`allowRequest` で `req.headers.origin` を検査する。ws は HTTP server の `upgrade` イベントで認証する |

## C 認証とセッション

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `crypto.createHash('sha256').update(pw)` でパスワードを保存する | argon2 / bcrypt のライブラリか `crypto.scrypt` |
| `Math.random()` でトークンを生成する | `crypto.randomBytes` / `crypto.randomUUID` |
| トークンを `===` で比較する | `crypto.timingSafeEqual`（長さが違うと例外を投げる前提で扱う） |
| `res.cookie` / Next の `cookies().set` / express-session の cookie で `secure` / `httpOnly` / `sameSite` 未指定 | 3 つを明示する。ログイン成功時は express-session の `req.session.regenerate()` |
| Next の Server Actions の CSRF 対策に全面的に頼る | Origin の host と `x-forwarded-host`（無ければ `host`）を比べて不一致を拒否するが、Origin ヘッダーが無い要求は警告だけで通す。追加許可は `serverActions.allowedOrigins`。Route Handler や Express の POST には別途 Origin / トークン検証が要る |
| `jsonwebtoken.decode` の結果を信用する、`verify` で `algorithms` を指定しない | `verify` に `algorithms` を明示する（未指定だと鍵の種類から既定が決まる）。jose の `jwtVerify` は `issuer` / `audience` を渡さないと検査しない |
| `req.headers.host` からリセット URL を作る | 設定値のベース URL |

## D 認可と API 契約

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `prisma.x.findUnique({ where: { id } })` のあとに所有者の確認が無い | `where: { id, ownerId: session.user.id }`、または取得直後に認可関数 |
| Next の Route Handler / Server Action / tRPC procedure の中に認可が無い | UI の出し分けは認可ではない。各ハンドラでセッションと対象の権限を確認する。Next の middleware（16.0.0 で proxy に改名）の matcher から外れたパスは素通りする |
| `prisma.x.update({ data: req.body })`、`Object.assign(entity, req.body)`、`{ ...body }` をそのまま保存する | zod の `.strict()` などで許可したフィールドだけを取り出し、所有者・ロールはセッションから決める |
| `res.json(row)`、Prisma の `select` を省略してモデルを返す | レスポンス用の型でフィールドを明示する |
| 最後の管理者の削除、自分自身の降格を許す | 権限ロックアウトを拒否する |
| 予約ルートと衝突する ID、`"1e+21"` のような数値に見える文字列を受け付ける | 予約語を拒否し、数値は `Number.isInteger` などで検証する |

## E 状態と業務ロジック

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `prisma.x.update({ where: { id }, data: { status: 'accepted' } })`（遷移元の状態を見ない） | `updateMany({ where: { id, status: 'pending' } })` の `count` が 1 のときだけ成功扱いにする。`prisma.$transaction` |
| 一意制約違反（Prisma の `P2002`）を握りつぶす | 利用者向けエラーへ変換する |
| `body.total` / `body.price` / `body.discount` を使う | サーバー側で再計算する |
| `catch { return true }` で許可に倒す | 拒否側に倒す |

## F SSRF と外部 I/O

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `fetch(url)` / `axios.get(url)` / got / undici、Puppeteer・Playwright の `page.goto(url)` に利用者の URL を渡す | 論理 ID から固定宛先へ変換する。任意 URL が必要なら名前解決後の IP を検査する |
| リダイレクトを既定（`redirect: 'follow'`）のまま追う、axios の既定の追従 | `redirect: 'manual'` / axios の `maxRedirects: 0`。追うなら各ホップを再検査する |
| timeout 未設定 | `AbortSignal.timeout()`（Node 17.3.0 / 16.14.0〜）。fetch は Node 18 からフラグ不要 |
| `NODE_TLS_REJECT_UNAUTHORIZED=0`、`rejectUnauthorized: false` | TLS 検証を無効化しない |
| 外部 API の応答を型アサーション（`as T`）だけで使う | zod の `safeParse` などで実行時に検証する |
| `express.json()` の limit を大きくする・外す | 既定は `'100kb'`。受け付ける `type` を限定する |
| `req.query.q` を string と決めつける（同名パラメータで配列になる）、`Number(x) \|\| 20` のような黙った既定値 | 型を検証して配列を拒否する。変換の失敗は 400 にする |
| クライアント側のバリデーションだけで保存する | UX にすぎない。サーバー側で同じ制約を強制する |

## G ファイル

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `path.join(base, userPath)`、`fs.readFile` / `writeFile` / `rm` / `rename` に利用者の値 | `fs.realpath` で解決したうえで `path.relative(base, target)` が `..` で始まらないか・絶対パスでないかを確認する。`p.startsWith(base)` で判定しない |
| `res.sendFile(userPath)`（root 指定なし） | `root` オプションで基準ディレクトリに閉じ込める（root 未指定だと絶対パスが必要で、利用者入力を含めると危険と docs が警告） |
| multer の `file.originalname` / `file.mimetype` を保存名や形式の判定に使う | `originalname` はクライアント申告値（README 明記）。保存名はサーバーで生成する。形式は file-type（マジックバイトによるベストエフォートの判定で、無害の保証ではない）と画像の再デコードで確認する |
| multer の `limits` 未設定 | `fileSize` の既定は無制限。`limits` はリクエスト全体に掛かる |
| sharp の `limitInputPixels: false` / `0` | 既定（約 2.7 億ピクセル）を外さない。出力時は既定でメタデータを落とし、`keepMetadata()` / `withMetadata()` で保持する |
| adm-zip / unzipper / tar でエントリ名を検証せずに展開する | 各エントリ名（`..`・絶対パス・symlink）と合計サイズ・ファイル数を検証する |

## H 情報露出・ログ・本番設定

| 危険・要注意 | 安全な代替・確認点 |
|---|---|
| `res.status(500).json({ error: err.message, stack: err.stack })`、Next のエラーメッセージをクライアントへ返す | 一般化したメッセージとリクエスト ID |
| `NEXT_PUBLIC_*` / `VITE_*` に秘密を入れる、クライアントから `process.env` の秘密を参照する | 公開用の変数はビルド時にクライアントバンドルへ埋め込まれる。公開してよいキーだけにする |
| Next の `productionBrowserSourceMaps: true`、Vite の `build.sourcemap: true` を公開環境で有効にする | どちらも既定は無効。有効にするなら sourcesContent に秘密や内部エンドポイントが無いか確認する |
| Express の `app.set('trust proxy', true)` | true は X-Forwarded-For の最左要素をクライアント IP とみなす。段数か CIDR で指定し、直接経路を閉じる |
| `console.log(req.headers)` / `console.log(req.body)`、Sentry・APM へ Cookie や Authorization を送る | pino の `redact` などでマスクし、本文を丸ごと記録しない |

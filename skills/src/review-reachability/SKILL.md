---
name: review-reachability
description: 差分が触れるアプリの入口（ルート・ハンドラ）とインフラのリソース（LB・WAF・Security Group・CloudFront・API Gateway・Lambda Function URL・ECS サービス）について、インターネットから届くか・どんな統制が効いているか・既存の公開面か・公開範囲が拡大／縮小したかを、IaC（Terraform / ecspresso jsonnet）で判定し、設定されていれば AWS のメタデータ専用ロールでライブ裏取りして返すとき。到達性コンテキスト（表と JSON）を返し、公開範囲の変更だけ指摘にする。コードは修正しない。「到達性を調べて」「この入口は公開されている？」「公開範囲が変わるか見て」「WAF や認証で塞がれているか確認して」等で発動。セキュリティレビュー（review-web-security と dotfiles-code-review）が、重要度の判定材料としてこのスキルを呼ぶ。
allowed-tools: [Bash, Read, Grep, Glob]
---

# /review-reachability

`<base>...HEAD` の差分が触れる入口（アプリ）とリソース（インフラ）について、到達性コンテキストを返す。レビューの重要度を「誰がそこへ届くか」で決めるための材料を作る単一責務のスキルで、脆弱性そのものは探さない。ファイルは編集しない。

- 到達性は IaC で判定し、ライブで裏取りする。ライブは未マージの現状なので base 側の IaC に対応し、HEAD の IaC は「マージ後の状態」に対応する。drift は「base の IaC とライブ」の食い違いで、そのときは現状の姿としてライブを正とする。HEAD とライブの食い違いは drift ではなくこの PR の変更で、`exposure_change` で扱う。
- ライブ確認の入口は `skill-aws-reach` だけ。ラッパーは許可した Describe / Get の項目だけを射影して返す。生の `aws` は sandbox 内に残してあり、ここからは使わない。
- 根拠の考え方: 攻撃者の足場の語彙は CVSS v4.0 の Exploitability（AV/AC/AT/PR/UI）、検出と検証を分ける考え方は NIST SP 800-115 による。
  - https://www.first.org/cvss/v4.0/specification-document
  - https://csrc.nist.gov/pubs/sp/800/115/final

## Input

- `--base=<branch>`: optional。解決は `skill-resolve-diff` に委譲する（`origin/master`、無ければ `origin/main`）。

## 設定

値は公開 dotfiles に書かない。ハブリポジトリの `settings.local.json` の `env` などで渡す。このスキルは値を表示しない（設定の有無だけを書く）。

- `REVIEW_REACH_IAC_PATHS`: コロン区切りの IaC 正本リポジトリの絶対パス。現在のリポジトリは常に探索対象に含める。
- `SKILL_AWS_REACH_PROFILE`: `skill-aws-reach` が使う AWS プロファイル。SecurityAudit 相当のメタデータ専用ロールのプロファイルに限る。
  - ラッパーはロールの権限を検証できない。ReadOnlyAccess のようにデータ本体を読める権限を持つロールを宣言しない: 用意するのは利用者の責任で、権限が広いと許可リストの外側で守る層が無くなるため。
  - SecurityAudit: https://docs.aws.amazon.com/aws-managed-policy/latest/reference/SecurityAudit.html
  - 未設定なら AWS を一切呼ばず、IaC のみで判定する。
- `SKILL_AWS_REACH_REGION`: `--region` が無いときの既定リージョン。任意。
- `SKILL_AWS_REACH_ACCOUNTS`: カンマ区切りの許可アカウント ID。任意。設定時は `whoami` の結果と照合され、不一致ならラッパーが `refused` を返す。

## Scope

対象:
- アプリの入口: 差分で変更されたルート定義・ハンドラ、および変更された関数を呼ぶ既存の入口
- インフラのリソース: 差分の IaC（`*.tf` `*.tfvars` `*.hcl` `*.jsonnet` `*.libsonnet`）のうち公開範囲・統制に関わるもの

対象外:
- コードの修正
- 脆弱性の探索と重要度の最終判定: `review-web-security` と `dotfiles-code-review`（このスキルは到達性だけを返す）
- IaC の構成・命名・IAM の妥当性: `dotfiles-code-review` の iac
- ライブの書き込み・データ本体の読み取り・設定の変更

## Workflow

`<SKILL_DIR>` はこのスキルのディレクトリの絶対パス（`~/.claude/skills/review-reachability`）とする。相対パスにしない: Read の cwd はレビュー対象のリポジトリなので、`references/...` のままでは存在していても読めない。

1. 差分を解決する:

```bash
skill-resolve-diff --base <base>
```

2. base ブランチが解決できなければ `ブランチ <base> が見つかりません` と伝えて終了。`files` が空なら `レビュー対象のファイルがありません` と伝えて終了。
3. `files` を `<TARGET_FILES>`、`diff` を `<DIFF_CONTEXT>` として保持する。`truncated` が true のときは `truncated_files` を Read で全文読み、切り詰めが起きた事実と落ちたファイル一覧を `確認できなかった範囲` に書く。黙って落とさない: 切断位置は commit が増えるたびに動くため、同じ PR でも実行ごとに到達性の範囲が変わる。
4. `<SKILL_DIR>/references/iac-signals.md` を Read する。読めなければ止めず、IaC の判定を「未確定」として続行し、`確認できなかった範囲` に読めなかったパスと `./install.sh` での再配置を書く。
5. 入口とリソースを列挙し（下記）、IaC で解決し、ライブで裏取りし、判定する。

### 入口・リソースの列挙

- (a) アプリの入口: 差分で変更されたルート定義・ハンドラ、および変更された関数を呼ぶ既存の入口。呼び出し元はリポジトリ内で `rg` / Read により最大 3 ホップまでたどる。HTTP メソッド・パス・ホスト・デプロイ単位（サービス名）を可能な範囲で特定する。base 時点で存在した入口かどうか（既存）も `git show <base>:<path>` や `git grep <base>` で確かめて記録する。
- (b) インフラのリソース: 差分の IaC のうち公開範囲・統制に関わるもの。base 側を `git show <base>:<path>` で読んで比べ、公開範囲の拡大・縮小を判定する。判定の表は `iac-signals.md` に従う。

### IaC での解決

現在のリポジトリと `REVIEW_REACH_IAC_PATHS` の各パスを探索する。パスが存在しなければそのパスを `確認できなかった範囲` に書いて続行する。次の順でたどる。

- 入口 → デプロイ単位（サービス）→ ターゲットグループ → リスナールール → LB（scheme・SG・サブネット）→ WAF
- CloudFront → origin、API Gateway → ルート・authorizer、Lambda Function URL の AuthType
- DNS（Route 53 レコード）→ どの LB・CloudFront・API Gateway へ向くか

証拠は `path:line` で残す。`iac-signals.md` に無い属性・リソース型は推測で判定せず、その統制を `unknown` にする。

変更されたリソースは base 側（`git show <base>:<path>`）と HEAD 側の両方を解決する。base 側はライブとの drift 判定に、HEAD 側は `controls` / `exposure` / `exposure_change`（マージ後の状態）に使う。base に無い新規リソースは base 側が存在しないので、ライブの `not_found` が想定内で、公開でないとも存在しないとも結論しない。

### ライブでの裏取り

1. `SKILL_AWS_REACH_PROFILE` が設定されているかを確認する（値は表示しない）:

```bash
test -n "$SKILL_AWS_REACH_PROFILE"
```

2. 設定されていれば、まず `whoami` を実行する:

```bash
skill-aws-reach whoami
```

3. `status` が `ok` のときだけ、IaC で特定した名前・ID で下の query を 1 件ずつ呼ぶ:

```bash
skill-aws-reach lb --name <lb-name>
skill-aws-reach sg --id <sg-id>
```

| query | 必須引数 |
|---|---|
| `lb` | `--name` または `--arn` |
| `sg` | `--id` |
| `subnet` | `--id` |
| `cloudfront` | `--id` または `--alias` |
| `apigw-rest` | `--id` または `--name` |
| `apigw-http` | `--id` または `--name` |
| `lambda-url` | `--name` |
| `ecs-service` | `--cluster` と `--service` |
| `dns` | `--name`（任意で `--zone-id`） |

- 全 query に `--region` を付けられる（省略時は `SKILL_AWS_REACH_REGION`）。
- `sg` と `subnet` の ID は IaC に実値が無い（参照式）ので、`lb` / `ecs-service` の結果の `security_groups[]` / `subnets[]` から得る。この連鎖は先の結果を待って逐次に呼び、互いに独立な問い合わせは別々の Bash 呼び出しにして並列で呼んでよい。

- `skill-aws-reach` は必ず単独コマンドで呼ぶ。パイプ・`&&`・`;`・`$()`・ファイルへのリダイレクト・環境変数の前置（`SKILL_AWS_REACH_PROFILE=… skill-aws-reach`）を付けない: sandbox 外実行の除外が効くのは単独コマンドのときだけで、付けると sandbox 内に戻って AWS へ届かず失敗する（`gh` と同じ理由）。整形は返った JSON を読んで行い、絞り込みを外側のコマンドに任せない。
- 引数は IaC やコードから読んだ値をそのまま渡さず、正規表現で検証される前提の名前・ID だけを渡す。拒否（exit 2）されたら、その値でのライブ確認は諦めて `確認できなかった範囲` に書く。
- 返った JSON の `status` を見る。変更されたリソースは「base の IaC とライブ」を比べ、食い違えば `drift=detected`（現状の姿はライブを正とする）、一致すれば `none`。HEAD の IaC とライブの食い違いは drift にせず、この PR の変更として `exposure_change` で判定する。
- `not_found`: 新規リソース（base に無い）なら想定内で、`drift` は `unchecked`、公開でないとも存在しないとも結論しない。既存リソースなら名前の特定違い（IaC の値がサフィックス付きの実名と合っていない等）を疑い、`unresolved` に確定方法（どの名前・ID で再問い合わせするか）を書く。
- `unconfigured` / `unauthenticated` / `denied` / `refused` / `failed` は「ライブ未確認（status）」として記録する。公開ではないと結論しない: 確認できていないことと存在しないことは別で、確認していない統制は下記の判定で存在しないものとして扱う。
- `partial` は主問い合わせの結果だけを使い、欠けた副問い合わせ（WAF・route table 等）は「ライブ未確認」として記録する。
- アカウント ID・ARN・プロファイル名は出力に書かない（PR コメントへ転記されるため）。ラッパーの応答に含まれていても、根拠にはリソース種別と名前だけを書く。

### 判定

各 surface に `exposure` / `attacker_position` / `controls` / `existing_public` / `exposure_change` / `evidence` / `drift` / `unresolved` を付ける。

- `exposure` / `attacker_position` / `controls` は HEAD の IaC（マージ後の状態）で判定し、ライブは base 側の裏取りと、変更されていない上流・下流の統制（LB の SG・WAF 等）の確認に使う。`existing_public` は base の IaC とライブで判定する。
- `exposure`: `public` はインターネットから匿名で TCP / HTTPS が届く経路が IaC かライブで確認できたもの。`internal` は private な経路でしか届かないと確認できたもの。どちらも確認できなければ `unknown`。
- `attacker_position`: 到達に必要な最小の足場。`anonymous-internet` / `authenticated-user` / `privileged-user` / `internal-network` / `unknown`。
- `controls`: `waf` / `edge-auth` / `app-auth` / `ip-restriction` / `security-group` / `private-network` の状態を `enforced` / `count-only` / `absent` / `unknown` で書く。
- 確認できていない統制は存在しないものとして扱い、重要度を下げる理由にしない。`unknown` を `enforced` に読み替えない。
- `app-auth` は、コード側の認証ミドルウェア・ルート定義のガードを Read して判定する。読めなければ `unknown`。
- 統制に数えるのは、サーバ側で検証されて効くものだけ。自己申告値（ヘッダ・User-Agent・クライアントが決める ID・署名検証されない Cookie）は統制に数えない: クライアントが任意に決められ、サーバが存在確認・書式検査・署名検証をしないため。
- WAF は `Count` 固定のルール・`RuleActionOverrides` で `Count` に上書きされたルールを `enforced` にしない。`count-only` と書く。`rule_action_overrides`・`has_scope_down`（一部のリクエストにしか効かない）・`firewall_manager_rule_groups`（Firewall Manager 管理のグループ）が返ったときも同じ表で読む（`iac-signals.md` の WAF の節）。
- `existing_public`: base 時点で公開されていたか。`yes` / `no` / `unknown`。
- `exposure_change`: (a) は入口そのものの追加・既存入口への変更を、(b) は base の IaC と HEAD の IaC（マージ後）を比べた公開範囲を判定する。`widened` / `narrowed` / `none` / `unknown`。
- `unresolved`: 確定しない理由と、何をどこで読めば確定するか。確定していれば `null`。

(b) の `widened` / `narrowed` は指摘として出す（下の exposure findings）。

### 入口が特定できないとき

入口が 1 つも特定できない、または IaC が見つからないときは `status=unresolved` とし、表は「未確定」行だけにする。止めない: 呼び出し側は全指摘を「到達性: 未確定」として扱い、レビューを続ける。

## 出力

次の順で出力する。見出しは逐語で使う。

### 1. 到達性コンテキスト

1 行目に情報源の状態を書く。アカウント ID・ARN・プロファイル名は書かない。

```text
## 🌐 到達性コンテキスト

情報源: IaC=<探索したリポ数>件 / ライブ=<ok|unconfigured|unauthenticated|denied|refused|failed>
```

続けて表を出す。ID は下の JSON の `id` と一致させる。表の `到達性` と `既存の公開面` は JSON の値を次のとおり写した語で書く: `exposure` は public→公開 / internal→内部のみ / unknown→未確定、`existing_public` は yes→該当 / no→非該当 / unknown→不明。

```markdown
| ID | 入口・リソース | 到達性 | 攻撃者の立ち位置 | 統制 | 既存の公開面 | 公開範囲の変化 | 根拠 | 未確定の理由・確定方法 |
|----|--------------|--------|----------------|------|------------|--------------|------|----------------------|
```

### 2. JSON（下流エージェント用）

表の直後に fenced の `json` ブロックを置く。キーは固定。

```json
{
  "status": "ok | partial | unresolved",
  "live": "ok | unconfigured | unauthenticated | denied | refused | failed",
  "surfaces": [
    {
      "id": "S1",
      "kind": "app-entry | infra-resource",
      "name": "GET /api/orders/{id}",
      "files": ["path:line"],
      "exposure": "public | internal | unknown",
      "attacker_position": "anonymous-internet | authenticated-user | privileged-user | internal-network | unknown",
      "controls": [
        { "type": "waf | edge-auth | app-auth | ip-restriction | security-group | private-network", "state": "enforced | count-only | absent | unknown", "evidence": "IaC path:line または ライブ <query>: <項目>=<値>" }
      ],
      "existing_public": "yes | no | unknown",
      "exposure_change": "widened | narrowed | none | unknown",
      "drift": "none | detected | unchecked",
      "evidence": ["..."],
      "unresolved": "何を・どこで読めば確定するか | null"
    }
  ]
}
```

- `status`: 全 surface が確定していれば `ok`、未確定が混じれば `partial`、入口もリソースも特定できなければ `unresolved`。
- `live`: `whoami` の `status`。`SKILL_AWS_REACH_PROFILE` 未設定なら `unconfigured`。個別 query の `denied` / `not_found` / `partial` はここに書かず、該当 surface の `drift=unchecked` と `unresolved` に書く。情報源行の `ライブ=` も同じ値。
- `drift`: 「base の IaC とライブ」の食い違い。ライブで確認できなかったとき（個別 query の `denied` / `not_found` / `partial` を含む）と新規リソースは `unchecked`。
- `evidence` と `controls[].evidence`: リソース種別と名前だけを書く。アカウント ID・ARN を書かない。

### 3. exposure findings

(b) の `widened` / `narrowed` があるときだけ出す。形式は `review-web-security` の `references/output-discipline.md` の「出力フォーマット」に従い、**観点** は逐語で `到達性・公開範囲の変更` とする。

- `Source→Sink` の欄は「欠けている検査: …」の形で、拡大なら何が外れて・何が足されて到達できるようになるかを書く。
- `到達性` と `既存の公開面` は、該当 surface の値を上の写像した語（公開 / 内部のみ / 未確定、該当 / 非該当 / 不明）で書く。
- `widened` の `重要度案` は `output-discipline.md` の付け方（Impact × Likelihood の 3×3）に従う。脆弱性を伴わない公開範囲の変更の Impact は、守られていた入口が扱うデータ・機能の重要度で決める: 個人データ・機密データ・管理機能・決済 → HIGH、一般の認証後機能 → MEDIUM、公開してよい静的内容のみ → LOW、判別できなければ MEDIUM。Likelihood は変更後の攻撃者の立ち位置で決める。
- 攻撃手順・PoC は書かず、公開範囲の変化と、塞ぐ・確かめる方向だけを書く。
- 縮小（`narrowed`）はセキュリティの指摘ではなく既存利用者への影響の確認なので、マトリクスに掛けず固定で Should とする。問題点に「既存の利用者・連携先が届かなくなる可能性」を書く。

### 4. 確認できなかった範囲

```text
#### 確認できなかった範囲
- （読めなかった IaC リポ・ライブ未確認のリソース・たどりきれなかった呼び出し元・切り詰めで落ちたファイル等。無ければ「なし」）
```

到達性が未確定の項目は「何を・どこで読めば確定するか」を書く。

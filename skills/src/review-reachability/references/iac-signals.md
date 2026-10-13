# IaC シグナル表

`review-reachability` が、公開範囲と統制を IaC から判定するときの表。Terraform（AWS provider）のリソース型・属性と、ecspresso の jsonnet 項目を持つ。

- 属性名・ブロック名は Terraform AWS provider の公式ドキュメントと照合済み。表にある属性・値だけで判定する。表に無いリソース型・属性・値は推測で判定せず、その統制を `unknown` にして `unresolved` に読むべき場所を書く。
- 値が変数・`locals`・モジュール出力・ecspresso の外部参照（tfstate・環境変数）で解決されるときは、参照元までたどって実値を確定する。たどれなければ `unknown`。
- 「拡大」「縮小」は base の IaC と HEAD の IaC（マージ後の状態）の同じリソースの比較で決める。ライブは未マージの現状で base に対応するので、HEAD とライブの食い違いを拡大・縮小の根拠にしない。リソースの新規追加は、追加されたものが公開側の値なら拡大、削除は縮小として扱う。
- 状態の語彙は SKILL.md の `controls` と同じ: `enforced`（効く）/ `count-only`（記録だけで止めない）/ `absent` / `unknown`。

## 到達性の経路

入口は次の順でたどる。上流のどれか 1 つでも `internal` が確定すれば、その経路は内部のみ。下流が公開でも上流が塞がれていれば公開にならない。複数の経路があるときは、最も開いている経路で判定する。

```text
DNS（aws_route53_record）→ CloudFront / API Gateway / LB
  → WAF → リスナールール → ターゲットグループ → ECS サービス（awsvpc のサブネット・SG）
Lambda Function URL（DNS・LB を経由せず直接）
```

## LB（aws_lb / aws_lb_listener / aws_lb_listener_rule）

| リソース・属性 | 値 | 判定 |
|---|---|---|
| `aws_lb.internal` | `false` または未指定（既定は `false`） | 公開（internet-facing）。サブネット・SG が許すときに届く |
| `aws_lb.internal` | `true` | 内部のみ（internal） |
| `aws_lb.load_balancer_type` | `application` / `network` / `gateway` | 種別。WAF は `application` にだけ関連付けられる。`network` の SG は `security_groups` を持つ場合だけ効く |
| `aws_lb.security_groups` | SG への参照 | SG の表で判定する |
| `aws_lb.subnets` / `subnet_mapping` | サブネットへの参照 | サブネットの表で判定する。`internal=false` でも public サブネットでなければ届かない |
| `aws_lb_listener.port` / `protocol` | `80` / `443`、`HTTP` / `HTTPS` | 届くポート。`HTTP` の default_action が `redirect` なら HTTPS へ誘導するだけで、HTTP 側のバックエンドは公開にしない |
| `aws_lb_listener.default_action.type` | `forward` | ターゲットへ到達する |
| 同上 | `fixed-response` | ターゲットへ到達しない（固定応答だけ） |
| 同上 | `redirect` | ターゲットへ到達しない |
| 同上 | `authenticate-oidc` / `authenticate-cognito` | エッジ認証。次の `forward` の前段で `edge-auth` を `enforced` にする。`type` の値はハイフン区切りで、設定ブロック名は `authenticate_oidc` / `authenticate_cognito`。その中の `on_unauthenticated_request` が `allow` のときは未認証でも通すので `enforced` にしない |
| `aws_lb_listener_rule.condition.host_header` / `path_pattern` | 値 | どの入口（ホスト・パス）がどのターゲットへ向くかを決める。統制ではない |
| `aws_lb_listener_rule.condition.source_ip` | 特定 CIDR | `ip-restriction` を `enforced`。`0.0.0.0/0` を含む値は制限にならず `absent` |
| `aws_lb_listener_rule.condition.http_header` / `query_string` | 値 | 自己申告値。統制に数えない |
| `aws_lb_listener_rule.action.type` | 上の `default_action.type` と同じ | 同上。`priority` の小さいルールが先に評価される |

## Security Group・ネットワーク

| リソース・属性 | 値 | 判定 |
|---|---|---|
| `aws_security_group.ingress.cidr_blocks` / `ipv6_cidr_blocks` | `0.0.0.0/0` / `::/0` | 匿名のインターネットから届く（`security-group` は `absent`）。ポート範囲（`from_port` / `to_port`）と `protocol`（`-1` は全プロトコル）も読む |
| 同上 | 特定の CIDR・社内レンジ | 制限あり（`security-group` は `enforced`）。レンジの広さを `evidence` に書く |
| `aws_security_group.ingress.security_groups` / `self` / `prefix_list_ids` | SG・プレフィックスリストへの参照 | 参照元が公開でなければ内部のみ。参照元の SG をたどる。プレフィックスリストの中身が読めなければ `unknown` |
| `aws_vpc_security_group_ingress_rule.cidr_ipv4` / `cidr_ipv6` | `0.0.0.0/0` / `::/0` | `aws_security_group.ingress` の `0.0.0.0/0` と同じ。`ip_protocol` と `from_port` / `to_port` を読む |
| 同上 `referenced_security_group_id` / `prefix_list_id` | 参照 | `aws_security_group.ingress.security_groups` と同じ |
| `aws_security_group_rule`（`type = "ingress"`） | `cidr_blocks` に `0.0.0.0/0` | `aws_security_group.ingress` と同じ。`source_security_group_id` は参照扱い |
| `aws_subnet.map_public_ip_on_launch` | `true` | 起動時に public IP を付ける。経路が無ければ到達はしないので単独では公開の根拠にしない |
| `aws_route.destination_cidr_block` / `destination_ipv6_cidr_block` | `0.0.0.0/0` / `::/0` で `gateway_id` が `aws_internet_gateway` | そのルートテーブルに関連付いたサブネットは public |
| 同上 | `nat_gateway_id` | 外向きだけ。private サブネット（インターネットから届かない） |
| `aws_route_table_association` / `aws_main_route_table_association` / `aws_default_route_table` | サブネット ↔ ルートテーブル | サブネットがどのルートテーブルに属するか。明示の関連付けが無いサブネットは VPC の main route table に属する |

## WAF（aws_wafv2_web_acl / aws_wafv2_web_acl_association）

`waf` を `enforced` にできるのは、対象リソースに関連付いていて、止めるルールが `Block`（または `Captcha` / `Challenge`）で効く場合だけ。次のものは `Block` に見えても止めないので、`count-only` として扱う: 個別ルールの上書き（API の `RuleActionOverrides`・旧来の `ExcludedRules`。Terraform には `excluded_rule` が無く `rule_action_override` で表す）、`rule_group_reference_statement` の `rule_action_override`、`scope_down_statement`（一部のリクエストにしか効かない）、Firewall Manager 管理のルールグループ（Web ACL の定義だけでは中身が読めないので、ライブの `firewall_manager_rule_groups` を読み、読めなければ `unknown`）。

| リソース・属性 | 値 | 判定 |
|---|---|---|
| `aws_wafv2_web_acl_association.resource_arn` / `web_acl_arn` | 対象の LB・API Gateway（REST API）ステージへの参照。HTTP API のステージには関連付けられない | 関連付けがあって初めて対象に効く。関連付けが無い Web ACL は `absent` |
| `aws_cloudfront_distribution.web_acl_id` | Web ACL への参照 | CloudFront への関連付けはこの属性（association リソースは使わない）。無ければ `absent` |
| `aws_wafv2_web_acl.scope` | `CLOUDFRONT` / `REGIONAL` | CloudFront 用は `CLOUDFRONT`、LB・API Gateway 用は `REGIONAL`。対象と合わなければ関連付けできない |
| `default_action` | `block {}` | 既定で拒否。許可するルールに合致したものだけ通る |
| 同上 | `allow {}` | 既定で許可。`Block` ルールに合致したものだけ止まる |
| `rule.action` | `block {}` | 止める（`enforced`） |
| 同上 | `count {}` | 数えるだけで止めない（`count-only`） |
| 同上 | `allow {}` | 通す。以降のルールが評価されない |
| 同上 | `captcha {}` / `challenge {}` | 止める方向の統制だが、自動化されたクライアントの扱いは設定による。`enforced` にする前に `evidence` へ書く |
| `rule.override_action`（`managed_rule_group_statement` 等のグループ参照のルール） | `none {}` | グループ内の各ルールのアクションがそのまま効く |
| 同上 | `count {}` | グループ全体が `count-only`。`none` → `count` への変更は拡大（下の「拡大・縮小の判定」参照） |
| `rule.statement.managed_rule_group_statement.rule_action_override`（`rule_group_reference_statement` にも同名の属性がある） | `action_to_use { count {} }` | 指定した個別ルール（`name`）だけ `count-only`。グループが `none {}` でも、その個別ルールは止めない |
| `rule.statement.managed_rule_group_statement.scope_down_statement` / `rate_based_statement.scope_down_statement` | 設定あり | 条件に合うリクエストにだけルールが効く。効く範囲を `evidence` に書き、全リクエストに効くとは読まない |
| 同上 | `action_to_use { block {} }` | 個別ルールだけ止める |
| `rule.statement.rate_based_statement` | `limit` 等 | 回数の制限。`rule.action` が `block {}` なら `enforced`、`count {}` なら `count-only` |
| `rule.statement` のその他の型 | — | `rule.action` で上の判定を適用する。表に無い statement の中身は推測しない |

## CloudFront（aws_cloudfront_distribution）

| 属性 | 値 | 判定 |
|---|---|---|
| `enabled` | `true` / `false` | `false` は配信停止。`true` なら `aliases` のドメインから届く |
| `aliases` | ドメイン名 | DNS の `aws_route53_record` と突き合わせる |
| `origin.domain_name` / `origin_id` | origin（LB・S3・API Gateway 等） | `default_cache_behavior.target_origin_id` / `ordered_cache_behavior.target_origin_id` と突き合わせ、どの入口がどの origin へ向くかを決める |
| `origin.origin_access_control_id` | 設定あり | S3・Lambda Function URL origin への直接アクセスを CloudFront 経由に限る。`absent` なら origin が単独で公開され得る（origin 側の認可・バケットポリシーも読む） |
| `origin.custom_header` | `name` / `value` | 共有秘密のヘッダを origin に付けて、origin 側で検証する構成かもしれない。origin 側が検証していることを確認できなければ統制に数えない |
| `default_cache_behavior.viewer_protocol_policy` / `ordered_cache_behavior.viewer_protocol_policy` | `allow-all` / `redirect-to-https` / `https-only` | 経路の暗号化。到達性そのものは変わらない |
| `ordered_cache_behavior.path_pattern` | パス | パスごとの origin・統制の違いを読む。`default_cache_behavior` と別の origin へ向くことがある |
| `default_cache_behavior.trusted_key_groups` / `ordered_cache_behavior.trusted_key_groups` | 設定あり | 署名付き URL / Cookie を要求する（`edge-auth` を `enforced`）。無ければ `absent` |
| `lambda_function_association` / `function_association` | `event_type = "viewer-request"` | 認証を実装しているかもしれないが、関数の中身を読むまで `edge-auth` は `unknown` |
| `web_acl_id` | Web ACL への参照 | WAF の表で判定する |

## API Gateway（aws_api_gateway_* / aws_apigatewayv2_*）

| リソース・属性 | 値 | 判定 |
|---|---|---|
| `aws_api_gateway_rest_api.endpoint_configuration.types` | `EDGE` / `REGIONAL` | インターネットから届く（公開）。リソースポリシーで絞られていなければ匿名で到達する |
| 同上 | `PRIVATE` | VPC エンドポイント経由だけ（`private-network`）。`vpc_endpoint_ids` とリソースポリシーも読む |
| `aws_api_gateway_rest_api.disable_execute_api_endpoint` | `true` | 既定の `execute-api` ドメインを使えない。カスタムドメイン経由だけが入口 |
| `aws_api_gateway_rest_api_policy.policy` / `aws_api_gateway_rest_api.policy` | 条件キー（`aws:SourceIp` / `aws:SourceVpce` 等） | 条件でソースを絞っているときだけ `ip-restriction` / `private-network`。本文を読んで条件が実際に効くか確かめる |
| `aws_api_gateway_method.authorization` | `NONE` | 認証なし（`edge-auth` は `absent`）。`api_key_required = true` でも API キーは認証の代わりにならず、`absent` のまま |
| 同上 | `AWS_IAM` / `COGNITO_USER_POOLS` / `CUSTOM` | 認証あり（`enforced`）。`CUSTOM` は `authorizer_id` の authorizer の中身も読む |
| `aws_api_gateway_authorizer.type` | `TOKEN` / `REQUEST` / `COGNITO_USER_POOLS` | authorizer の種別。メソッドに `authorizer_id` が付いていなければ効かない |
| `aws_apigatewayv2_api.protocol_type` | `HTTP` / `WEBSOCKET` | 種別 |
| `aws_apigatewayv2_api.disable_execute_api_endpoint` | `true` | `aws_api_gateway_rest_api` の同名属性と同じ |
| `aws_apigatewayv2_route.authorization_type` | `NONE` | 認証なし（`absent`） |
| 同上 | `JWT` / `AWS_IAM` / `CUSTOM` | 認証あり（`enforced`）。`authorizer_id` が付いているかも読む。`JWT` は `aws_apigatewayv2_authorizer` の `issuer` / `audience` も読む |
| `aws_apigatewayv2_authorizer.authorizer_type` | `JWT` / `REQUEST` | authorizer の種別 |
| `aws_apigatewayv2_integration` / `aws_apigatewayv2_vpc_link` | 統合先 | どのバックエンドに向くか |
| `aws_apigatewayv2_stage` / `aws_api_gateway_stage` | ステージ | 公開されるステージ。WAF を `aws_wafv2_web_acl_association` で関連付けられるのは REST API のステージだけ（HTTP API は不可） |

## Lambda Function URL（aws_lambda_function_url）

| 属性 | 値 | 判定 |
|---|---|---|
| `authorization_type` | `NONE` | 認証なしで URL から実行できる（公開・`edge-auth` は `absent`）。`aws_lambda_permission` の `principal = "*"` と `function_url_auth_type = "NONE"` が併せて必要なので、どちらも読む |
| 同上 | `AWS_IAM` | IAM 認証（`enforced`）。呼び出す主体への権限付与は IAM 側で確かめる |
| `cors` | 設定あり | ブラウザからのオリジンを許可する設定。サーバ側の認可ではなく、統制に数えない |
| `invoke_mode` | `BUFFERED` / `RESPONSE_STREAM` | 到達性には影響しない |

## ECS（aws_ecs_service と ecspresso の jsonnet）

Terraform の `aws_ecs_service` と ecspresso の service 定義は同じ意味の項目を持つ。ecspresso の項目名は ECS API（`CreateService`）の名前と対応する（`networkConfiguration.awsvpcConfiguration.assignPublicIp` 等）。ecspresso 固有の構文は扱わず、API 名で読めない値は `unknown` にする。

| 意味 | Terraform | ecspresso jsonnet | 値と判定 |
|---|---|---|---|
| public IP の付与 | `network_configuration.assign_public_ip` | `networkConfiguration.awsvpcConfiguration.assignPublicIp` | `ENABLED`（Terraform は `true`）: タスクが public IP を持つ。public サブネットと SG が許せば LB を介さず直接届く。`DISABLED`（Terraform は `false` または未指定）: public IP を持たない |
| 配置サブネット | `network_configuration.subnets` | `networkConfiguration.awsvpcConfiguration.subnets` | サブネットの表で public / private を判定する |
| タスクの SG | `network_configuration.security_groups` | `networkConfiguration.awsvpcConfiguration.securityGroups` | SG の表で判定する |
| LB への登録 | `load_balancer`（`target_group_arn` / `container_name` / `container_port`） | `loadBalancers`（`targetGroupArn` / `containerName` / `containerPort`） | どのターゲットグループ（= どの LB のリスナールール）経由で入口になるかを決める。無ければ LB 経由では届かない |
| 起動タイプ | `launch_type` | `launchType` | `FARGATE` / `EC2`。到達性は上の項目で決まる |

- ターゲットグループ → リスナールールは、`aws_lb_listener_rule.action` の `target_group_arn`（`forward` ブロックのときはその中の `target_group`）で突き合わせる。
- jsonnet が値を外部参照で受けているときは、参照元（tfstate の出力・環境変数）まで読めなければ `unknown`。

## DNS（aws_route53_record / aws_route53_zone）

| リソース・属性 | 値 | 判定 |
|---|---|---|
| `aws_route53_record.name` / `type` | レコード名・種別 | 入口のホスト名 → 向き先の対応 |
| `aws_route53_record.alias.name` | LB / CloudFront / API Gateway のドメイン | その向き先リソースの判定を引き継ぐ |
| `aws_route53_record.records` | IP・ホスト名 | 向き先を突き合わせる。IP は到達できる実体が不明なら `unknown` |
| `aws_route53_zone` の `vpc` ブロック | 設定あり | private ホストゾーン。インターネットから名前解決できない（`private-network`） |

DNS が無くても、LB・API Gateway・Lambda Function URL は既定のドメインで届き得る。DNS に無いことを内部のみの根拠にしない。

## 拡大・縮小の判定

base と HEAD の同じリソース・属性を比較する。方向が決まらない変化（表に無い属性）は `unknown`。

| 変化 | 判定 | 補足 |
|---|---|---|
| `aws_lb.internal` が `true` → `false`（または属性を削除） | 拡大 | scheme が internal から internet-facing へ |
| `aws_lb.internal` が `false` → `true` | 縮小 | 既存の利用者・連携先が届かなくなる可能性 |
| `aws_lb.subnets` が private → public サブネット | 拡大 | サブネットの表で判定 |
| SG の ingress に `0.0.0.0/0` / `::/0` を追加、または特定 CIDR → `0.0.0.0/0` | 拡大 | ポート範囲の拡大・`protocol` が `-1` への変更も拡大 |
| SG の ingress から `0.0.0.0/0` を削除、または CIDR を狭める | 縮小 | |
| `aws_lb_listener` / `aws_lb_listener_rule` の追加、`fixed-response` / `redirect` → `forward` | 拡大 | ターゲットへ到達するようになる |
| `forward` → `fixed-response` / `redirect`、リスナー・ルールの削除 | 縮小 | |
| `aws_lb_listener_rule.condition.source_ip` の削除・`0.0.0.0/0` の追加 | 拡大 | |
| `authenticate-oidc` / `authenticate-cognito` の action の削除、`authenticate_oidc` / `authenticate_cognito` 内の `on_unauthenticated_request` の `allow` 化 | 拡大 | |
| WAF の `rule.action` が `block` → `count`（または `allow`） | 拡大 | Block から Count へ |
| WAF の `override_action` が `none` → `count` | 拡大 | |
| WAF の `rule_action_override` で個別ルールを `count` へ上書き、`scope_down_statement` の追加 | 拡大 | 個別ルール・一部のリクエストだけの変化でも指摘する |
| WAF の `default_action` が `block` → `allow` | 拡大 | |
| WAF ルールの削除、`aws_wafv2_web_acl_association` / `web_acl_id` の削除 | 拡大 | 統制が外れる |
| WAF の `count` → `block`、ルール・関連付けの追加 | 縮小 | |
| `aws_api_gateway_method.authorization` / `aws_apigatewayv2_route.authorization_type` が認証あり → `NONE`、`authorizer_id` の削除 | 拡大 | authorizer の削除を含む |
| 同 `NONE` → 認証あり | 縮小 | |
| `aws_api_gateway_rest_api.endpoint_configuration.types` が `PRIVATE` → `EDGE` / `REGIONAL`、リソースポリシーの削除 | 拡大 | |
| 同 `EDGE` / `REGIONAL` → `PRIVATE` | 縮小 | |
| `disable_execute_api_endpoint` が `true` → `false` | 拡大 | 既定ドメインから届く |
| `aws_lambda_function_url.authorization_type` が `AWS_IAM` → `NONE`、`aws_lambda_function_url` の新規追加（`NONE`） | 拡大 | AuthType NONE 化 |
| 同 `NONE` → `AWS_IAM` | 縮小 | |
| `aws_cloudfront_distribution.origin.origin_access_control_id` の削除、`trusted_key_groups` の削除、新しい `aliases` の追加 | 拡大 | origin が単独で公開され得る、または入口が増える |
| CloudFront の `enabled` が `false` → `true` | 拡大 | |
| ECS の `assign_public_ip` / `assignPublicIp` が `DISABLED` → `ENABLED`（または `false` → `true`） | 拡大 | |
| ECS のタスクを private → public サブネットへ移す | 拡大 | |
| ECS の `load_balancer` / `loadBalancers` の追加 | 拡大 | LB 経由の入口が増える |
| 上記の逆方向 | 縮小 | |
| 値は変わったが表で方向が決まらない | `unknown` | `unresolved` に読むべき場所を書く |

どの変化でも、変化したリソースを経由する入口（アプリの入口・ホスト名）を特定して、同じ変化が届く入口を列挙する: 同じ LB・SG・ターゲットグループを共有する他のサービスにも影響が及ぶため。

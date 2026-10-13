#!/usr/bin/env bash

# skill-aws-reach の入出力契約を、偽の aws で固定する。本物を呼ぶと実アカウントへ
# 問い合わせが飛び、応答が環境ごとに変わって検証の軸にならない。
#
# mktemp を使うので、書き込み先を制限したサンドボックス下では $TMPDIR 以外に作れない。
# 「Operation not permitted」で落ちた場合はテストの不具合ではなく実行環境の制約。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
REACH="$REPO_ROOT/bin/skill-aws-reach"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/skill-aws-reach-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

# 本物の aws に届かないよう、PATH は実機の PATH を使わず必要なツールだけを並べる。
TOOLS_BIN="$TEST_ROOT/tools"
FAKE_BIN="$TEST_ROOT/fakes"
FIX="$TEST_ROOT/fixtures"
export CALL_LOG="$TEST_ROOT/calls.log"
export FIXTURES="$FIX"
ALL_CALLS="$TEST_ROOT/all-calls.log"
ALL_OUT="$TEST_ROOT/all-out.log"
mkdir -p "$TOOLS_BIN" "$FAKE_BIN" "$FIX"
: >"$CALL_LOG"
: >"$ALL_CALLS"
: >"$ALL_OUT"

NOJQ_BIN="$TEST_ROOT/nojq"
mkdir -p "$NOJQ_BIN"
for tool in bash jq env mktemp rm date cat; do
  ln -s "$(command -v "$tool")" "$TOOLS_BIN/$tool"
  [ "$tool" = jq ] || ln -s "$(command -v "$tool")" "$NOJQ_BIN/$tool"
done

# 偽の aws。FAKE_FAIL は「<service> <operation>=<種別>」のカンマ区切り（<service> <operation> に * も可）。
# 種別 empty / nonjson は終了コード 0 のまま空出力・非 JSON を返す。FAKE_VARIANT は <service>.<op>.<variant>.json があれば差し替える。
command cat >"$FAKE_BIN/aws" <<'EOF'
#!/usr/bin/env bash
profile="" region="" output="" connect="" read_timeout=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) profile="$2"; shift 2 ;;
    --region) region="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --cli-connect-timeout) connect="$2"; shift 2 ;;
    --cli-read-timeout) read_timeout="$2"; shift 2 ;;
    *) break ;;
  esac
done
service="$1" op="$2"
shift 2
printf 'aws %s %s %s\n' "$service" "$op" "$*" >>"$CALL_LOG"
printf 'env %s %s profile=%s region=%s KEY=%s SECRET=%s TOKEN=%s AWS_PROFILE=%s PAGER=[%s] SECTOKEN=%s DEFPROFILE=%s ENDPOINT=%s CONFIG=%s CABUNDLE=%s OUTPUT=%s CONNECT=%s READ=%s\n' \
  "$service" "$op" "$profile" "${region:-unset}" "${AWS_ACCESS_KEY_ID-unset}" \
  "${AWS_SECRET_ACCESS_KEY-unset}" "${AWS_SESSION_TOKEN-unset}" "${AWS_PROFILE-unset}" \
  "${AWS_PAGER-unset}" "${AWS_SECURITY_TOKEN-unset}" "${AWS_DEFAULT_PROFILE-unset}" \
  "${AWS_ENDPOINT_URL-unset}" "${AWS_CONFIG_FILE-unset}" "${AWS_CA_BUNDLE-unset}" \
  "${output:-unset}" "${connect:-unset}" "${read_timeout:-unset}" >>"$CALL_LOG"

if [ "$service" = configure ]; then
  [ -n "${FAKE_PROFILE_REGION:-}" ] || exit 1
  echo "$FAKE_PROFILE_REGION"
  exit 0
fi

IFS=, read -r -a fails <<<"${FAKE_FAIL:-}"
for item in ${fails[@]+"${fails[@]}"}; do
  key="${item%=*}" kind="${item#*=}"
  [ "$key" = "$service $op" ] || [ "$key" = "*" ] || continue
  case "$kind" in
    expired)   echo "An error occurred (ExpiredToken) when calling the $op operation: The security token included in the request is expired" >&2 ;;
    noprofile) echo "The config profile (audit-profile) could not be found" >&2 ;;
    denied)    echo "An error occurred (AccessDenied) when calling the $op operation: User: arn:aws:sts::${FAKE_ACCT}:assumed-role/audit/s is not authorized to perform: x:Y" >&2 ;;
    notfound)  echo "An error occurred (ResourceNotFoundException) when calling the $op operation: not here" >&2 ;;
    empty)     exit 0 ;;
    nonjson)   echo "<html>not json</html>"; exit 0 ;;
    *)         echo "An error occurred (InternalFailure) when calling the $op operation: boom" >&2 ;;
  esac
  exit 254
done

file="$FIXTURES/$service.$op.json"
if [ -n "${FAKE_VARIANT:-}" ] && [ -f "$FIXTURES/$service.$op.$FAKE_VARIANT.json" ]; then
  file="$FIXTURES/$service.$op.$FAKE_VARIANT.json"
fi
case "$*" in
  *association.main*) [ ! -f "$FIXTURES/$service.$op.main.json" ] || file="$FIXTURES/$service.$op.main.json" ;;
  *association.subnet-id*) [ "${FAKE_RT_EMPTY:-}" != 1 ] || { echo '{"RouteTables":[]}'; exit 0; } ;;
esac
[ -f "$file" ] || { echo "no fixture: $service $op" >&2; exit 1; }
cat "$file"
EOF
chmod +x "$FAKE_BIN/aws"

# AWS ドキュメントの例示値と同じ書式のダミー。実アカウントの ID を使うと公開リポに実値が残るため。
ACCT=111122223333
ACCT_OTHER=999999999999
export FAKE_ACCT="$ACCT"

fx() {
  local body
  body="$(command cat)"
  printf '%s\n' "${body//@ACCT@/$ACCT}" >"$FIX/$1.$2.json"
}
LB_ARN="arn:aws:elasticloadbalancing:ap-northeast-1:$ACCT:loadbalancer/app/web/abc"

fx sts get-caller-identity <<'EOF'
{"Account":"@ACCT@","UserId":"AIDAEXAMPLE","Arn":"arn:aws:sts::@ACCT@:assumed-role/audit/session"}
EOF

fx elbv2 describe-load-balancers <<'EOF'
{"LoadBalancers":[{"LoadBalancerArn":"arn:aws:elasticloadbalancing:ap-northeast-1:@ACCT@:loadbalancer/app/web/abc","LoadBalancerName":"web","DNSName":"web-1.example.elb.amazonaws.com","Scheme":"internet-facing","Type":"application","SecurityGroups":["sg-0aaa"],"AvailabilityZones":[{"SubnetId":"subnet-0111"},{"SubnetId":"subnet-0222"}]}]}
EOF

fx elbv2 describe-listeners <<'EOF'
{"Listeners":[{"ListenerArn":"arn:aws:elasticloadbalancing:ap-northeast-1:@ACCT@:listener/app/web/abc/l1","Port":443,"Protocol":"HTTPS","DefaultActions":[{"Type":"fixed-response"}]}]}
EOF

fx elbv2 describe-rules <<'EOF'
{"Rules":[
 {"Priority":"10","IsDefault":false,"Conditions":[
   {"Field":"http-header","Values":["SECRET-HEADER-VALUE"],"HttpHeaderConfig":{"HttpHeaderName":"X-Origin-Verify","Values":["SECRET-HEADER-VALUE"]}},
   {"Field":"host-header","Values":["app.example.com"],"HostHeaderConfig":{"Values":["app.example.com"]}}],
  "Actions":[{"Type":"forward"}]},
 {"Priority":"default","IsDefault":true,"Conditions":[],"Actions":[{"Type":"fixed-response"}]}]}
EOF

WAF='{"WebACL":{"Name":"web-acl","DefaultAction":{"Allow":{}},"Rules":[
 {"Name":"rate","Priority":1,"Statement":{"RateBasedStatement":{"Limit":100}},"Action":{"Count":{}}},
 {"Name":"block-bad","Priority":2,"Statement":{"ByteMatchStatement":{}},"Action":{"Block":{}}},
 {"Name":"managed","Priority":3,"OverrideAction":{"None":{}},"Statement":{"ManagedRuleGroupStatement":{"VendorName":"AWS","Name":"AWSManagedRulesCommonRuleSet","RuleActionOverrides":[{"Name":"SizeRestrictions_BODY","ActionToUse":{"Count":{}}}]}}},
 {"Name":"excl","Priority":4,"OverrideAction":{"None":{}},"Statement":{"ManagedRuleGroupStatement":{"VendorName":"AWS","Name":"AWSManagedRulesSQLiRuleSet","ExcludedRules":[{"Name":"SQLi_BODY"}],"ScopeDownStatement":{"ByteMatchStatement":{}}}}},
 {"Name":"ref","Priority":5,"OverrideAction":{"None":{}},"Statement":{"RuleGroupReferenceStatement":{"ARN":"arn:aws:wafv2:ap-northeast-1:@ACCT@:regional/rulegroup/rg/xyz","RuleActionOverrides":[{"Name":"R1","ActionToUse":{"Count":{}}}],"ExcludedRules":[{"Name":"R2"}]}}}],
 "PreProcessFirewallManagerRuleGroups":[{"Name":"fm-pre","Priority":1,"OverrideAction":{"None":{}},"FirewallManagerStatement":{"ManagedRuleGroupStatement":{"VendorName":"AWS","Name":"X","RuleActionOverrides":[{"Name":"F1","ActionToUse":{"Count":{}}}]}}}],
 "PostProcessFirewallManagerRuleGroups":[{"Name":"fm-post","Priority":2,"OverrideAction":{"Count":{}},"FirewallManagerStatement":{"RuleGroupReferenceStatement":{"ARN":"arn:aws:wafv2:ap-northeast-1:@ACCT@:regional/rulegroup/rg2/abc","ExcludedRules":[{"Name":"F2"}]}}}]}}'
printf '%s\n' "$WAF" | fx wafv2 get-web-acl-for-resource
printf '%s\n' "$WAF" | fx wafv2 get-web-acl

fx ec2 describe-security-group-rules <<'EOF'
{"SecurityGroupRules":[
 {"IsEgress":false,"IpProtocol":"tcp","FromPort":443,"ToPort":443,"CidrIpv4":"0.0.0.0/0","Description":"SECRET-SG-DESC"},
 {"IsEgress":true,"IpProtocol":"-1","CidrIpv4":"0.0.0.0/0"},
 {"IsEgress":false,"IpProtocol":"tcp","FromPort":8080,"ToPort":8080,"ReferencedGroupInfo":{"GroupId":"sg-0bbb"},"Description":"SECRET-SG-DESC"}]}
EOF

fx ec2 describe-subnets <<'EOF'
{"Subnets":[{"SubnetId":"subnet-0111","VpcId":"vpc-0abc","MapPublicIpOnLaunch":true}]}
EOF
fx ec2 describe-route-tables <<'EOF'
{"RouteTables":[{"RouteTableId":"rtb-0aaa","Routes":[{"DestinationCidrBlock":"10.0.0.0/16","GatewayId":"local"},{"DestinationCidrBlock":"0.0.0.0/0","GatewayId":"igw-0123"}]}]}
EOF
command cat >"$FIX/ec2.describe-route-tables.main.json" <<'EOF'
{"RouteTables":[{"RouteTableId":"rtb-0main","Routes":[{"DestinationCidrBlock":"0.0.0.0/0","NatGatewayId":"nat-0xyz"}]}]}
EOF

fx cloudfront get-distribution-config <<'EOF'
{"ETag":"E","DistributionConfig":{"Enabled":true,"Aliases":{"Items":["www.example.com"]},
 "Origins":{"Items":[{"Id":"o1","DomainName":"web.example.com","OriginAccessControlId":"","CustomHeaders":{"Items":[{"HeaderName":"X-Origin-Verify","HeaderValue":"SECRET-ORIGIN-VALUE"}]}}]},
 "DefaultCacheBehavior":{"TargetOriginId":"o1","ViewerProtocolPolicy":"redirect-to-https"},
 "CacheBehaviors":{"Items":[{"PathPattern":"/api/*","TargetOriginId":"o1"}]},
 "WebACLId":"arn:aws:wafv2:us-east-1:@ACCT@:global/webacl/cf-acl/1234-abcd"}}
EOF
fx cloudfront list-distributions <<'EOF'
{"DistributionList":{"Items":[{"Id":"E999","Aliases":{"Quantity":0}},{"Id":"E123ABC","Aliases":{"Items":["WWW.example.com"]}}]}}
EOF

fx apigateway get-rest-api <<'EOF'
{"id":"abc123","name":"orders","endpointConfiguration":{"types":["REGIONAL"]},"policy":"{\"Statement\":[{\"Condition\":{\"IpAddress\":{\"aws:SourceIp\":[\"203.0.113.0/24\"]}},\"Resource\":[\"arn:aws:execute-api:*:*:*/*\",\"SECRET-POLICY-BODY\"]}]}"}
EOF
fx apigateway get-rest-apis <<'EOF'
{"items":[{"id":"zzz","name":"other"},{"id":"abc123","name":"orders"}]}
EOF
fx apigateway get-authorizers <<'EOF'
{"items":[{"id":"auth1","name":"jwt","type":"COGNITO_USER_POOLS"}]}
EOF
fx apigateway get-resources <<'EOF'
{"items":[{"id":"r1","path":"/orders","resourceMethods":{
 "GET":{"httpMethod":"GET","authorizationType":"COGNITO_USER_POOLS","authorizerId":"auth1","apiKeyRequired":false},
 "POST":{"httpMethod":"POST","authorizationType":"NONE","apiKeyRequired":true}}}]}
EOF

fx apigatewayv2 get-api <<'EOF'
{"ApiId":"h1","Name":"edge","ProtocolType":"HTTP","DisableExecuteApiEndpoint":true}
EOF
fx apigatewayv2 get-apis <<'EOF'
{"Items":[{"ApiId":"h1","Name":"edge"}]}
EOF
fx apigatewayv2 get-routes <<'EOF'
{"Items":[{"RouteKey":"GET /x","AuthorizationType":"JWT","AuthorizerId":"a1"},{"RouteKey":"$default","AuthorizationType":"NONE"}]}
EOF
fx apigatewayv2 get-authorizers <<'EOF'
{"Items":[{"AuthorizerId":"a1","Name":"jwt","AuthorizerType":"JWT"}]}
EOF

fx lambda get-function-url-config <<'EOF'
{"FunctionUrl":"https://x.lambda-url.ap-northeast-1.on.aws/","AuthType":"NONE","Cors":{"AllowOrigins":["*"]},"InvokeMode":"BUFFERED"}
EOF

fx ecs describe-services <<'EOF'
{"services":[{"launchType":"FARGATE","networkConfiguration":{"awsvpcConfiguration":{"subnets":["subnet-0111"],"securityGroups":["sg-0aaa"],"assignPublicIp":"DISABLED"}},
 "loadBalancers":[{"targetGroupArn":"arn:aws:elasticloadbalancing:ap-northeast-1:@ACCT@:targetgroup/tg/1","containerName":"app","containerPort":8080}]}],"failures":[]}
EOF

fx route53 list-hosted-zones <<'EOF'
{"HostedZones":[{"Id":"/hostedzone/ZPUB","Name":"example.com.","Config":{"PrivateZone":false}},{"Id":"/hostedzone/ZSUB","Name":"api.example.com.","Config":{"PrivateZone":true}}]}
EOF
fx route53 list-resource-record-sets <<'EOF'
{"ResourceRecordSets":[
 {"Name":"app.api.example.com.","Type":"A","AliasTarget":{"DNSName":"web-1.elb.amazonaws.com.","HostedZoneId":"Z","EvaluateTargetHealth":false}},
 {"Name":"zzz.api.example.com.","Type":"A","ResourceRecords":[{"Value":"10.0.0.1"}]}]}
EOF

fx elbv2 describe-rules.unknowncond <<'EOF'
{"Rules":[{"Priority":"5","IsDefault":false,"Conditions":[
 {"Field":"query-string","Values":["SECRET-QS"],"QueryStringConfig":{"Values":[{"Key":"k","Value":"SECRET-QS"}]}},
 {"Field":"future-field","Values":["SECRET-FUTURE"],"FutureConfig":{"Values":["SECRET-FUTURE"]}},
 {"Field":"source-ip","SourceIpConfig":{"Values":["203.0.113.0/24"]}},
 {"Field":"path-pattern","PathPatternConfig":{"Values":["/api/*"]}}],"Actions":[{"Type":"forward"}]}]}
EOF
fx cloudfront get-distribution-config.legacywaf <<'EOF'
{"ETag":"E","DistributionConfig":{"Enabled":true,"Aliases":{"Items":["www.example.com"]},
 "Origins":{"Items":[{"Id":"o1","DomainName":"web.example.com","OriginAccessControlId":""}]},
 "DefaultCacheBehavior":{"TargetOriginId":"o1","ViewerProtocolPolicy":"redirect-to-https"},
 "WebACLId":"a1b2c3d4-5678-90ab-cdef-EXAMPLE11111"}}
EOF
fx apigateway get-rest-api.textpolicy <<'EOF'
{"id":"abc123","name":"orders","policy":"not json: arn:aws:execute-api:us-east-1:@ACCT@:abc123/*/GET/ aws:SourceVpce SECRET-POLICY-BODY"}
EOF
fx route53 list-hosted-zones.dupzone <<'EOF'
{"HostedZones":[{"Id":"/hostedzone/ZPUB","Name":"example.com.","Config":{"PrivateZone":false}},{"Id":"/hostedzone/ZPRV","Name":"example.com.","Config":{"PrivateZone":true}}]}
EOF

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

run() { env -i PATH="$FAKE_BIN:$TOOLS_BIN" TMPDIR="${TMPDIR:-/tmp}" CALL_LOG="$CALL_LOG" FIXTURES="$FIXTURES" FAKE_ACCT="$ACCT" "$@"; }
PROF=SKILL_AWS_REACH_PROFILE=audit-profile

reset_log() { command cat "$CALL_LOG" >>"$ALL_CALLS"; : >"$CALL_LOG"; }

expect_json() {
  local name="$1" json="$2" filter="${3//@ACCT@/$ACCT}"
  printf '%s' "$json" | jq -e "$filter" >/dev/null || fail "$name: $filter が成り立たない: $json"
}

# 出力を記録して返す（秘匿値が混ざっていないかを最後にまとめて見る）。
reach() {
  local out
  out="$(run "$PROF" "$@")"
  printf '%s\n' "$out" >>"$ALL_OUT"
  printf '%s' "$out"
}

aws_calls() { { rg '^aws ' "$CALL_LOG" || true; } | { rg -v '^aws configure' || true; } | wc -l | tr -d ' '; }

# --- 引数不正は exit 2 で、aws を呼ばない ---
for args in "" "bogus" "sg" "sg --id" "sg --id --region" "sg --id -x" "sg --id sg-XYZ" \
  "sg --id sg-1 --region bad" "sg --id sg-1 --id sg-2" "sg --id sg-1;ls" "sg --id sg-1 --name x" \
  "lb" "lb --name a --arn arn:aws:elasticloadbalancing:x" "lb --arn notarn" "lb --name -foo" \
  "whoami --id sg-1" "dns" "dns --name -x" "ecs-service --cluster c" "cloudfront --id E1 --alias a.com" \
  "subnet --id sg-1" "lambda-url" "apigw-rest" "apigw-http --id h1 --name x"; do
  code=0
  # shellcheck disable=SC2086
  run "$PROF" "$REACH" $args >/dev/null 2>&1 || code=$?
  [ "$code" -eq 2 ] || fail "引数不正 '$args' は exit 2 のはずが $code"
done
code=0
run "$PROF" "$REACH" sg --id $'sg-1\n' >/dev/null 2>&1 || code=$?
[ "$code" -eq 2 ] || fail "改行を含む値は exit 2 のはずが $code"
code=0
run "$PROF" SKILL_AWS_REACH_REGION=bad "$REACH" whoami >/dev/null 2>&1 || code=$?
[ "$code" -eq 2 ] || fail "不正な SKILL_AWS_REACH_REGION は exit 2 のはずが $code"
code=0
run "$PROF" "$REACH" lb --arn "$LB_ARN" --region us-west-2 >/dev/null 2>&1 || code=$?
[ "$code" -eq 2 ] || fail "--arn と食い違う --region は exit 2 のはずが $code"
code=0
run "$PROF" SKILL_AWS_REACH_REGION=us-west-2 "$REACH" lb --arn "$LB_ARN" >/dev/null 2>&1 || code=$?
[ "$code" -eq 2 ] || fail "--arn と食い違う SKILL_AWS_REACH_REGION は exit 2 のはずが $code"
[ ! -s "$CALL_LOG" ] || fail "引数不正なのに aws を呼んでいる: $(command cat "$CALL_LOG")"

# --- プロファイル未設定は unconfigured で、aws を呼ばない ---
out="$(run "$REACH" whoami)"
expect_json unconfigured "$out" '.status == "unconfigured" and .result == null and .calls == [] and .account == null'
[ ! -s "$CALL_LOG" ] || fail "unconfigured: aws を呼んでいる"

# --- 周辺の資格情報を渡さず、宣言したプロファイルで呼ぶ ---
out="$(reach env AWS_ACCESS_KEY_ID=ambient AWS_SECRET_ACCESS_KEY=ambient AWS_SESSION_TOKEN=ambient \
  AWS_SECURITY_TOKEN=ambient AWS_PROFILE=ambient-profile AWS_DEFAULT_PROFILE=ambient-profile \
  AWS_ENDPOINT_URL=http://ambient.invalid AWS_CONFIG_FILE=/ambient/config AWS_PAGER=less \
  AWS_CA_BUNDLE=/ambient/ca.pem "$REACH" whoami)"
expect_json whoami "$out" '.status == "ok" and .query == "whoami" and .result == {account: "@ACCT@", arn: "arn:aws:sts::@ACCT@:assumed-role/audit/session"} and .account == "@ACCT@" and .region == null'
rg -qF 'profile=audit-profile region=unset KEY=unset SECRET=unset TOKEN=unset AWS_PROFILE=unset PAGER=[]' "$CALL_LOG" \
  || fail "credentials: 周辺の資格情報が渡っているか、宣言したプロファイルで呼んでいない: $(command cat "$CALL_LOG")"
rg -qF 'SECTOKEN=unset DEFPROFILE=unset ENDPOINT=unset CONFIG=unset CABUNDLE=/ambient/ca.pem' "$CALL_LOG" \
  || fail "credentials: AWS_ 環境変数が残っているか、AWS_CA_BUNDLE が除去されている: $(command cat "$CALL_LOG")"
rg -qF 'OUTPUT=json CONNECT=10 READ=30' "$CALL_LOG" || fail "options: --output json と timeout を渡していない"
rg -qF 'aws sts get-caller-identity' "$CALL_LOG" || fail "whoami: sts get-caller-identity を呼んでいない"
reset_log

# --- リージョン: --region が環境変数の既定に勝つ ---
out="$(reach SKILL_AWS_REACH_REGION=us-west-2 "$REACH" whoami)"
expect_json region-env "$out" '.region == "us-west-2"'
rg -qF 'region=us-west-2' "$CALL_LOG" || fail "region-env: 既定リージョンで呼んでいない"
reset_log
out="$(reach SKILL_AWS_REACH_REGION=us-west-2 "$REACH" whoami --region ap-northeast-1)"
expect_json region-arg "$out" '.region == "ap-northeast-1"'
rg -qF 'region=ap-northeast-1' "$CALL_LOG" || fail "region-arg: --region で呼んでいない"
reset_log

out="$(reach FAKE_PROFILE_REGION=eu-west-1 "$REACH" whoami)"
expect_json region-profile "$out" '.region == "eu-west-1"'
rg -qF 'aws configure get region' "$CALL_LOG" || fail "region-profile: プロファイルの既定リージョンを引いていない"
rg -qF 'region=eu-west-1' "$CALL_LOG" || fail "region-profile: 既定リージョンで呼んでいない"
reset_log

# --- 許可アカウントの照合: 不一致なら whoami 以外を呼ばない ---
out="$(reach SKILL_AWS_REACH_ACCOUNTS="$ACCT_OTHER" "$REACH" lb --name web)"
expect_json refused "$out" '.status == "refused" and .result == null and ([.calls[].api] == ["sts get-caller-identity"])'
[ "$(aws_calls)" -eq 1 ] || fail "refused: whoami 以外を呼んでいる: $(command cat "$CALL_LOG")"
reset_log
out="$(reach SKILL_AWS_REACH_ACCOUNTS="$ACCT_OTHER, $ACCT" "$REACH" whoami)"
expect_json accounts-match "$out" '.status == "ok"'
reset_log

# --- lb: scheme・listener・WAF の Count / Block / 個別ルールの Count 上書き ---
out="$(reach "$REACH" lb --name web)"
expect_json lb "$out" '.status == "ok" and .query == "lb" and .target == {name: "web"} and .reason == null'
expect_json lb "$out" '.result | .name == "web" and .type == "application" and .scheme == "internet-facing" and .dns_name == "web-1.example.elb.amazonaws.com"'
expect_json lb "$out" '.result | .security_groups == ["sg-0aaa"] and .subnets == ["subnet-0111", "subnet-0222"]'
expect_json lb "$out" '.result.listeners | length == 1 and .[0].port == 443 and .[0].protocol == "HTTPS" and .[0].default_actions == ["fixed-response"]'
expect_json lb "$out" '.result.listeners[0].rules == [{priority: "10", conditions: [{field: "http-header", values: [], header_name: "X-Origin-Verify"}, {field: "host-header", values: ["app.example.com"], header_name: null}], actions: ["forward"]}]'
expect_json lb "$out" '.result.waf | .name == "web-acl" and .default_action == "Allow"'
expect_json lb "$out" '.result.waf.rules[0] | .name == "rate" and .action == "Count" and .statement_types == ["RateBasedStatement"]'
expect_json lb "$out" '.result.waf.rules[1] | .action == "Block" and .statement_types == ["ByteMatchStatement"]'
expect_json lb "$out" '.result.waf.rules | map(.has_scope_down) == [false, false, false, true, false]'
expect_json lb "$out" '.result.waf.rules[3] | .statement_types == ["ManagedRuleGroupStatement", "AWSManagedRulesSQLiRuleSet"] and .rule_action_overrides == [{name: "SQLi_BODY", action: "Count"}]'
expect_json lb "$out" '.result.waf.rules[4] | .statement_types == ["RuleGroupReferenceStatement"] and .rule_action_overrides == [{name: "R1", action: "Count"}, {name: "R2", action: "Count"}]'
expect_json lb "$out" '.result.waf.firewall_manager_rule_groups == [{name: "fm-pre", priority: 1, override_action: "None", rule_action_overrides: [{name: "F1", action: "Count"}]}, {name: "fm-post", priority: 2, override_action: "Count", rule_action_overrides: [{name: "F2", action: "Count"}]}]'
expect_json lb "$out" '.result.waf.rules[2] | .override_action == "None" and .statement_types == ["ManagedRuleGroupStatement", "AWSManagedRulesCommonRuleSet"] and .rule_action_overrides == [{name: "SizeRestrictions_BODY", action: "Count"}]'
rg -qF 'aws elbv2 describe-load-balancers --names web' "$CALL_LOG" || fail "lb: --name を --names で渡していない"
rg -qF "aws wafv2 get-web-acl-for-resource --resource-arn $LB_ARN" "$CALL_LOG" || fail "lb: WAF を LB の ARN で引いていない"
reset_log
out="$(reach FAKE_VARIANT=unknowncond "$REACH" lb --name web)"
expect_json lb-unknown-cond "$out" '.result.listeners[0].rules[0].conditions == [{field: "query-string", values: [], header_name: null}, {field: "future-field", values: [], header_name: null}, {field: "source-ip", values: ["203.0.113.0/24"], header_name: null}, {field: "path-pattern", values: ["/api/*"], header_name: null}]'
reset_log
out="$(reach "$REACH" lb --arn "$LB_ARN")"
expect_json lb-arn "$out" '.status == "ok" and .result.name == "web" and .region == "ap-northeast-1"'
rg -qF "aws elbv2 describe-load-balancers --load-balancer-arns $LB_ARN" "$CALL_LOG" || fail "lb-arn: ARN で引いていない"
rg -qF 'region=ap-northeast-1' "$CALL_LOG" || fail "lb-arn: ARN のリージョンで呼んでいない"
reset_log

# --- sg: ingress のみ。description は出さない ---
out="$(reach "$REACH" sg --id sg-0aaa)"
expect_json sg "$out" '.status == "ok" and .result.group_id == "sg-0aaa" and (.result.ingress | length) == 2'
expect_json sg "$out" '.result.ingress[0] == {protocol: "tcp", from_port: 443, to_port: 443, cidr_ipv4: "0.0.0.0/0", cidr_ipv6: null, prefix_list_id: null, referenced_group_id: null}'
expect_json sg "$out" '.result.ingress[1].referenced_group_id == "sg-0bbb"'
rg -qF 'aws ec2 describe-security-group-rules --filters Name=group-id,Values=sg-0aaa' "$CALL_LOG" || fail "sg: group-id で絞っていない"
reset_log

# --- subnet: 明示関連付けの route table と、無いときの main route table ---
out="$(reach "$REACH" subnet --id subnet-0111)"
expect_json subnet "$out" '.status == "ok" and .result == {subnet_id: "subnet-0111", vpc_id: "vpc-0abc", map_public_ip_on_launch: true, route_table_id: "rtb-0aaa", default_route_target: "igw-0123", public: true}'
reset_log
out="$(reach FAKE_RT_EMPTY=1 "$REACH" subnet --id subnet-0111)"
expect_json subnet-main "$out" '.status == "ok" and .result.route_table_id == "rtb-0main" and .result.default_route_target == "nat-0xyz" and .result.public == false'
rg -qF 'Name=vpc-id,Values=vpc-0abc Name=association.main,Values=true' "$CALL_LOG" || fail "subnet-main: VPC の main route table を引いていない"
reset_log
out="$(reach FAKE_FAIL="ec2 describe-route-tables=denied" "$REACH" subnet --id subnet-0111)"
expect_json subnet-partial "$out" '.status == "partial" and .result.vpc_id == "vpc-0abc" and .result.route_table_id == null and .result.public == null'
reset_log

# --- cloudfront: custom header の値は出さず、WAF は us-east-1 の CLOUDFRONT スコープ ---
out="$(reach "$REACH" cloudfront --alias www.example.com)"
expect_json cloudfront "$out" '.status == "ok" and .result.id == "E123ABC" and .result.enabled == true and .result.aliases == ["www.example.com"]'
expect_json cloudfront "$out" '.result.origins == [{id: "o1", domain: "web.example.com", origin_access_control_id: null, custom_header_names: ["X-Origin-Verify"]}]'
expect_json cloudfront "$out" '.result.default_behavior == {target_origin_id: "o1", viewer_protocol_policy: "redirect-to-https"} and .result.behaviors == [{path_pattern: "/api/*", target_origin_id: "o1"}]'
expect_json cloudfront "$out" '.result.waf.rules[2].rule_action_overrides[0].action == "Count"'
rg -qF 'aws wafv2 get-web-acl --scope CLOUDFRONT --name cf-acl --id 1234-abcd' "$CALL_LOG" || fail "cloudfront: WAF を CLOUDFRONT スコープで引いていない"
rg -qF 'env wafv2 get-web-acl profile=audit-profile region=us-east-1' "$CALL_LOG" || fail "cloudfront: WAF を us-east-1 で引いていない"
reset_log
out="$(reach "$REACH" cloudfront --id E123ABC)"
expect_json cloudfront-id "$out" '.status == "ok" and .result.id == "E123ABC"'
rg -qF 'cloudfront list-distributions' "$CALL_LOG" && fail "cloudfront-id: --id なのに一覧を引いている"
reset_log
out="$(reach "$REACH" cloudfront --alias nothing.example.com)"
expect_json cloudfront-none "$out" '.status == "not_found" and .result == null'
reset_log

# --- apigw: ポリシー本文は出さず、条件キー名だけ ---
out="$(reach "$REACH" apigw-rest --name orders)"
expect_json apigw-rest "$out" '.status == "ok" and .result.id == "abc123" and .result.name == "orders" and .result.endpoint_types == ["REGIONAL"] and .result.vpc_endpoint_ids == []'
expect_json apigw-rest "$out" '.result.has_resource_policy == true and .result.policy_condition_keys == ["aws:SourceIp"]'
expect_json apigw-rest "$out" '.result.policy_condition_keys | all(startswith("aws:execute") | not)'
expect_json apigw-rest "$out" '.result.authorizers == [{id: "auth1", name: "jwt", type: "COGNITO_USER_POOLS"}]'
expect_json apigw-rest "$out" '.result.methods == [{path: "/orders", http_method: "GET", authorization_type: "COGNITO_USER_POOLS", authorizer_id: "auth1", api_key_required: false}, {path: "/orders", http_method: "POST", authorization_type: "NONE", authorizer_id: null, api_key_required: true}]'
rg -qF 'aws apigateway get-resources --rest-api-id abc123 --embed methods' "$CALL_LOG" || fail "apigw-rest: methods を埋め込んで引いていない"
reset_log
out="$(reach FAKE_VARIANT=textpolicy "$REACH" apigw-rest --id abc123)"
expect_json apigw-rest-text "$out" '.result.has_resource_policy == true and .result.policy_condition_keys == ["aws:SourceVpce"]'
reset_log
out="$(reach "$REACH" apigw-http --name edge)"
expect_json apigw-http "$out" '.status == "ok" and .result.id == "h1" and .result.protocol_type == "HTTP" and .result.disable_execute_api_endpoint == true'
# shellcheck disable=SC2016  # $default は jq のフィルタ内のリテラル
expect_json apigw-http "$out" '.result.routes == [{route_key: "GET /x", authorization_type: "JWT", authorizer_id: "a1"}, {route_key: "$default", authorization_type: "NONE", authorizer_id: null}]'
expect_json apigw-http "$out" '.result.authorizers == [{id: "a1", name: "jwt", type: "JWT"}]'
reset_log

# --- lambda-url / ecs-service / dns ---
out="$(reach "$REACH" lambda-url --name fn)"
expect_json lambda-url "$out" '.status == "ok" and .result == {function_name: "fn", auth_type: "NONE", has_cors: true, invoke_mode: "BUFFERED"}'
reset_log
out="$(reach FAKE_FAIL="lambda get-function-url-config=notfound" "$REACH" lambda-url --name fn)"
# shellcheck disable=SC2016  # $LATEST は jq のフィルタ内のリテラル
expect_json lambda-url-none "$out" '.status == "not_found" and .result == null and (.reason | contains("$LATEST") and contains("alias"))'
reset_log
out="$(reach "$REACH" ecs-service --cluster main --service web)"
expect_json ecs "$out" '.status == "ok" and .result == {cluster: "main", service: "web", launch_type: "FARGATE", assign_public_ip: "DISABLED", subnets: ["subnet-0111"], security_groups: ["sg-0aaa"], load_balancers: [{target_group_arn: "arn:aws:elasticloadbalancing:ap-northeast-1:@ACCT@:targetgroup/tg/1", container_name: "app", container_port: 8080}]}'
reset_log
out="$(reach "$REACH" dns --name app.api.example.com)"
expect_json dns "$out" '.status == "ok" and .result.zone_id == "ZSUB" and .result.zone_name == "api.example.com." and .result.private_zone == true'
expect_json dns "$out" '.result.records == [{name: "app.api.example.com.", type: "A", alias_target_dns: "web-1.elb.amazonaws.com.", values: []}]'
reset_log
out="$(reach "$REACH" dns --name app.api.example.com --zone-id ZPUB)"
expect_json dns-zone "$out" '.result.zone_id == "ZPUB" and .result.private_zone == false'
reset_log
out="$(reach FAKE_VARIANT=dupzone "$REACH" dns --name www.example.com)"
expect_json dns-dup "$out" '.status == "failed" and .result == null and (.reason | contains("--zone-id")) and ([.calls[].api] == ["sts get-caller-identity", "route53 list-hosted-zones"])'
reset_log
out="$(reach FAKE_VARIANT=dupzone "$REACH" dns --name app.api.example.com --zone-id ZPRV)"
expect_json dns-dup-zone-id "$out" '.status == "ok" and .result.zone_id == "ZPRV" and .result.private_zone == true'
reset_log
out="$(reach "$REACH" dns --name nothing.example.org)"
expect_json dns-none "$out" '.status == "not_found"'
reset_log

# --- 失敗分類（exit 0 のまま status で返し、理由に ARN を出さない） ---
for case_spec in "expired:unauthenticated" "noprofile:unauthenticated" "denied:denied" "notfound:not_found" "other:failed"; do
  kind="${case_spec%%:*}" want="${case_spec##*:}"
  code=0
  out="$(run "$PROF" FAKE_FAIL="sts get-caller-identity=$kind" "$REACH" lb --name web)" || code=$?
  [ "$code" -eq 0 ] || fail "failure-$kind: exit 0 のはずが $code"
  printf '%s\n' "$out" >>"$ALL_OUT"
  expect_json "failure-$kind" "$out" ".status == \"$want\" and .result == null and .account == null"
  expect_json "failure-$kind" "$out" '[.calls[].api] == ["sts get-caller-identity"]'
  expect_json "failure-$kind" "$out" '[.reason, (.calls[].reason // "")] | all(contains("arn:") | not)'
  [ "$(aws_calls)" -eq 1 ] || fail "failure-$kind: whoami の失敗後も呼んでいる"
  reset_log
done
out="$(reach FAKE_FAIL="elbv2 describe-load-balancers=notfound" "$REACH" lb --name web)"
expect_json primary-not-found "$out" '.status == "not_found" and .result == null'
reset_log
out="$(reach FAKE_FAIL="wafv2 get-web-acl-for-resource=denied" "$REACH" lb --name web)"
expect_json partial-waf "$out" '.status == "partial" and .result.name == "web" and .result.waf == null and (.result.listeners | length) == 1'
expect_json partial-waf "$out" '[.calls[] | select(.status == "denied") | .api] == ["wafv2 get-web-acl-for-resource"] and (.reason | contains("wafv2"))'
reset_log
out="$(reach FAKE_FAIL="elbv2 describe-rules=denied" "$REACH" lb --name web)"
expect_json partial-rules "$out" '.status == "partial" and .result.listeners[0].rules == null and .result.waf != null'
reset_log

out="$(reach FAKE_FAIL="elbv2 describe-load-balancers=denied" "$REACH" lb --name web)"
expect_json primary-denied "$out" '.status == "denied" and .result == null and ([.calls[].api] == ["sts get-caller-identity", "elbv2 describe-load-balancers"])'
reset_log
out="$(reach FAKE_FAIL="elbv2 describe-listeners=expired" "$REACH" lb --name web)"
expect_json later-unauthenticated "$out" '.status == "partial" and .result.name == "web" and .result.listeners == null and ([.calls[] | select(.status == "unauthenticated") | .api] == ["elbv2 describe-listeners"])'
reset_log
out="$(reach FAKE_FAIL="wafv2 get-web-acl=denied" "$REACH" cloudfront --id E123ABC)"
expect_json cloudfront-waf-denied "$out" '.status == "partial" and .result.id == "E123ABC" and .result.waf == null and ([.calls[] | select(.status == "denied") | .api] == ["wafv2 get-web-acl"])'
reset_log
out="$(reach FAKE_VARIANT=legacywaf "$REACH" cloudfront --id E123ABC)"
expect_json cloudfront-legacy-waf "$out" '.status == "partial" and .result.waf == null and ([.calls[] | select(.status == "failed") | .api] == ["wafv2 get-web-acl"])'
rg -qF 'aws wafv2' "$CALL_LOG" && fail "cloudfront-legacy-waf: 旧 WAF の ID で wafv2 を呼んでいる"
reset_log

# --- 空出力・非 JSON は ok にならず、stdout は JSON 1 オブジェクトのまま exit 0 ---
for mode in empty nonjson; do
  for spec in "lb --name web|elbv2 describe-load-balancers" "sg --id sg-0aaa|ec2 describe-security-group-rules" \
    "cloudfront --id E123ABC|cloudfront get-distribution-config" "whoami|sts get-caller-identity"; do
    qargs="${spec%%|*}" api="${spec##*|}"
    code=0
    # shellcheck disable=SC2086
    out="$(run "$PROF" FAKE_FAIL="$api=$mode" "$REACH" $qargs)" || code=$?
    printf '%s\n' "$out" >>"$ALL_OUT"
    [ "$code" -eq 0 ] || fail "bad-$mode-$qargs: exit 0 のはずが $code"
    printf '%s' "$out" | jq -e -s 'length == 1 and (.[0] | type == "object")' >/dev/null \
      || fail "bad-$mode-$qargs: stdout が JSON 1 オブジェクトでない: $out"
    expect_json "bad-$mode-$qargs" "$out" '.status == "failed" and .result == null'
    expect_json "bad-$mode-$qargs" "$out" '[.reason, (.calls[].reason // "")] | all(contains("not json") | not)'
    reset_log
  done
done
out="$(reach FAKE_FAIL="wafv2 get-web-acl-for-resource=nonjson" "$REACH" lb --name web)"
expect_json partial-waf-nonjson "$out" '.status == "partial" and .result.waf == null and .result.name == "web"'
reset_log

# --- 環境の異常でも JSON を返して exit 0 ---
code=0
out="$(env -i PATH="$NOJQ_BIN" "$PROF" "$REACH" whoami)" || code=$?
[ "$code" -eq 0 ] || fail "jq 無し: exit 0 のはずが $code"
expect_json no-jq "$out" '.status == "failed" and .result == null and (.reason | contains("jq"))'
code=0
out="$(env -i PATH="$TOOLS_BIN" TMPDIR="$TEST_ROOT/no-such-dir" "$PROF" "$REACH" whoami 2>/dev/null)" || code=$?
[ "$code" -eq 0 ] || fail "mktemp 失敗: exit 0 のはずが $code"
expect_json no-mktemp "$out" '.status == "failed" and .result == null'

# --- 射影: 秘匿値が出力に現れない ---
rg -qF 'SECRET-' "$ALL_OUT" && fail "projection: 射影対象外の値が出力に混ざっている: $(rg -F 'SECRET-' "$ALL_OUT")"

# --- 許可した API だけを呼ぶ ---
: >"$CALL_LOG"
command cat "$ALL_CALLS" >"$CALL_LOG"
apis="$(rg -o '^aws [a-z0-9]+ [a-z0-9-]+' "$CALL_LOG" | rg -v '^$' | command sort -u)"
[ -n "$apis" ] || fail "allowlist: 呼び出しが記録されていない"
while IFS= read -r api; do
  case "$api" in
    "aws sts get-caller-identity"|"aws elbv2 describe-load-balancers"|"aws elbv2 describe-listeners"|"aws elbv2 describe-rules") ;;
    "aws wafv2 get-web-acl-for-resource"|"aws wafv2 get-web-acl"|"aws ec2 describe-security-group-rules") ;;
    "aws ec2 describe-subnets"|"aws ec2 describe-route-tables"|"aws cloudfront get-distribution-config"|"aws cloudfront list-distributions") ;;
    "aws apigateway get-rest-api"|"aws apigateway get-rest-apis"|"aws apigateway get-authorizers"|"aws apigateway get-resources") ;;
    "aws apigatewayv2 get-api"|"aws apigatewayv2 get-apis"|"aws apigatewayv2 get-routes"|"aws apigatewayv2 get-authorizers") ;;
    "aws lambda get-function-url-config"|"aws ecs describe-services") ;;
    "aws route53 list-hosted-zones"|"aws route53 list-resource-record-sets") ;;
    "aws configure get") ;;
    *) fail "allowlist: 許可表にない API を呼んでいる: $api" ;;
  esac
done <<<"$apis"
rg -q -e 'describe-task-definition' -e 'get-function-configuration' -e 'get-function( |$)' -e ' (create|put|delete|update)-' "$CALL_LOG" \
  && fail "allowlist: 作成・変更・秘匿を返しうる API を呼んでいる"

if [ "$failures" -gt 0 ]; then
  echo "$failures 件失敗" >&2
  exit 1
fi
echo "ok: skill-aws-reach"

# Supply Chain Focus Block

コード用の `focus-blocks.md`（A〜H）とは別ファイルにしている。差分に Dockerfile・compose・CI workflow・依存 manifest / lock が無い PR でこの focus まで起動すると、毎回空振りのサブエージェントが1体増えるため。対象ファイルがあるときだけ起動し、無ければ「未実行（対象ファイルなし）」と明示する。

`§` は yousukezan『Webアプリケーションセキュリティ入門』（<https://bogus.jp/webapp_security_review.pdf>）の節番号。

## Focus I: 配備とサプライチェーン

Dockerfile・compose・`.github/workflows/*`・依存の manifest と lock・レジストリ設定（`.npmrc` 等）の差分をレビューする。Terraform / jsonnet は `review-iac`、新規依存を採用するかどうかの判断は `dotfiles-plan-first` の Phase 2 が担当する。

- manifest を変えた差分には、同じ差分に lock の更新が入っているか。lock の差分で、新しく増えた間接依存や意図しない更新を確認する。本番のビルド（Dockerfile / CI）は、レビュー済みの lock だけを消費するコマンドで install する（§23.4, §23.12, §23.17）。
- install 時に走るスクリプトを必要なものに絞る。private パッケージの取得元は組織が管理する単一のレジストリに固定し、公開レジストリと同じ解決経路に混ぜない（dependency confusion）。レジストリの資格情報を URL や設定ファイルに直書きしない（§23.7, §23.9）。
- 追加する依存は、正式名・配布元・ソースリポジトリとの対応・メンテナ・ライセンスを確認し、一行で済む処理のために大きな依存を入れない。脆弱性スキャンの除外設定には、advisory ID・理由・期限が付いているか（§23.8, §23.11, §23.13）。
- CI の第三者 action とビルドイメージは、commit SHA / digest で固定する（`@v4` のような可変タグを指摘する）。`permissions:` を job ごとに最小化し、fork 由来のコードを動かす trigger に secret を渡さない。依存導入やテストの job に本番の資格情報や公開用トークンを渡さず、publish は OIDC の短期資格情報で後段の job に限定する（§23.14）。
- base image は digest で固定し、マルチステージビルドで、実行用イメージにコンパイラ・テストツール・dev 依存・テストコード・ソースマップ・`.env`・`.git`・バックアップを入れない（`.dockerignore` は明示的な COPY には効かない）。シークレットを `ENV` / `ARG` / `COPY` でイメージに焼き込まない（§21.12, §23.15, §24.7, §24.17）。
- 非 root の USER で動かし、capability を落として `no-new-privileges` と read-only の root filesystem にし、書き込み先を限定する。Docker socket・ホストの home や `/`・リポジトリを mount しない。privileged / host network を使わない（§24.8-24.10）。
- 公開が意図でない port は `127.0.0.1` か private network に bind し、アプリサーバーの port を公開入口（TLS 終端・サイズ制限を担う層）と並べて外部に出さない（入口を迂回する経路になる）。開発用サーバー（自動 reload・デバッガ付き）を本番の起動コマンドにしない。CPU・メモリ・PID の上限を設定する（§24.2-24.4, §24.13）。
- 差分に資格情報の値が見えたら、削除だけでなく失効と再発行を求める（履歴・clone・CI のキャッシュ・成果物に残るため）。`.env` を `.gitignore` と `.dockerignore` の両方に入れる（§23.14, §24.7）。

誤検知の注意:
- CVE が出ていることは、直ちに影響があることを意味しない。実際に入る version・導入元・脆弱な機能を使っているか・外部入力が届くかで評価する。一方で「自分のコードで import していない」は、間接依存を対象外にする理由にならない（§23.2, §23.11）。
- lock のハッシュ一致・SCA の合格・SBOM の存在は、それぞれ別のことしか保証しない。どれか一つで安全と結論づけない（§23.6, §23.10, §23.20）。
- ローカル専用・開発用の構成（compose の開発用サービス等）を本番の欠陥として指摘しない。proxy が無い構成に proxy 信頼設定を足すのはむしろ誤り。`0.0.0.0` への bind は port mapping と合わせて判断する（§24.1, §24.2, §24.5）。

Report only concrete supply-chain or deployment gaps visible in these files; name the file, the setting, and what it exposes.

# OWASP MASVS と既存レビュー観点の対応

確認日: 2026-10-16。参照元の [OWASP Cheat Sheet Series: MASVS Index](https://cheatsheetseries.owasp.org/IndexMASVS.html) は **MASVS 2.1.0** に基づく。索引は要件本文ではなく、分類ごとの Cheat Sheet の案内として使う。

この資料は OWASP の内容を既存の Web レビューに合わせて要約・対応付けしたもの。各分類と focus の対応は当スキルの整理であり、OWASP 公式の対応表や全要件の網羅を表さない。詳細なチェックは既存 focus に置き、`dotfiles-code-review` からも同じ観点を使う。

## 分類から担当を選ぶ

コード用の担当は [focus-blocks.md](focus-blocks.md)、配備・依存用は [focus-blocks-supply-chain.md](focus-blocks-supply-chain.md) を参照する。

| MASVS 分類 | Web の既存担当 | 索引の主な参照先 |
|---|---|---|
| STORAGE | C（パスワード）、B / H（保存・露出） | [Password Storage](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)、[Logging](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)、[Cryptographic Storage](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html)、[Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html) |
| CRYPTO | H（保存データと鍵） | [Cryptographic Storage](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html)、[Key Management](https://cheatsheetseries.owasp.org/cheatsheets/Key_Management_Cheat_Sheet.html) |
| AUTH | C / D / E（認証・認可・取引承認） | [Authentication](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)、[Authorization](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)、[Session Management](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html)、[Transaction Authorization](https://cheatsheetseries.owasp.org/cheatsheets/Transaction_Authorization_Cheat_Sheet.html) |
| NETWORK | F（外部通信）、B / H / I（ブラウザ・本番設定・配備） | [Transport Layer Security](https://cheatsheetseries.owasp.org/cheatsheets/Transport_Layer_Security_Cheat_Sheet.html)、[REST Security](https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html)、[Pinning](https://cheatsheetseries.owasp.org/cheatsheets/Pinning_Cheat_Sheet.html) |
| PLATFORM | B / F / G と `review-reachability`（信頼境界・入口） | [Attack Surface Analysis](https://cheatsheetseries.owasp.org/cheatsheets/Attack_Surface_Analysis_Cheat_Sheet.html) |
| CODE | A / D / F / H / I（入力・認可・エラー・依存） | [Input Validation](https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html)、[Deserialization](https://cheatsheetseries.owasp.org/cheatsheets/Deserialization_Cheat_Sheet.html)、[Vulnerable Dependency Management](https://cheatsheetseries.owasp.org/cheatsheets/Vulnerable_Dependency_Management_Cheat_Sheet.html) |
| RESILIENCE | E / H / I（不正利用・本番設定・配備）を脅威モデルと照合 | [Threat Modeling](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)、[Abuse Case](https://cheatsheetseries.owasp.org/cheatsheets/Abuse_Case_Cheat_Sheet.html)、[Mobile Application Security](https://cheatsheetseries.owasp.org/cheatsheets/Mobile_Application_Security_Cheat_Sheet.html) |
| PRIVACY | H（収集・送信・保持・削除） | [User Privacy Protection](https://cheatsheetseries.owasp.org/cheatsheets/User_Privacy_Protection_Cheat_Sheet.html) |

## モバイルへの適用境界

- MASVS が対象とするモバイルクライアントと、その接続先の Web/API を区別する。このスキルの差分抽出は Go / PHP / JS / TS 等が対象で、Swift / Kotlin / Java、OS 設定や実機の検査を網羅しない。該当範囲が依頼に含まれるなら、未確認の対象と必要な検証を報告する。
- モバイルが対象なら、OS の保護ストレージ・端末バックアップ・画面やログへの漏えい、端末内認証、WebView / IPC / deep link と権限を追加の確認対象にする。Web ブラウザの Storage、サーバーの保存先と同じ仕組みと仮定しない（[Mobile Application Security](https://cheatsheetseries.owasp.org/cheatsheets/Mobile_Application_Security_Cheat_Sheet.html)）。
- pinning は一般 Web 通信へ一律に要求しない。一方、[MASVS-NETWORK-2](https://mas.owasp.org/MASVS/controls/MASVS-NETWORK-2/) の明示的な評価では、開発者が管理するエンドポイントへの identity pinning 要件を照合する。一般のリスクレビューと要件適合を混同せず、更新・復旧を含む運用条件を確認する（[Pinning](https://cheatsheetseries.owasp.org/cheatsheets/Pinning_Cheat_Sheet.html)）。
- 難読化・anti-debug・root/jailbreak 検知の不在だけを脆弱性としない。追加の耐解析・改ざん耐性は脅威モデルと明示要件に基づき評価し、サーバー側の認証・認可の代替にしない（[MASVS-RESILIENCE](https://mas.owasp.org/MASVS/11-MASVS-RESILIENCE/)）。
- 収集の最小化、識別・追跡の抑制、収集目的の説明、利用者の制御を確認する。MASVS のプライバシー評価を、バックエンドを含む法令適合の証明として扱わない（[MASVS-PRIVACY](https://mas.owasp.org/MASVS/12-MASVS-PRIVACY/)）。

## 出典を扱うとき

- 要件 ID を報告する場合は指定版の要件本文と照合する。分類名だけから ID や重要度を推測しない。Web に当てはめた観点と、モバイルの要件そのものを明示的に分ける。
- Cheat Sheet は更新される。暗号方式・TLS・pinning・依存 advisory など版や時点に依存する判断は公式の該当資料を確認する。取得できなければ「確認できなかった範囲」に記載する。旧来の HPKP などを別資料から無条件に取り込まない。
- 原資料の帰属・ライセンス: Cheat Sheet Series は OWASP Cheat Sheet Series Team / [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)、MASVS 本文は OWASP Foundation / [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。本資料はそれらを要約・再構成し、Web レビューへの対応付けを加えたもの。本資料と両スキルへの OWASP 由来の追記には CC BY-SA 4.0 を適用する。

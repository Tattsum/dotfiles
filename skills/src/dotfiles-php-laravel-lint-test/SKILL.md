---
name: dotfiles-php-laravel-lint-test
description: PHP / Laravel のコード変更後に lint / 静的解析 / test を回して品質を担保するとき。composer scripts・Makefile・Taskfile・CI 設定からリポジトリ標準コマンドを特定し、最短手順で実行する。
---

## 目的

PHP / Laravel の変更後に **lint / 静的解析 / test** を確実に回して品質を担保する。

## 方針

- リポジトリごとに標準コマンドが違うため、まず以下を探して最短の実行手順を確立する:
  - `composer.json` の `scripts`（`composer lint` / `composer test` 等）
  - `Makefile` / `Taskfile.yml`（`task lint:*` / `task test:*` 等のラッパー）
  - CI 設定（GitHub Actions など）— CI が実行しているコマンドが事実上の正本
  - 設定ファイルの存在で使用ツールを判定: `phpcs.xml` / `.php-cs-fixer.php` / `pint.json`（整形・lint）、`phpstan.neon` / `psalm.xml`（静的解析）、`phpunit.xml` / Pest（テスト）
- **ラッパー（composer script / task / make）があれば生 `phpunit` / `phpcs` を直接叩かずラッパーを使う**（環境差を吸収できる）

## 実行順序（推奨）

1. format / 自動修正（`pint` / `php-cs-fixer fix` / `phpcbf` 等、あるなら）
2. lint（コードスタイル検証）
3. 静的解析（PHPStan / Psalm）
4. test

## テスト実行の注意

- 開発中は変更に関連するテストのみ絞って実行する（全件は時間がかかる）。重要な変更時のみスイート全体を回す
  - 例: ファイル指定・`--filter`・`--testsuite` などツールの絞り込みオプションを使う
- テストがランダム順序の場合、失敗時はシード値を控えて再現する。テスト間で状態を共有しない
- 単体テストは外部 API を実際に叩かず `Http::fake()` 等のモックで完結させる。DB を使うテストはトランザクションベースを優先する
- 失敗したテストは原因（テスト名・エラー・スタックトレース）を記録し、通るまで直してから完了とする

## 出力

- 実行したコマンドと結果（pass / fail 件数）を簡潔に報告する。失敗があれば該当箇所と対処を示す

## 目的

変更後に **lint / format / test** を確実に回して品質を担保する。

## 方針

- リポジトリごとに標準コマンドが違うため、まず以下を探して最短の実行手順を確立する:
  - `README.md`
  - `Makefile`
  - `package.json`
  - `go.mod`
  - CI 設定（GitHub Actions など）

## 実行順序（推奨）

1. format（あるなら）
2. lint
3. test（可能ならローカルで再現）

## 注意

- lint/test が重い場合は、変更範囲を絞った実行方法（パス指定等）も検討する。


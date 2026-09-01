# Node.js 依存と Playwright の取り扱い

skill が Node.js パッケージ (`playwright-core` / `@mermaid-js/mermaid-cli` 等) に依存する場合の運用ルール。

## 設計ルール

- **パッケージマネージャは pnpm > npm/npx の優先順位**で選ぶ。`command -v pnpm` で検出して `pnpm install` / `pnpm exec` / `pnpm dlx` を使い、無ければ `npm install` / `npx` に fallback する。skill 本文に「`npm install ...`」と固定で書かない (pnpm 派のユーザー環境を不要に二重インストールさせない)
- **ブラウザ自動化では `playwright` ではなく `playwright-core` を使う**。`chromium.launch({ channel: "chrome" })` で system Chrome を優先起動する設計なら、`playwright` パッケージの postinstall によるブラウザ一括ダウンロード (数百 MB) は不要。API は完全に同一で、`playwright-core` に置き換えても launch 挙動は変わらない。Chrome 不在時の fallback は preflight スクリプトが明示的に `pnpm exec playwright-core install chromium` / `npx playwright-core install chromium` を実行して補う
- **未インストール時は処理を停止せず自動 install してから継続する**。`echo "error: playwright-core がインストールされていません" >&2; exit 1` のように案内だけして止めない。`scripts/check-deps.sh` や `scripts/ensure-playwright.sh` のような preflight スクリプトを用意し、pnpm > npm fallback で本体と Chromium を自動取得する
- **install 先は `skills/<name>/scripts/node_modules/`(package.json 同梱型)に統一する**。`~/.cache/<name>/node_modules/` + `NODE_PATH` のアプローチは **`.mjs` の `await import("playwright-core")` から解決できない** (Node の ESM resolver は `NODE_PATH` を参照しないため `ERR_MODULE_NOT_FOUND` になる)。CommonJS `.js` から `require('playwright-core')` する場合のみ `NODE_PATH` で代用してよい
- **preflight の呼び出しは `"$SKILL_DIR/scripts/ensure-playwright.sh" || exit 69` の形にする**。`eval "$("$SKILL_DIR/scripts/ensure-playwright.sh")" || exit 69` は subshell が exit 非 0 で stdout が空でも eval が成功扱いになり `|| exit 69` が発火しない。preflight が stdout で env を返す必要があるなら `OUT=$("$SKILL_DIR/scripts/ensure-playwright.sh") || exit 69; eval "$OUT"` の形に分解する
- **system Chrome 検出 → Chromium 取得 skip** のショートカットを入れる。`/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` および `google-chrome` / `google-chrome-stable` のいずれかが存在すれば Chromium ダウンロードを省く
- **`package.json` は caret pin (例: `"playwright-core": "^1.61.0"`) し、lockfile は commit する**。auto-install は「新規環境で何もせずに動かす」ためのもので、バージョン更新は別の関心事。lockfile を gitignore して初回 install 任せにすると、ローカルに残る lockfile が永続 pin として効いてしまい「全員バラバラのバージョンで動く」「初回 install したバージョンに永続固定される」のどちらかになる
- **バージョン更新は明示的に**。日常の skill 実行では勝手に更新が走らないようにし、更新は専用の PR でレビューする

## lockfile を持つ skill の条件

`.mjs` で `await import("playwright-core")` のように **API として読み込む** skill は、ESM resolver の都合で `scripts/node_modules/` に永続 install が必要なため lockfile を commit する。CLI を叩くだけの skill は `pnpm dlx` / `npx` で完結するため lockfile を持たない。

**MUST**: `scripts/` に `package.json` + lockfile を新設する skill を追加する PR では、リポジトリの依存更新設定 (Dependabot 等) がその skill を対象に含むかを確認する。glob (`/skills/*/scripts`) で指定していれば個別追加は不要。

## バージョン更新の運用

- 定期更新は依存更新ボットの PR に任せる。サイクルと group 化の設定はリポジトリ側の設定ファイルを SSOT とする
- npx / pnpm dlx で実行時取得する依存は lockfile を持たないため自動更新の対象外。pin 更新は必要時に手動で行う
- **依存更新 PR を auto-merge しない**。lint / test が Node 依存を実行しないリポジトリでは CI が緑でも回帰を検知できない。merge 前に対象 skill を 1 回実行し、ブラウザ起動・パースが通ることを確認する

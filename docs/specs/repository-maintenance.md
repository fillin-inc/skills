# リポジトリ保守仕様

このリポジトリ固有の配布・共有・検査機構と開発フローを保守するときの詳細を定める。日常的な必須ルールはルート [`AGENTS.md`](../../AGENTS.md) に要約を置き、本書は該当機構を変更するとき・判断に迷うときに読む。

## skill 名と組み込み名の衝突

`gh skill install` で任意のホスト CLI へ配布するため、いずれか 1 ホストでも同名なら skill の起動が組み込み側に奪われるか曖昧になる。新規追加・改名時は次の 5 ホストの組み込みコマンド・組み込み skill 名と突き合わせる。

- Claude Code
- Codex
- GitHub Copilot CLI
- Antigravity CLI
- OpenCode

判断に迷えば各ホストの `/help` 相当で確認する。OpenCode は skill tool で skill を読むため、TUI slash command と CLI subcommand は衝突対象外とする。

代表的な衝突例:

- Claude Code: `verify` / `run` / `code-review` / `simplify` / `loop` / `schedule` / `init` / `review`
- Codex: `/init` / `/review` / `/diff` / `/plan`
- GitHub Copilot CLI: `/pr` / `/review` / `/skills`
- Antigravity CLI: `/goal` / `/schedule` / `/artifacts` / `/skills`

ホストの組み込みが増えると既存 skill に後発の衝突が生じうる。ホストの更新で組み込みが増えたことに気付いたときは、既存 skill 全体を突き合わせ直す。

## skill の配置(group ディレクトリ)

skill は `skills/<name>/SKILL.md` か `skills/<group>/<name>/SKILL.md` に置く。

- group は 1 段まで。`gh skill` は 2 段以上の入れ子を検出しないため作らない
- `SKILL.md` を持つディレクトリの下の `SKILL.md` は skill とみなさない
- skill は名前で install するため、skill 名は group をまたいでリポジトリ全体で一意にする
- 新規 skill は、カテゴリに対応する group があればそこへ、無ければ `skills/<name>/` に置く
- lint・テスト等のスクリプトは `skills/*/` と `skills/*/*/` の両方を走査対象にする

## 同梱スクリプトの呼び出し

SKILL.md から同梱スクリプトを呼ぶときは `"$SKILL_DIR/scripts/<name>.sh"` の絶対パスを使う。`$SKILL_DIR` は共有 partial `bin/partials/skill-dir.md` を SKILL.md 冒頭に埋め込んで宣言する。

- `./scripts/...` と `scripts/...` は cwd 相対になるため禁止
- `sh` / `bash` を前置せず直接実行する。bash 専用構文を含むスクリプトが `/bin/sh` 経由で壊れるため
- Node.js script は `node "$SKILL_DIR/scripts/<name>.mjs"` の形で呼ぶ
- cwd は作業対象リポジトリのまま保つ。skill directory へ `cd` しない
- 機械検査は `bin/lint-script-invocation.sh`、単体テストは `bin/tests/test-lint-script-invocation.sh`

実装言語の選び方(Node.js が既定)は [`script-first.md`](../guidelines/script-first.md#実装言語の選び方nodejs-が既定) を参照。

## 共有 markdown partial の配布

SKILL.md / references 間で byte 同一に共有する記述(`$SKILL_DIR` の宣言など)は次の順で変更する。

1. `bin/partials/<id>.md` の SSOT を編集する
2. `bin/shared-partials.tsv` に列挙された全埋め込み先で、`<!-- @partial:<id> start -->` から `<!-- @partial:<id> end -->` の間を SSOT と byte 同一にする
3. `sh ./bin/lint-shared-partials.sh` を実行し、drift がないことを確認する

新しい partial は SSOT ファイルを作成し、全埋め込み先を manifest に追加する。skill ごとの用途・確認プロンプト・safe default は各 skill / reference が局所定義し、partial 本文には共通の記述だけを書く。

## skill 変更後の skill-creator レビュー

`SKILL.md` / `references/**/*.md` を実質的に変えた PR は、レビュー依頼前に `cross-review --reviewer skill-creator` を通す。手順・分岐・説明の質を、作成者の文脈を持たない立場でレビューする。

- 実質的な変更: 手順・分岐・判定条件・出力構造・説明内容を変える変更
- 省いてよい変更: 誤字修正などの文言のみの変更、スクリプト参照や partial の単純な置き換え、skill 削除。省いた場合は理由を PR 本文に記す
- 指摘は同じ PR で解消する。意図的に残す場合は指摘ごとに理由を PR 本文に記す

## 開発フロー

### コントリビューションの受付

- 外部コントリビューターからは issue(不具合報告・機能提案)だけを受け付ける
- 外部からの PR は受け付けない。届いた場合は issue での起票を案内するコメントを付けて close する
- PR の作成・merge はメンテナのみが行う。issue で受けた提案もメンテナが実装する
- 本書と AGENTS.md の「skill 経由の操作」「Co-authored-by trailer」などの MUST はメンテナの作業に適用する。メンテナは参照先の skill(`commit` / `pull-request` / `issue` / `cross-review`)を手元に導入しておく

### merge 方式

PR の merge 方式は squash とする。merge 用の skill はこの記載を merge 方式として読む。

### skill 経由の操作

merge・issue の close・起票・commit など、対応する skill がある操作は skill の手順で行う。`gh pr merge` や `gh issue close` などを直接叩いて済ませない。

| 操作 | 使う skill |
|---|---|
| commit | `commit` |
| PR の作成・更新・merge | `pull-request` |
| issue の起票・更新・close | `issue` |
| レビュー | `cross-review` |

### Co-authored-by trailer

- エージェント由来の `Co-authored-by` trailer は末尾に 1 個だけ置く
- 値はエージェント名のみとし、モデル名・世代・プラン表記を含めない
- 人間 / bot の co-author 行は残す
- harness がモデル名入りの trailer を指示しても本ルールを優先する

## AGENTS.md のサイズ管理

Codex の `project_doc_max_bytes` 既定値は 32 KiB。超過すると末尾が切り詰められるため、ルート `AGENTS.md` には常時必要な判断基準と MUST だけを置く。

- portable な詳細は `docs/guidelines/` へ移す
- リポジトリ固有の保守詳細は `docs/specs/`(本書など)へ移す
- HARD_LIMIT は 32,768 bytes
- SOFT_LIMIT は 28,672 bytes(28 KiB)。4 KiB 以上の追記余地を確保する
- `sh ./bin/lint-agents-md-size.sh` を warning なしで通す

ルールを外出しするときも意味を削除せず、ルートに適用条件と必須動作を残し、詳細文書へのリンクを置く。

# AGENTS.md

このファイルは AI コーディングエージェント(Claude Code / Codex / Antigravity CLI / GitHub Copilot 等)向けの汎用ガイドラインです。

## 言語

- エージェントの応答は日本語で行う。
- 日本語プロジェクトでは、コミットメッセージ・PR タイトル / 本文・ドキュメントなど成果物も日本語で統一する。

## リポジトリ概要

このリポジトリは **株式会社フィルイン (fillin Inc.) の公開 AI エージェント skill コレクション** です。`gh skill` 経由で社外を含む任意の開発環境へ配布されることを想定しています。

- 配布手段: `gh skill install <owner>/<repo> <name>`(TODO: GitHub 上の owner / repo が確定したら実名に置き換える)
- 可視性: **public**
- ライセンス: **MIT**(詳細は「ライセンス方針」節)
- 社内限定の skill は private リポジトリ `internal-skills` 側で管理する。本リポジトリには **公開して問題のない汎用 skill のみ** を置く

### public リポジトリであることの含意

**MUST**: 本リポジトリへ追加するすべてのファイルは、第三者に読まれる前提で書く。

- 社内固有の URL・ホスト名・アカウント ID・顧客名・案件名を書かない(必要な場合は環境変数化し、README に変数名だけ記す)
- 社内向けの運用前提(特定メンバーの環境・社内ツール名)に依存する記述を skill 本文へ埋め込まない
- 内部リポジトリ `internal-skills` から skill を移植する際は、移植 PR で上記の観点を 1 ファイルずつ確認する

## 技術スタック

- Markdown — skill 本体 (`SKILL.md`) / 参照ドキュメント / ガイドライン
- POSIX sh / bash — skill 同梱スクリプト (`skills/<name>/scripts/`) および lint スクリプト (`bin/`)
- GNU Make — lint / test / validate のエントリポイント
- GitHub Actions — CI
- `gh` CLI + `gh skill` 拡張 — skill の配布・spec 適合検証

ビルド工程は持たない(コンパイル対象なし)。

## ビルド・開発コマンド

```bash
make help      # 利用可能なコマンドを表示
make lint      # shellcheck + frontmatter / HOW_TO_USE / 括弧ルール 等の検証
make test      # bin/tests/test-*.sh の単体テスト
make validate  # gh skill publish --dry-run (spec 適合検証)
```

## ライセンス方針

本リポジトリの skill は **MIT License** を基本とする。

- ルートに `LICENSE`(MIT、著作権者は `株式会社フィルイン / fillin Inc.`)を置く
- **MUST**: 各 skill は `skills/<name>/LICENSE` を **同梱** する。`gh skill install` はファイルコピー配布のため、配布先の環境にルートの `LICENSE` は存在しない。skill 単体で見てライセンスが判明する状態を保つ
- **MUST**: 各 skill の `SKILL.md` frontmatter に `license: MIT` を記載する
- MIT 以外のライセンスを採用する skill を追加する場合は、当該 SPDX 識別子を frontmatter と同梱 `LICENSE` の双方に反映し、README のカテゴリ別一覧にも注記する
- 第三者コードを取り込む場合は、そのライセンス条文を `skills/<name>/LICENSE` に併記する(MIT 単独にしない)

ルート `LICENSE` と各 skill 同梱 `LICENSE` の整合は `bin/lint-license.sh`(`make lint` に含まれる)が機械検証する。

## プロジェクト構成

```
<repo>/
├── skills/                # skill 本体(gh skill のディスカバリ規約)
│   └── <name>/
│       ├── SKILL.md
│       ├── LICENSE        # MIT(必須・同梱)
│       ├── HOW_TO_USE.md  # 人間向けリファレンス(必須)
│       ├── scripts/       # skill 専用スクリプト(同梱、agentskills.io 仕様準拠)
│       └── references/    # 参照ドキュメント(任意)
├── bin/                   # lint スクリプトとその単体テスト
│   └── tests/
├── docs/
│   ├── guidelines/        # 横断的設計ガイドライン(portable)
│   ├── requirements/      # spec skill (--kind requirements) の出力先
│   └── specs/             # このリポジトリ固有の機能仕様
├── .github/workflows/ci.yml
├── AGENTS.md
├── CLAUDE.md
├── LICENSE
├── README.md
└── Makefile
```

### `docs/` 配下のドキュメント種別

| ディレクトリ | 位置付け | 判定基準 |
|---|---|---|
| `docs/guidelines/` | 横断的設計ガイドライン (portable) | skill 設計一般に通用する原則。このリポジトリ固有の skill 名・実装細部を書かない |
| `docs/specs/` | このリポジトリ固有の機能仕様 | 特定 skill 群が共有する実装機構の SSOT。このリポジトリの skill 名・スクリプトパスに紐付く |
| `docs/requirements/` | `spec` skill (`--kind requirements`) の出力先 | 設計ドキュメントではなく生成物置き場 |

**リンクの許容度**:

- **`skills/**` 配下 (`SKILL.md` / `references/` / `scripts/`) から `docs/` 配下への参照は全面禁止**。`gh skill install` はファイルコピー配布のため、配布後の環境に `docs/` は存在しない。ルール本文は skill 側にインライン記述し、docs/ への「参照」breadcrumb も置かない
- **`skills/**` 配下からは `docs/` に加え、リポジトリルートのガバナンスファイル (`AGENTS.md` / `README.md` 等) への典拠参照も置かない**。理由は同じ。ただし、**実行時に対象リポジトリの同名ファイルを読む runtime 記述**(例: 「AGENTS.md があれば読み込む」)はこの禁止の対象外
- docs/ は skill author が maintain 時に参照する SSOT。skill 実行時経路には乗せない
- `AGENTS.md` / `README.md` / `docs/` 配下 間の相互リンクは自由

### Skill 配置の原則

- `gh skill` のディスカバリ規約 (`skills/*/SKILL.md`) に従う
- skill 名はディレクトリ名と frontmatter `name:` を一致させる
- skill 名は agentskills.io の strict naming(kebab-case 必須。アンダースコア不可、連続ハイフン不可、先頭/末尾ハイフン不可、1-64 文字)
- skill 名は配布先ホスト CLI(Claude Code / Codex / GitHub Copilot CLI / Antigravity CLI)の **組み込みコマンド・組み込み skill 名と衝突させない**。いずれか 1 ホストでも同名だと、そのホストで起動が組み込み側に奪われる / 曖昧化する。新規追加・改名時は 4 ホストの組み込みと突き合わせる(判断に迷えばホストの `/help` 相当で確認する)
- skill が利用するスクリプトは `skills/<name>/scripts/` に **同梱** する(agentskills.io 仕様の推奨レイアウト)
  - `gh skill install` はファイルコピーで配布されるため、リポジトリ外/共通スクリプトの symlink は機能しない
  - 共通スクリプトを参照したい場合は実体をコピーして同梱する
- **MUST**: 各 skill は `skills/<name>/HOW_TO_USE.md`(人間向けリファレンス)を 1 枚持つ。オプション一覧・各機能・組み合わせ別の特殊用法を記載する。**`SKILL.md` / `references/` からはリンクしない**(エージェントの実行経路に乗せない)。SSOT はあくまで `scripts/` の引数解析スクリプトと `SKILL.md` で、`HOW_TO_USE.md` はその派生。配置・必須セクションは [`docs/guidelines/skill-how-to-use.md`](docs/guidelines/skill-how-to-use.md) を参照
- **MUST**: 各 skill は `skills/<name>/LICENSE` を同梱する(「ライセンス方針」節を参照)

### frontmatter

必須フィールド:

- `name`: skill 名(kebab-case、parent ディレクトリ名と一致、1-64 文字)
- `description`: 1-1024 文字。YAML block scalar (`|` / `>`) は禁止(lint で fail させる)。**capability (_what_) と起動条件 (_when_) を書き、内部手順 (_how_) は要約しない**。詳細は [`docs/guidelines/skill-description-writing.md`](docs/guidelines/skill-description-writing.md) を参照
- `license`: 本リポジトリの skill は原則 `MIT`。例外を設ける場合は「ライセンス方針」節に従う

任意フィールド:

- `argument-hint`: agentskills.io 仕様の top-level allowlist 外だが、ホスト CLI が引数ヒント表示に使うため、本リポジトリの lint 許可リストに含めている
- `allowed-tools`: 書く場合は string(配列 NG)
- `compatibility`, `metadata`: 必要に応じて
- `model` / `effort`: **Claude Code 固有拡張**(他ホストでは無視される)。いずれも任意で、**判断・対話・深い推論が中心の skill には付けない**。判断基準は [`docs/guidelines/skill-model-effort.md`](docs/guidelines/skill-model-effort.md) を参照

`bin/lint-frontmatter.sh` が agentskills.io 仕様に基づいて機械検証する。

### SKILL.md 本文の行数上限

SKILL.md は frontmatter を除いた本文を **500 行以下** に保つ(`bin/lint-frontmatter.sh` が hard limit として fail させる)。超過したら手順そのものは削らず、詳細スキーマ・参照テーブル・長い判定ルールを `skills/<name>/references/` へ逃がして SKILL.md からリンク参照する。

### 設計ガイドライン

新規 skill の追加・既存 skill の強化を行う際は `docs/guidelines/` 配下を参照する。主要なものは次のとおり。

- [`skill-design.md`](docs/guidelines/skill-design.md) — Discipline パターン / Pressure Test / 命名原則 / token 効率
- [`script-first.md`](docs/guidelines/script-first.md) — 決定的処理を script へ切り出す判断軸
- [`skill-description-writing.md`](docs/guidelines/skill-description-writing.md) — description の書き方と初期 discovery 予算
- [`markdown-punctuation.md`](docs/guidelines/markdown-punctuation.md) — 括弧の全角/半角ルール
- [`markdown-list-nesting.md`](docs/guidelines/markdown-list-nesting.md) — リスト項目のネスト規約
- [`ambiguity-resolution-pattern.md`](docs/guidelines/ambiguity-resolution-pattern.md) — 曖昧解決 discipline
- [`node-dependencies.md`](docs/guidelines/node-dependencies.md) — Node.js 依存の取り扱い

### Subagent 起動の方針

skill 本文に「subagent を使え」「`Agent` tool を起動せよ」と書かない。委譲に積極的か inline 推論に寄せるかはモデル世代・ホスト実装で変動するため、skill 側は **手段ではなく委譲基準を書く**。

委譲基準:

- **委譲してよい**: 互いに独立で、それぞれ複数ファイルの読み込み・検索を伴う規模の調査 / レビュー / 監査
- **単一の流れで完結させる**: 数件の tool call で終わる作業、直前の結果を見てから次の手順が決まる作業
- **委譲しない**: 自分が行った作業を検証する目的の委譲(検証は証拠の再取得で行う)
  - 別 CLI・別コンテキストの reviewer を独立して当てる設計はこの禁止の対象外

skill 本文での書き方:

- 並列性が必要な場合は「**並列に実行する**」とだけ書く(手段はホストの自律判断に委ねる)
- 各タスクの独立性が必要な場合は「他タスクの結果を参照しない独立タスクとして扱う」と書く(メカニズムは指定しない)
- ホスト別 subagent 起動 API (`subagent_type` 等) を skill 本文に列挙しない

## コーディングスタイル

### シェルスクリプト

- ShellCheck でリントを行う
- POSIX 互換を心がける(`#!/bin/sh` 推奨。bash 機能が必要なら `#!/bin/bash`)
- エラーハンドリングを適切に行う(`set -eu` を基本)

### SKILL.md 本文

- エージェント中立に書く(特定ホストの API・名称を埋め込まない)
- 単独で動く skill は本文に他 skill 名を書かない(協調はマーカー / プロトコルで)。ただし **一式として動作する前提の skill 群** は、description および本文での相互参照を許容する
- **人間向けの使い方リファレンス `HOW_TO_USE.md` へもリンクしない**(実行経路に乗せないため)
- 必要な処理だけ記述する(「やらないこと」の否定形・各 Phase で扱い済み内容の Notes 再掲は避ける)
- **MUST**: 同梱スクリプトは `"$SKILL_DIR/scripts/<name>.sh"` の絶対パスで呼び、`./scripts/...` とも `scripts/...` とも書かない(cwd 相対記法は skill ディレクトリへの `cd` を誘発する)。`sh` / `bash` を前置せず直接実行する(bash 専用構文を含む同梱スクリプトがあるため shebang を尊重する)。`bin/lint-script-invocation.sh`(`make lint` に含まれる)が機械検出する

### Markdown

- **括弧は半角に統一する。全角括弧は使わない**。唯一の例外はインラインコードで、全角であること自体が意味を持つ記述の逃がし場所として使う。`bin/lint-markdown-punctuation.sh`(`make lint` に含まれる)が機械検証し、`--fix` で一括修正できる
- 1 つの list 項目に **独立した事実** を 2 つ以上詰め込むときは `/` 区切りの 1 行ではなくネスト list の子項目として分ける。事実が 1 つならフラットな 1 行のままで良い

## テスト方針

- 新しい skill を追加した場合は、実際にホストエージェントから呼び出して動作確認を行う
- `make lint` で全リントを実行する
- `make test` で lint スクリプトの単体テストを実行する
- `make validate` で `gh skill publish --dry-run` を通す

## コミット指針

- **Conventional Commits** 形式を使用する。
  - `feat:` — 新機能
  - `fix:` — バグ修正
  - `docs:` — ドキュメント
  - `refactor:` — リファクタリング
  - `chore:` — その他の変更
- コミットメッセージは日本語をデフォルトとする。
- コミット粒度は細かくて良い。PR は squash-and-merge で単一コミットに丸められる前提のため、PR 単位で成立していれば良い。
- 必要な場合は `Co-authored-by` トレーラーを末尾に付与する(使用するエージェントに応じた値を設定する)。

## PR 作成ルール

- PR タイトルも **Conventional Commits** 形式に寄せる(squash-and-merge 後のコミットメッセージがそのまま PR タイトルになるため)。
- issue 駆動の PR は本文に `Closes #N`(または `Fixes #N`)を必ず含め、マージ時に自動で close されるようにする。
- マージ方式は **squash-and-merge** をデフォルトとする。
- **1 PR = 1 目的**。1 つの PR で複数の論点を混ぜない。

### umbrella 型 issue の PR オーケストレーション

親 issue に複数の子 issue (sub-issues) がぶら下がる **umbrella 型** の構成では、次の手順で PR をスタックして作業を進める。

1. 親 issue に対応する**親 PR** を先に用意する(base = `main`)。
2. 各子 issue に対応する**子 PR** は、**親 PR の feature ブランチを base に向けて**作成する(`main` には直接向けない)。子 issue の起票時に「base は main」と指示されていても、親 PR が open な間は親ブランチを base にする。
3. 子 PR を**親 PR に順次マージ**しながら作業を進める(親 PR の差分が umbrella の全体像を常に表す状態を維持する)。
4. すべての子 PR がマージされたら、最終的に親 PR を `main` にマージする。

## Git 運用ルール

- ブランチモデルは **GitHub Flow** を採用する(`main` は常時デプロイ可能に保ち、機能開発はブランチ + PR で進める)。
- 何らかの変更を加える場合は**必ず**ブランチを切ってから作業を開始する(`main` 上での直接コミット・直接 push は禁止)。
- ブランチ命名規則は Conventional prefix + slug とする。
  - `feat/` — 新機能追加
  - `fix/` — バグ修正
  - `docs/` — ドキュメント更新
  - `refactor/` — リファクタリング
  - `chore/` — その他の変更
- issue ベースで開発する場合はブランチ名に issue 番号を含める(例: `feat/136-agents-base-md`)。issue が無い ad-hoc な作業では issue 番号を省略して `<type>/<slug>` とする。

### リリース

skill を公開バージョンとして固定したい場合は `gh skill publish` で tag を切る。

```bash
gh skill publish --dry-run    # 検証のみ
gh skill publish --tag v0.1.0 # tag を切って release 作成
```

## 品質ゲート

- コミット前 / PR 化前に `make lint` と `make test` を必ず実行する。
- skill を追加・変更した PR では `make validate` も実行する。

## GitHub 参照

- GitHub 関連の操作(issue / PR / checks / releases の取得・作成・更新など)は **`gh` CLI を優先利用する**。Web UI 経由の手動操作や、生の REST / GraphQL 呼び出しより `gh` コマンドを先に検討する。
- issue / PR の URL を与えられた場合も `gh` 経由で情報取得する。

## セキュリティ

- API キー、トークンなどの機密情報をコミットしない。
- `.env` ファイルや認証情報は `.gitignore` に追加する。
- スキル / プロンプト内で機密情報を扱う場合は環境変数を使用する。
- **本リポジトリは public**。社内固有の URL・ID・顧客名・案件名を書かない(「public リポジトリであることの含意」節を参照)。

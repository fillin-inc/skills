# Skill frontmatter `description` の書き方

`skills/**/SKILL.md` の frontmatter `description` フィールド (1-1024 文字) の書き方を規定する。YAML block scalar (`|` / `>`) は禁止 (lint で fail させる。長さ検証が骨抜きになるため)。

## 大原則

**skill の能力 (capability, _what_) と起動条件 (triggering conditions, _when_) を書く。内部の手順 (workflow, _how_) は要約しない**。

description で手順を summary すると、ホストエージェントが SKILL.md 本体を読まずに description の手順だけに従って動作してしまい、本来のフローが省略されるトラップが発生する (capability や起動条件は手順ではないので書いてよい。手順だけが禁止対象)。

### 例

- BAD (手順を列挙): `"spec md を読み込んでプランを生成し、ユーザー承認を経て plan.md に保存する skill"`
- BAD (手順を列挙): `"git diff を取得して codex CLI に渡し、出力を JSON に正規化してから指摘を表示する skill"`
- GOOD (capability + 起動条件): `"spec md から実装プランを作成・承認する skill。新しい spec md から作業に着手したいとき、または既存プランを refine したいときに使う"`
- GOOD (capability + 起動条件): `"差分や PR に外部 CLI 経由でコードレビューを掛ける skill。"レビューして" / "check this PR" / "コードレビュー" のような要求で起動"`

## 起動条件 (when) の書き方

host の undertrigger 傾向に対抗し trigger 精度を高めるため、次の指針に従う。

- **具体的な trigger phrase を含める**: ユーザーが実際に打ちそうな自然文 (例: `"commit して"` / `"PR 作って"` / `"review コメント直して"`) を 1〜複数含めると発火率が上がる。日本語セッションでは日本語 trigger phrase を入れる
- **競合する skill との優先順位を明示**: 似た役割の skill が複数ある場合は `prefer this over X for Y` / `use X instead when Z` のように差分を description 内で書く。host の選択判断に直接効く
- **上流 / 下流 skill との位置関係を書く**: `before invoking X` / `after \`git add\`` のような前後関係は when の具体化であり書いてよい (how ではない)
- **trigger surface を広げる**: capability の周辺ユースケースを副詞句で列挙 (例: `Use this skill for any PR lifecycle operation, including review comment triage and CI failure recovery`)。how には踏み込まない範囲で起動条件のバリアントを増やす

## 総量観点 (初期 discovery 予算)

ホストエージェント (Claude Code / Codex / GitHub Copilot CLI / Antigravity CLI 等) は起動時に install 済み skill の frontmatter `description` 一覧をモデルコンテキストへ載せ、自然文からの暗黙起動候補として使う。この初期一覧には各ホストごとに予算がある (例: Codex は既定でモデル context window の 2%、context window 不明時は 8,000 文字を上限にし、超過時は description を短縮・一部 skill を初期一覧から省略する)。予算超過は「明示 `$skill-name` 起動はできるが、自然文からの発火が不安定になる」形で表面化する。

- **予算は「ホスト × install セット」単位で効く**。`gh skill install` は skill 単位の配布であり、利用者は用途別セット (開発 / 執筆 / 調査 等) を選んで install する。リポジトリ全体の description 総量ではなく、**推奨セット内の合計** が対象ホストの初期 discovery 予算に収まるかを見る
- **個々の description は目安として 200〜400 文字**。capability + 主要 trigger + 最重要な境界 (競合 skill との差分・上下流関係) に絞り、trigger phrase を description 前半へ置く。オプション詳細・workflow 説明・競合表は SKILL.md 本文または `HOW_TO_USE.md` に残す
- **検証手段**: 各ホストの skill 一覧表示コマンド (Codex なら `codex debug prompt-input` 等) で、対象 skill が初期一覧に残ることを確認する

README で推奨セットを定義・更新するときは、このセット単位の予算を意識する。

## 関連

- [`skill-design.md`](skill-design.md) — 3. description CSO 原則
- [`skill-how-to-use.md`](skill-how-to-use.md) — description に書かない詳細の逃がし先

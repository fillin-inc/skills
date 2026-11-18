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

## 総量観点

description の総量 (install セット単位の予算) については [`skill-description-budget.md`](skill-description-budget.md) を参照。

## 関連

- [`skill-design.md`](skill-design.md) — 3. description CSO 原則

# Skill 設計ガイドライン

本リポジトリで **新規 skill を追加・既存 skill を強化する際の参照ドキュメント**。
`docs/specs/` がこのリポジトリ固有の機能仕様を記述するのに対し、本ドキュメントは横断的な設計原則を定義する。

---

## 1. Discipline パターン

"Discipline skill" とは、エージェントが圧力下でも特定のルールを遵守させることを目的とした skill。

### Iron Law

```
SKILL に FAILING TEST なければ SHIP するな
```

新規追加にも編集にも適用。「documentation だけの変更」も例外なし。skill を書く前に、その skill がなければエージェントが違反する pressure シナリオを必ず確認する。

### Spirit vs Letter

> "Violating the letter of the rules is violating the spirit."

エージェントが「ルールの精神は守っているが文字通りには従っていない」と論じはじめたら、それはルール違反。skill 本文ではこのロジックを明示的に封じる。

### Red Flags(自己チェックリスト)

skill を書いたら以下の兆候がないか確認する:

- [ ] description に手順のサマリが含まれている(→ CSO 違反)
- [ ] loophole を残したまま「spirit で判断できる」と書いている(→ Iron Law 違反)
- [ ] 圧力シナリオを試す前に ship した(→ TDD 違反)
- [ ] rationalization への反論が skill 本文にない(→ Bulletproofing 不足)
- [ ] 複数 skill を同時に書いた(→ 1 つずつ deploy すべき)
- [ ] モデル自身の内部推論を出力させる指示を書いた(→ [7. 内部推論の開示を指示しない](#7-内部推論の開示を指示しない) 違反)

### Rationalization 撃退表

pressure 下でエージェントがよく使う言い訳と、その封じ方:

| Rationalization | 封じ方 |
|---|---|
| 「今回は特殊ケースなので例外」 | 例外規定を明示し「それ以外は一切例外なし」と明記 |
| 「ルールの精神は守っている」 | "Violating the letter is violating the spirit." を skill 本文に入れる |
| 「次のステップで修正するから今はスキップ」 | 「後回し禁止」を Iron Law として明示する |
| 「ユーザーが急いでいるのでこの手順は省略」 | `--auto` フラグでも省略できないステップを明記 |
| 「この変更は小さいので baseline チェック不要」 | "any change" に Iron Law を適用すると明記 |

### Loophole の明示的封鎖

skill を書くときは「どうすれば誰かがこの skill を回避できるか」を考え、その経路を本文に記載して封じる。「明示していない＝許可」と解釈されることがある。

---

## 2. Pressure Test 方法論(RED-GREEN-REFACTOR)

### なぜ Pressure Test が必要か

エージェントは「普通の状況」では概ねルールを守る。問題は圧力がかかったとき(締め切り・複雑な依存・ユーザーの催促など)にルールを rationalize して破ることがある。skill は最大 pressure 下での compliant を目標にする。

### RED フェーズ: Baseline を記録する

1. **pressure シナリオを設計する**(discipline skill は 3+ つの pressure を組み合わせる)
   - 例: 「締め切り圧力」＋「複雑な依存関係」＋「ユーザーが急かしている」
2. **skill なしでエージェントにシナリオを実行させる**
3. エージェントの選択・rationalization・どの pressure で違反したかを **verbatim で記録** する

> "If you didn't watch an agent fail without the skill, you don't know if the skill teaches the right thing."

### GREEN フェーズ: 最小 skill を書く

1. RED で観測した違反 **だけ** を潰す最小の skill を書く
2. 同じ pressure シナリオを再実行し、compliant になることを確認する
3. 複数の違反を一度に潰そうとしない(どの記述が効いたか分からなくなる)

### REFACTOR フェーズ: Bulletproof にする

1. GREEN になったら、新たな rationalization が出ないか別の pressure で再テストする
2. 新 rationalization が出たら **その counter を skill 本文に追加** して再テスト
3. 最大 pressure 下でも compliant になるまでサイクルを繰り返す

### AGENTS.md との整合

pressure test のために並列にエージェントを起動する場合、skill 本文では「**並列に実行する**」とだけ書く。subagent 起動の具体的な API(`subagent_type` 等)は書かない([AGENTS.md: Subagent 起動の方針](../../AGENTS.md#subagent-起動の方針) 参照)。

### `--auto` 無人完走トレース

`--auto` は「skill 内のユーザー確認プロンプト・人間判断項目をすべて skip して無人完走させる」フラグとして扱う (すでに skill が行う対話の skip のみを意味し、破壊的操作の追加実行や新たな書き込み権限を意味しない)。

`--auto` フラグを持つ skill は、入力を受け取ってから終端に到達するまでの全分岐を **机上でトレースし、ユーザー応答待ちに到達する経路がゼロであることを確認する**。設計時にも改修時にも実施する。無人実行という「圧力」下で discipline が破綻しないかの確認であり、Pressure Test の一種として扱う。

トレース手順:

1. `--auto` を渡した状態で skill 本文・呼び出しスクリプト・下流 skill を辿り、分岐(`if AUTO=true` / `if AUTO=false`)と対話 gate(承認要求・番号選択の再問い合わせ・自由文入力の待受け等)をすべて列挙する
2. 各分岐で `--auto=true` 経路がどこへ流れるかを追う。ハードエラー時の停止(コンパイル失敗・テスト失敗・致命的な Git 操作失敗)は仕様上許容される終端。ユーザーへの clarifying question や y/n 承認待ちに落ちる経路が 1 つでもあれば設計不良として塞ぐ
3. 下流の別 skill を呼ぶ場合、その skill にも `--auto` が forward されていることを確認する(forward し忘れると下流で応答待ちに落ちる)
4. 新規オプション追加・分岐追加・下流 skill 差替えを行った改修 PR では同じトレースを再実施する

机上トレースだけでも「対話 gate に落ちる経路がゼロ」を保証できないと判断したら ship しない。全経路の実走が困難な場合でも、机上トレース自体は省略しない。

### STOP: 複数 skill を同時に書かない

> "After writing ANY skill, you MUST STOP and complete the deployment process."

1 つの skill を書いたら必ず test → deploy してから次に進む。バッチで複数 skill を書くと、どの記述が効いたか(or 壊したか)が分からなくなる。

---

## 3. description CSO 原則

CSO(Claude Search Optimization): エージェントが skill を正しく選択・実行するための description 最適化。

### 核心原則

```
description には「skill の能力(capability)」と「いつ使うか(triggering conditions)」を書く。
skill の手順(workflow)を要約してはいけない。
```

**なぜか:** description に手順のサマリが含まれると、エージェントが SKILL.md 本体を読まずに description の手順だけに従って動作する。結果として本来のフローが省略される。capability と起動条件は手順ではないので書いてよい。手順の要約だけが禁止対象。

> 例: description に "code review between tasks" と書いたら、SKILL.md の 2 段 review を無視して 1 回しか review しなくなった。description を capability + triggering conditions だけにしたら正しく動くようになった。

この原則は AGENTS.md の frontmatter セクションと整合している([AGENTS.md: frontmatter](../../AGENTS.md#frontmatter) 参照)。

### 良い description / 悪い description

| | 例 |
|---|---|
| ❌ 手順を列挙 | `"spec md を読み込んでプランを生成し、ユーザー承認を経て plan.md に保存する skill"` |
| ❌ workflow を要約 | `"git diff を取得して codex CLI に渡し、出力を JSON に正規化してから指摘を表示する skill"` |
| ✅ capability + 起動条件 | `"spec md から実装プランを作成・承認する skill。新しい spec md から作業に着手したいとき、または既存プランを refine したいときに使う"` |
| ✅ capability + 起動条件 | `"差分や PR に外部 CLI 経由でコードレビューを掛ける skill。"レビューして" / "コードレビュー" のような要求で起動"` |

### Keyword Coverage(検索性向上)

description に以下を含めることで、エージェントが正しい文脈で skill を選択しやすくなる:

- エラーメッセージ・症状の自然文("flaky", "hanging" 等)
- 同義語("timeout/hang/freeze" をすべて入れる)
- 実際に使われるコマンド名・ライブラリ名
- ユーザーが発しそうなフレーズ

---

## 4. 命名原則

### Skill 名

- kebab-case 必須。アンダースコア・連続ハイフン・先頭末尾ハイフン不可、1-64 文字
- 命名スタイルの指定なし(imperative verb: `implement` / `commit`、noun-phrase: `spec` / `decision-record` など既存 skill の形を参考にする)

### AGENTS.md との整合

skill 名のディレクトリ名と frontmatter `name:` フィールドを一致させる([AGENTS.md: Skill 配置の原則](../../AGENTS.md#skill-配置の原則) 参照)。

---

## 5. Token 効率の目安

頻繁にロードされる skill ほど、コンテキスト消費が積み重なる。

| カテゴリ | 語数目安 |
|---|---|
| getting-started 系(オンボーディング) | 各 < 150 words |
| frequently-loaded(毎タスクで使う) | 合計 < 200 words |
| 通常の technique / pattern | < 500 words |
| reference(辞書的に参照) | 制限なし(supporting file に外出し推奨) |

### 削減テクニック

- **フラグ説明は `--help` に外出し**: skill 本文には「`--help` を参照」とだけ書く
- **cross-reference で重複排除**: 他 skill / docs に書いてある内容は再掲しない
  - ✅ `REQUIRED: 上流 skill でプランを確定させてから起動`
  - ❌ 上流 skill の手順を copy-paste
- **example を圧縮**: 1 つだけ excellent な例を書く(多言語例・網羅的例は NG)
- **narrative を排除**: 「〜という背景があって…」の導入文は書かない

### script-first との相乗効果

決定的処理をシェルスクリプトに切り出すと、SKILL.md に書く手順が減り token 消費が下がる([`script-first.md`](script-first.md) 参照)。

---

## 6. 失敗系設計の必須チェック

skill が外部 CLI・ネットワーク・別プロセスに依存する場合、成功系だけでなく失敗系の分岐を必ず設計する。skill が想定外の状況で「静かに成功したように見える出力」を返すと、下流の skill・ユーザー判断がすべて破綻する。

### チェックリスト

- [ ] **外部 CLI / ネットワーク呼び出しには 3 分岐を必ず定義する**: (a) 利用不能(CLI 未インストール / 必要な API・エンドポイントに到達不能 / 認証情報未設定)、(b) 実行失敗(認証エラー・レート制限・4xx / 5xx・非 0 exit を含む)、(c) ハング / タイムアウト(時間制限で打ち切る)。3 分岐すべてに挙動を割り当てていない状態で ship しない
- [ ] **「結果ゼロ(指摘なし)」と「実行不能(実行失敗)」を出力で区別する**: 両者を空出力・空配列で同じに丸めない。利用者と下流 skill が「見に行った結果ゼロ件だった」のか「そもそも見に行けなかった」のかを判別できるフィールド / メッセージを分けて emit する
- [ ] **exit code 契約はスクリプト header を SSOT とする**: 手順書(SKILL.md 本文)は「フォールバック可能な失敗なら続行」「致命的な失敗なら中断」のように **意味論(何を続行・何を中断するか)** で書き、数値と意味の対応表はスクリプト header 側に置く。数値を手順書に直書きすると header と乖離した瞬間に分岐漏れが生まれる

### アンチパターン

- 外部 CLI 呼び出しをそのまま埋め込み、失敗時は空文字を返して下流に流す
- タイムアウトを設けず「普段は数秒で返るから」と naked 実行する
- 「見つからなかった」も「実行失敗した」も同じ空出力で表現し、利用者に区別を委ねる
- 手順書に生の exit code(`if [ $? -eq 64 ]` 等)を直書きし、数値の意味をスクリプト側の SSOT から切り離す

---

## 7. 内部推論の開示を指示しない

skill 本文・references・スクリプトが生成するプロンプトのいずれでも、**モデル自身の内部推論(thinking)をそのまま応答へ書き出させる指示を書かない**。

現行モデル世代には内部推論の抽出要求に対する refusal カテゴリがあり、該当する指示は拒否・fallback 応答を誘発する。skill が途中で停止したり、以降の Phase が実行されないまま終わる事故につながる。

### NG / OK の線引き

判定軸は「**モデルの思考過程そのもの** を求めているか、**観測結果・成果物としての理由** を求めているか」。後者は対象外で、通常どおり書いてよい。

| | 例 |
|---|---|
| ❌ 思考過程の復唱 | 「判断に至った thinking をそのまま出力せよ」 |
| ❌ 内部推論の転写 | 「内部の推論トレースを逐語で書き出してから結論を述べよ」 |
| ❌ 推論過程の説明要求 | 「あなたの内部推論プロセスを説明せよ」 |
| ✅ 観測事実の記録 | 「実行したコマンドと stdout を verbatim で記録せよ」 |
| ✅ 判断根拠の提示 | 「その判定を裏付ける根拠(ファイルパス・行番号・エラーメッセージ)を挙げよ」 |
| ✅ 成果物としての理由 | 「採用案と却下案を、それぞれの理由を添えて md に書き出せ」 |

`root-cause-analysis` の evidence trail(観測事実の verbatim 記録)や、レビュー系 skill が要求する指摘理由の提示は ✅ 側に属する。「理由を書かせること」自体は禁止対象ではない。

### 書き換え方

内部推論の開示を書きたくなったら、求めている情報を **外形的に観測できる形** に置き換える。

- 「なぜそう判断したか思考を出せ」 → 「判断の根拠となった入力(該当行 / コマンド出力)を引用せよ」
- 「検討過程を見せろ」 → 「検討した選択肢と採否を表に列挙せよ」

---

## 参考

- [obra/superpowers — writing-skills/SKILL.md](https://github.com/obra/superpowers/blob/main/skills/writing-skills/SKILL.md) — 1. Discipline パターン / 2. Pressure Test 方法論 / 3. description CSO 原則 の原典
- [`script-first.md`](script-first.md) — 決定的処理を script へ切り出す判断軸
- [AGENTS.md](../../AGENTS.md) — frontmatter 規約・subagent 方針

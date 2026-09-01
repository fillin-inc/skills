# skill frontmatter の `model` / `effort` override

skill の frontmatter に書ける `model` / `effort` は **Claude Code 固有拡張** で、agentskills.io 仕様外のフィールド。Codex 等の他ホストでは無視されるため、このフィールドに依存した挙動を skill の前提にしてはならない。

## スコープ

- `model`: skill が active な間だけ動作モデルを override する。次の prompt で session model に戻り、**永続化されない**
- `effort`: 同じスコープで effort level を override する

## 指定の判断基準

いずれも **任意** であり、必須ではない。迷ったらフィールドごと省略して session model に委ねるのが安全側。

| skill の性質 | 指定 | 例 |
|---|---|---|
| 検出・コマンド実行が中心で深い推論を要しない | `model: haiku` / `effort: low` を任意で指定してよい | 静的検査、データ突き合わせ、定型コマンドの実行 |
| 生成が中心だが最上位モデルの推論力を必須としない | コスト最適化目的で `model: sonnet` を任意で指定してよい | 抽出・変換・翻訳・レポート生成 |
| 判断・対話・深い推論が中心 | **override を付けない**(フィールド自体を省略する) | 複雑度評価、分割判断、対話を通じた方針決定 |

`model: sonnet` を選ぶ場合、`effort` は skill の性質に応じて `low`〜`high` を任意併用してよい。例えば深い調査を伴う生成タスクには `effort: high` を併用する。

この表は **思考量に対する要求** で行を選ぶ。成果物の分量を調整する目的で `effort` を選んではならない(次節「effort の性質」を参照)。

## effort の性質

現行モデル世代(Claude Opus 5 / Claude Fable 5)の公式ドキュメントが示す effort の性質のうち、指定判断に直接影響する 2 点。

### effort は出力分量の制御手段にならない

`effort` は応答全体の token 使用量(思考量を主とし、可視テキストや tool call も含む)を調整するが、**可視出力の分量を確実に制御する手段にはならない**。Opus 5 のドキュメントは「changing effort does not reliably shorten responses, so prompt for length instead」として、長さの制御は prompt 側で行うよう指示している。

したがって:

- 成果物が冗長 / 薄いという問題を `effort` の上下で解決しようとしない。`effort` を下げてもテンプレートの全節を埋める挙動は変わらないことが多い
- 分量は prompt 側の較正文で制御する。成果物を書き出す skill では、出力テンプレートの冒頭に水増しを抑止する短い較正文を 1 箇所だけ置く
- 節数そのものを減らしたい場合はテンプレート側(`references/` の出力 template や SKILL.md 本文の出力構造定義)を変更する

### 低 effort の品質は世代を追って向上している

Opus 5 のドキュメントは「use low and medium liberally as your primary control for token cost」、Fable 5 のドキュメントは「lower effort settings still perform well and often exceed xhigh performance on prior models」としている。低 effort を **token コストの第一の制御軸** として選ぶことは現行世代では妥当で、旧世代の基準で「品質のために上振れさせる」判断は見直しの対象になる。

ただしこれは「同一世代内で低 effort と高 effort の品質が等価」という主張ではない。判断・対話・深い推論が中心の skill は前節の表 3 行目のとおり override を付けない方針を維持し、コスト理由だけで下振れさせない。

この帰結として、旧モデル世代の基準で決めた `effort` の pin は世代更新のたびに陳腐化しうる。

## 世代更新時の effort pin 再評価

**MUST**: 本リポジトリが前提とするモデル世代が変わったときは、既存 skill の `effort` pin を棚卸しして再評価する。

前提として、**現行世代の既定 effort 値は本ガイドラインに焼き込まない**(世代更新で陳腐化するため)。再評価の実施時に、対象モデルの公式ドキュメントとホスト側の現在設定(Claude Code なら `/config` 相当)から既定値を確認してから判定に入る。

判定は次の順で行う。

1. **既定値と同値になった pin は、pin の意図で残置 / 削除を分ける**
    - コスト最適化のために「その値まで下げる」目的で付けた pin は削除する。既定と同値なら効果が無く、次の世代更新で再び陳腐化する負債だけが残る(例: Opus 4.x 期に付けた `effort: high` は Opus 5 では既定値と同値になり、下げる目的の pin としての意味を失う)
    - session effort が既定より低く設定されていても **その effort を保証する** 目的で付けた pin は残す。pin は session 設定に対する override として働くため、モデル既定と同値でも削除すると挙動が変わる
2. **上振れ側の pin(既定より高い値)は 1 段下げて成果物の品質を確認する**。低 effort の品質が向上しているため、旧世代で必要だった上振れが不要になっていることがある。品質が落ちるなら元の値に戻す
3. **下振れ側の pin(既定より低い値)は据え置きを既定とする**。低 effort の品質向上は下振れ pin にとって順風であり、値を戻す動機は無い

pin を残す判断をした場合は、その pin が「値を変えるため」か「値を保証するため」かを skill 側で読み取れる状態にしておく(判断が非自明なら SKILL.md 側に 1 行残す)。

## lint との関係

両フィールドとも lint の許可リストに含めているため、指定しても warning は出ない。

## 参照

- [Skills frontmatter reference](https://code.claude.com/docs/en/skills)
- [`skill-design.md`](skill-design.md) — skill 設計原則

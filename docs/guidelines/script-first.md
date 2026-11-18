# スクリプト化の原則 (script-first)

skill を追加・修正するときは、まず「**自然言語で LLM に指示するより skill 内 `scripts/` のスクリプトに切り出すべき処理がないか**」を検討する。

## 理由

- **安定性**: 決定的処理を自然言語で指示すると出力ゆれ・LLM 依存の見落としが発生する
- **トークン削減**: 同じ手順を SKILL.md に書き連ねるとセッション毎にトークンを消費する

## スクリプト化を優先する処理

- 引数・フラグの解析
- GitHub の issue / PR 情報取得 (`gh` の薄いラッパ)
- ベースブランチ・パス正規化など決定的な計算
- マーカー差し込み・テキスト編集

## 自然言語に残す処理

- 文章生成・要約・カテゴライズなど判断や言い換えを伴う処理
- ユーザーとの対話・承認ガード

## 独立 script にするかの 2 軸判定

独立 script にするかの可否は次の 2 軸で判定する (両方を満たすときだけ独立 script にする)。

1. **決定的か**: 入力ごとに正解が一意に決まるか。字句・構文的な分類 (パス形状・issue 番号・拡張子の判定等) は決定的処理として script 側に置く。意味内容の解釈・言い換え・対話を伴う処理は NL 側に残す
2. **script 化のコストが見合うか**: 複数 skill へ実体コピーする共通スクリプトの drift 管理・失敗系分岐の実装・SKILL.md ↔ script の二重更新というコストが、その処理の脆さ・再利用性・分岐複雑度に見合うか

第 1 軸を満たすが第 2 軸を満たさない軽量な決定的処理 (1〜2 分岐の reject 判定等) は、独立 script にせず SKILL.md 本文のインライン shell snippet (数行の `if` / `case`) として記述する。インライン snippet は fail-fast の決定性を保ったまま script ファイルの保守コスト (shared 配布・二重更新) を避ける中間形態として扱う。

## 実装言語の選び方(Node.js が既定)

skill を実行するホストは Node.js 22 以上を備える前提とし([`node-dependencies.md`](node-dependencies.md#実行ホストの-nodejs-前提))、script は Node.js(`.mjs`)で書くのを既定とする。sh は次の場合だけ使う。

- 外部コマンドを呼ぶだけの薄いラッパー。引数を渡して結果をそのまま返し、出力の加工・状態管理・分岐の組み合わせを持たないもの(`gh api` を 1 回呼ぶ、`diff -u` で差分を出す、`mktemp` で一時ディレクトリを作るなど)
- skill が利用者のリポジトリへ生成する runtime script。生成先のリポジトリや CI で Node.js を前提にできない

次は sh に残す理由にしない。

- 短い、分岐が少ない
- 呼び出し側の shell へ `eval` で値を返す。Node.js から `KEY='value'` 行を出せばよい
- 依存の preflight。足りないのは npm パッケージだけなので、組み込みモジュールで書けば導入前に動く
- 待機ループやプロセス制御。`child_process` の `timeout` で書ける
- git / gh を多く呼ぶ。呼び出しの間に分岐・加工・ハング対策があるなら Node.js で書く

Node.js を既定にする理由:

- Mac と Linux の差を吸収する回避コードが要らなくなる(`stat -c` / `stat -f`、`date -d` / `date -v`、`timeout` / `gtimeout`、`sed` の方言、`shasum` / `sha256sum` など)
- JSON / Markdown / YAML / CSV の解析や状態管理を、jq / awk / sed の多段パイプや一時ファイルを使わずに書ける
- 言語とテスト方法(`node --test`)が揃う

外部ソフトのインストール先(ブラウザのパスなど)の違いは Node.js でも残るため、`process.platform` で分岐する。既存の sh は、改修のタイミングで Node.js に置き換える。

Node.js で書くときの規則:

- Node.js の組み込みモジュールだけを使う(`node:fs`、`node:util` の `parseArgs`、`node:child_process`、`node:crypto`、`fetch` など)。npm パッケージが必要な場合は [`node-dependencies.md`](node-dependencies.md) に従う
- 呼び出し側の shell へ値を返すときは、eval-safe な `KEY='value'` 行を stdout に出す。sh から移行しても呼び出し側の `eval` を変えずに済む
- 外部コマンドは `child_process` の `execFile` / `spawn` で引数配列として渡し、shell を経由しない。応答が返らないおそれがあるコマンドには `timeout` を付ける
- 移行前の sh にテストがなければ、sh の出力を基準にした比較テストを先に用意してから置き換える

## 関連

- [`skill-design.md`](skill-design.md) — token 効率の目安 (script-first との相乗効果)

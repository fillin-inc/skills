# Skill description 総量の考え方(初期 discovery 予算)

ホストエージェント(Claude Code / Codex / GitHub Copilot CLI / Antigravity CLI / OpenCode 等)は起動時に install 済み skill の frontmatter `description` 一覧をモデルコンテキストへ載せ、自然文からの暗黙起動候補として使う。この初期一覧には各ホストごとに予算がある(例: Codex は既定でモデル context window の 2%、context window 不明時は 8,000 文字を上限にし、超過時は description を短縮・一部 skill を初期一覧から省略する)。予算超過は「明示 `$skill-name` 起動はできるが、自然文からの発火が不安定になる」形で表面化する。

運用方針:

- **リポジトリ全体の description 総量は指標にしない**。`gh skill install` は skill 単位の配布であり、利用者は用途別セット(開発 / 執筆 / 調査 等)を選んで install する前提で、全 skill を単一ホストの単一 scope へ入れることは想定しない
- **予算は「ホスト × install セット」単位で効く**。README のカテゴリ別一覧や推奨セットを新規に定義・更新するときは、その **セット内の description 合計** が対象ホストの初期 discovery 予算に収まるかを意識する
- **個々の description は目安として 200〜400 文字**。capability + 主要 trigger + 最重要な境界(競合 skill との差分・上下流関係)に絞り、trigger phrase を description 前半へ置く。オプション詳細・workflow 説明・競合表は SKILL.md 本文または `references/` に残す
- **検証手段**: 各ホストの skill 一覧表示コマンド(Codex なら `codex debug prompt-input` 等)で、対象 skill が初期一覧に残ることを確認する

description の書き方(capability + trigger、how を書かない)そのものは [`skill-description-writing.md`](skill-description-writing.md) を SSOT とする。本ファイルは総量観点の補足。

# fillin public skills

株式会社フィルイン (fillin Inc.) が公開する AI コーディングエージェント向け skill コレクションです。

Claude Code / Codex / GitHub Copilot CLI / Antigravity CLI など、[agentskills.io 仕様](https://agentskills.io/specification) に準拠したホストで利用できます。

## インストール

```bash
gh skill install <owner>/<repo> <name>
```

<!-- TODO: GitHub 上の owner / repo が確定したら実名に置き換える -->

## カテゴリ別 skill 一覧

<!-- TODO: skill を追加したらこの表に 1 行追加する (AGENTS.md「Skill 配置の原則」参照) -->

| skill | 用途 |
|---|---|
| `web-research-report` | Web 調査から出典付きの HTML または Markdown 資料を作成 |

## 開発

```bash
make help      # 利用可能なコマンドを表示
make lint      # shellcheck + frontmatter / license / 括弧ルール 等の検証
make test      # lint スクリプトの単体テスト
make validate  # gh skill publish --dry-run (spec 適合検証)
```

コントリビュートの際は [AGENTS.md](AGENTS.md) を参照してください。設計ガイドラインは [`docs/guidelines/`](docs/guidelines/) にあります。

## ライセンス

MIT License. 詳細は [LICENSE](LICENSE) を参照してください。

各 skill は `skills/<name>/LICENSE` にライセンスを同梱しています。`gh skill install` はファイルコピー配布のため、配布先でも skill 単体でライセンスが確認できます。

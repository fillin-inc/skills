#!/bin/sh
# 公開 skill リポジトリのライセンス同梱規約を検証する。
#
# 検証内容:
#   - リポジトリルートに LICENSE が存在する
#   - 各 skills/<name>/ に LICENSE が同梱されている
#     (gh skill install はファイルコピー配布のため、ルートの LICENSE は配布先に存在しない)
#   - 各 SKILL.md の frontmatter に license フィールドがある
#   - frontmatter の license が MIT の skill は、同梱 LICENSE が MIT License 本文であること
#     (MIT 以外を宣言する skill は本文一致検査の対象外。AGENTS.md「ライセンス方針」参照)
set -eu

errfile=$(mktemp)
trap 'rm -f "$errfile"' EXIT

emit_err() {
  printf '%s\n' "$1" >&2
  printf 'x\n' >> "$errfile"
}

if [ ! -f LICENSE ]; then
  emit_err 'LICENSE: missing at repository root'
fi

[ -d skills ] || { echo "license: ok (no skills/ directory)"; exit 0; }

for file in $(find skills -mindepth 2 -maxdepth 2 -name SKILL.md | sort); do
  dir=$(dirname "$file")

  if [ ! -f "$dir/LICENSE" ]; then
    emit_err "$(printf '%s: missing bundled LICENSE (required by this repository, see AGENTS.md)' "$dir")"
  fi

  # frontmatter (先頭の --- から次の --- まで) から license 行を取り出す
  license=$(awk '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { next }
    /^---[[:space:]]*$/ { exit }
    /^license:[[:space:]]*/ {
      sub(/^license:[[:space:]]*/, "")
      gsub(/^"|"$|^'"'"'|'"'"'$/, "")
      print
      exit
    }
  ' "$file")

  if [ -z "$license" ]; then
    emit_err "$(printf '%s: missing required field: license' "$file")"
    continue
  fi

  if [ "$license" = "MIT" ] && [ -f "$dir/LICENSE" ]; then
    if ! grep -q '^MIT License' "$dir/LICENSE"; then
      emit_err "$(printf '%s/LICENSE: declares license: MIT in SKILL.md but the bundled LICENSE is not the MIT License text' "$dir")"
    fi
  fi
done

if [ -s "$errfile" ]; then
  errors=$(wc -l < "$errfile" | tr -d ' ')
  printf '\n%s error(s) found\n' "$errors" >&2
  exit 1
fi

echo "license: ok"

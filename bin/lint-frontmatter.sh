#!/bin/sh
# SKILL.md の YAML frontmatter を agentskills.io 仕様 (https://agentskills.io/specification) と
# 既存の YAML エスケープ規約に基づいて検証する。
#
# 検証内容:
#   YAML エスケープ:
#     - 値が [ で始まる場合、ダブルクォートで囲まれていることを確認
#     - unquoted な値に ": "（コロン+空白）が含まれていないことを確認
#   agentskills.io 仕様:
#     - name は kebab-case (a-z, 0-9, ハイフン)、1-64 文字、連続/先頭/末尾ハイフン禁止
#     - SKILL.md の親ディレクトリ名 = name field 一致
#     - description は 1-1024 文字
#     - frontmatter フィールドは許可リスト内のみ（仕様外は警告）
#   本体長:
#     - frontmatter を除いた SKILL.md 本文は 500 行以下
#       （gh skill publish の "recommended max: 500 for efficient context" 警告に合わせる）
set -eu

body_line_limit=500

errfile=$(mktemp)
warnfile=$(mktemp)
trap 'rm -f "$errfile" "$warnfile"' EXIT

allowed_fields="name description argument-hint license compatibility metadata allowed-tools model effort"

is_allowed_field() {
  for f in $allowed_fields; do
    if [ "$1" = "$f" ]; then return 0; fi
  done
  return 1
}

strip_quotes() {
  case "$1" in
    '"'*'"') printf '%s' "$1" | sed 's/^"//;s/"$//' ;;
    "'"*"'") printf '%s' "$1" | sed "s/^'//;s/'$//" ;;
    *) printf '%s' "$1" ;;
  esac
}

# stderr に出力しつつ $errfile に追記する。pipeline を避けることで SC2094 を回避。
emit_err() {
  printf '%s\n' "$1" >&2
  printf '%s\n' "$1" >> "$errfile"
}

emit_warn() {
  printf '%s\n' "$1" >&2
  printf '%s\n' "$1" >> "$warnfile"
}

validate_name() {
  _file=$1
  _lineno=$2
  _name=$3
  _len=${#_name}
  if [ "$_len" -lt 1 ] || [ "$_len" -gt 64 ]; then
    emit_err "$(printf '%s:%d: name length must be 1-64 (got %d): %s' \
      "$_file" "$_lineno" "$_len" "$_name")"
    return
  fi
  if ! printf '%s' "$_name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    emit_err "$(printf '%s:%d: name must be kebab-case (lowercase a-z, 0-9, hyphens; no leading/trailing/consecutive hyphens): %s' \
      "$_file" "$_lineno" "$_name")"
  fi
}

# shellcheck disable=SC2094
# SC2094 は pipeline 内で `$file` を read しつつ別の処理が同一 file に write する可能性を
# 検出する。本スクリプトは `$errfile` / `$warnfile` (mktemp 由来の別ファイル) にのみ追記し、
# `$file` への write は一切行わないため誤検知。
find . -name 'SKILL.md' -type f \
  -not -path './.claude/*' \
  -not -path './.agents/*' \
  -not -path './.git/*' \
  -not -path '*/node_modules/*' \
  | while IFS= read -r file; do
  expected_name=$(basename "$(dirname "$file")")
  have_name=0
  have_desc=0
  have_license=0
  in_frontmatter=false
  frontmatter_closed=false
  body_lines=0
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    if [ "$line" = "---" ]; then
      if [ "$in_frontmatter" = true ]; then
        in_frontmatter=false
        frontmatter_closed=true
        continue
      fi
      in_frontmatter=true
      continue
    fi
    if [ "$frontmatter_closed" = true ]; then
      body_lines=$((body_lines + 1))
      continue
    fi
    if [ "$in_frontmatter" = false ]; then
      continue
    fi

    # 既存の YAML エスケープ検証 (key: value 形式の値部分のみ)
    value=$(echo "$line" | sed -n 's/^[a-zA-Z_-]*: *//p')
    case "$value" in
      '"'*|"'"*) ;;
      '['*)
        emit_err "$(printf '%s:%d: unquoted value starting with "[" — wrap in double quotes: %s' \
          "$file" "$lineno" "$value")"
        ;;
      *': '*)
        emit_err "$(printf '%s:%d: unquoted value contains ": " — wrap in double quotes or rephrase: %s' \
          "$file" "$lineno" "$value")"
        ;;
    esac

    # agentskills.io 仕様検証 (key / value の抽出)。
    # 仕様外フィールドの検出漏れを避けるため、key は「非空白・非コロン文字 1 文字以上」で
    # 抽出する。これにより `_custom:` / `1custom:` のような英字以外で始まる仕様外フィールドも
    # allowlist 照合の対象に乗る。
    key=$(printf '%s' "$line" | sed -n 's/^\([^:[:space:]][^:[:space:]]*\):.*/\1/p')
    if [ -z "$key" ]; then
      continue
    fi
    raw_val=$(printf '%s' "$line" | sed 's/^[^:[:space:]][^:[:space:]]*: *//')
    val=$(strip_quotes "$raw_val")

    if ! is_allowed_field "$key"; then
      emit_warn "$(printf '%s:%d: WARN: unknown frontmatter field (not in allowlist): %s' \
        "$file" "$lineno" "$key")"
      continue
    fi

    case "$key" in
      name)
        have_name=1
        validate_name "$file" "$lineno" "$val"
        if [ "$val" != "$expected_name" ]; then
          emit_err "$(printf '%s:%d: name "%s" must match parent directory name "%s"' \
            "$file" "$lineno" "$val" "$expected_name")"
        fi
        ;;
      description)
        have_desc=1
        # YAML のブロックスカラー (`|`, `>`, `|-`, `>+` 等) は単一行リーダーで
        # 値を捕まえられないため、後続のインデント行を含めた実長検証ができない。
        # description 文字数ゲートを正しく機能させるため、ブロックスカラー記法は
        # 仕様逸脱として fail させる（agentskills.io 仕様の description は単一の
        # string で、現行 skill もすべて単一行記法で書かれている）。
        case "$raw_val" in
          '|'*|'>'*)
            emit_err "$(printf '%s:%d: description must be a single-line scalar (YAML block scalar (pipe or folded) is not supported by this linter)' \
              "$file" "$lineno")"
            ;;
          *)
            # ${#val} は locale 依存（LANG=*.UTF-8 では char、LANG=C では byte）で
            # ローカルと CI で異なる結果になる事故が発生した（local 989 char OK / CI
            # 1055 byte FAIL）。byte で揃えれば deterministic に判定できるため、
            # `wc -c` でバイト長を取り byte 1-1024 の境界を一律に適用する。
            dlen=$(printf '%s' "$val" | wc -c | tr -d ' ')
            if [ "$dlen" -lt 1 ] || [ "$dlen" -gt 1024 ]; then
              emit_err "$(printf '%s:%d: description length must be 1-1024 bytes (got %d)' \
                "$file" "$lineno" "$dlen")"
            fi
            ;;
        esac
        ;;
      license)
        # license は agentskills.io 仕様では optional だが、本リポジトリでは
        # AGENTS.md の方針により各 skill で個別定義を必須としている。
        # 値が非空であることだけ確認する（フォーマットは自由）。
        have_license=1
        if [ -z "$val" ]; then
          emit_err "$(printf '%s:%d: license must be non-empty' \
            "$file" "$lineno")"
        fi
        ;;
    esac
  done < "$file"

  if [ "$have_name" -eq 0 ]; then
    emit_err "$(printf '%s: missing required field: name' "$file")"
  fi
  if [ "$have_desc" -eq 0 ]; then
    emit_err "$(printf '%s: missing required field: description' "$file")"
  fi
  if [ "$have_license" -eq 0 ]; then
    emit_err "$(printf '%s: missing required field: license (required by this repository, see AGENTS.md)' "$file")"
  fi
  if [ "$body_lines" -gt "$body_line_limit" ]; then
    emit_err "$(printf '%s: SKILL.md body is %d lines (max: %d). Move details into references/ files.' \
      "$file" "$body_lines" "$body_line_limit")"
  fi
done

if [ -s "$warnfile" ]; then
  warns=$(wc -l < "$warnfile" | tr -d ' ')
  printf '\n%s warning(s) found\n' "$warns" >&2
fi

if [ -s "$errfile" ]; then
  errors=$(wc -l < "$errfile" | tr -d ' ')
  printf '\n%s error(s) found\n' "$errors" >&2
  exit 1
fi

echo "frontmatter: ok"

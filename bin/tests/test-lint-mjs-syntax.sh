#!/bin/bash
# bin/lint-mjs-syntax.sh のユニットテスト。
# mktemp -d の sandbox に疑似 skills/ と bin/ を組み立て、構文検証の判定を検証する。
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
LINT="$REPO_ROOT/bin/lint-mjs-syntax.sh"

pass=0
fail=0
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# 引数は "<path>=<content>" の形
make_sandbox() {
    rm -rf "${SANDBOX:?}/skills" "${SANDBOX:?}/bin"
    for spec in "$@"; do
        f=${spec%%=*}
        mkdir -p "$SANDBOX/$(dirname "$f")"
        printf '%s\n' "${spec#*=}" > "$SANDBOX/$f"
    done
}

expect_lint() {
    desc="$1"; want="$2"; shift 2
    make_sandbox "$@"
    if sh "$LINT" "$SANDBOX" >/dev/null 2>&1; then got=0; else got=1; fi
    if [ "$got" = "$want" ]; then
        pass=$((pass + 1)); echo "  ok   - $desc"
    else
        fail=$((fail + 1)); echo "  FAIL - $desc (want exit $want, got $got)"
    fi
}

echo "# test-lint-mjs-syntax"

expect_lint "正しい .mjs と .js は pass" 0 \
    "skills/a/scripts/x.mjs=import { readFileSync } from 'node:fs'; export const f = () => readFileSync;" \
    "skills/a/scripts/y.js=const fs = require('node:fs'); module.exports = fs;" \
    "bin/z.mjs=#!/usr/bin/env node
console.log('ok');"

expect_lint "Node.js script が無ければ pass" 0 "skills/a/SKILL.md=# a"

expect_lint "skills/ の構文エラーは fail" 1 "skills/a/scripts/x.mjs=export const f = (;"
expect_lint "bin/ の構文エラーは fail" 1 "bin/x.mjs=function ("
expect_lint "node_modules/ 配下は対象外" 0 "skills/a/scripts/node_modules/p/i.js=function ("
expect_lint "fixtures/ 配下は対象外" 0 "skills/a/scripts/tests/fixtures/broken.mjs=function ("

echo "# pass=$pass fail=$fail"
[ "$fail" -eq 0 ]

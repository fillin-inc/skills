#!/bin/bash
# bin/lint-skill-tests.sh / bin/list-skill-tests.sh のユニットテスト。
# mktemp -d の sandbox に疑似 skills/ を組み立て、配置規則の判定を検証する。
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
LINT="$REPO_ROOT/bin/lint-skill-tests.sh"
LIST="$REPO_ROOT/bin/list-skill-tests.sh"

pass=0
fail=0
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

make_sandbox() {
    rm -rf "${SANDBOX:?}/skills"
    mkdir -p "$SANDBOX/skills"
    for f in "$@"; do
        mkdir -p "$SANDBOX/$(dirname "$f")"
        : > "$SANDBOX/$f"
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

echo "# test-lint-skill-tests"

expect_lint "許可された配置はすべて pass" 0 \
    skills/a/SKILL.md skills/b/SKILL.md \
    skills/a/scripts/tests/test-x.sh \
    skills/a/scripts/tests/test-y.mjs \
    skills/a/scripts/tests/z.test.mjs \
    skills/b/scripts/w.test.mjs

expect_lint "テストが無ければ pass" 0 skills/a/SKILL.md
expect_lint "group 配下の skill の許可された配置は pass" 0 \
    skills/g/c/SKILL.md \
    skills/g/c/scripts/tests/test-x.sh \
    skills/g/c/scripts/w.test.mjs
expect_lint "SKILL.md の無いディレクトリのテストは fail" 1 skills/a/scripts/tests/test-x.sh
expect_lint "skill の下の SKILL.md を持つディレクトリのテストは fail" 1 \
    skills/a/SKILL.md skills/a/tpl/SKILL.md \
    skills/a/tpl/scripts/tests/test-x.sh
expect_lint "group の入れ子の skill のテストは fail" 1 \
    skills/g/h/c/SKILL.md \
    skills/g/h/c/scripts/tests/test-x.sh

expect_lint "skill 直下の tests/ は fail" 1 skills/a/tests/test-x.sh
expect_lint "scripts/ 直下の test-*.sh は fail" 1 skills/a/scripts/test-x.sh
expect_lint "入れ子の tests/ は fail" 1 skills/a/scripts/sub/tests/test-x.sh
expect_lint "*.test.js は fail" 1 skills/a/scripts/x.test.js
expect_lint "*.bats は fail" 1 skills/a/scripts/tests/x.bats
expect_lint "node_modules 配下は対象外" 0 skills/a/scripts/node_modules/pkg/test-x.js
expect_lint "fixtures 配下は対象外" 0 skills/a/scripts/tests/fixtures/test-x.sh

# bin/tests の対応表(test-map.tsv)の検査
expect_map() {
    desc="$1"; want="$2"; map="$3"; shift 3
    make_sandbox skills/a/SKILL.md skills/a/sub/SKILL.md skills/g/d/SKILL.md
    rm -rf "${SANDBOX:?}/bin"
    mkdir -p "$SANDBOX/bin/tests"
    for f in "$@"; do : > "$SANDBOX/bin/tests/$f"; done
    printf '%b' "$map" > "$SANDBOX/bin/tests/test-map.tsv"
    if sh "$LINT" "$SANDBOX" >/dev/null 2>&1; then got=0; else got=1; fi
    if [ "$got" = "$want" ]; then
        pass=$((pass + 1)); echo "  ok   - $desc"
    else
        fail=$((fail + 1)); echo "  FAIL - $desc (want exit $want, got $got)"
    fi
}

expect_map "対応表に全テストがあれば pass" 0 'bin/tests/test-x.sh\ta\nbin/tests/test-y.mjs\t-\n' test-x.sh test-y.mjs
expect_map "対応表に無い bin/tests は fail" 1 'bin/tests/test-x.sh\ta\n' test-x.sh test-y.sh
expect_map "対応表にあってファイルが無い行は fail" 1 'bin/tests/test-x.sh\ta\nbin/tests/test-gone.sh\t-\n' test-x.sh
expect_map "存在しない skill を指す行は fail" 1 'bin/tests/test-x.sh\tnope\n' test-x.sh
expect_map "group 配下の skill を指す行は pass" 0 'bin/tests/test-x.sh\td\n' test-x.sh
expect_map "group 名を skill として指す行は fail" 1 'bin/tests/test-x.sh\tg\n' test-x.sh
expect_map "skill の下のディレクトリ名を skill として指す行は fail" 1 'bin/tests/test-x.sh\tsub\n' test-x.sh
expect_map "コメント行は無視する" 0 '# header\nbin/tests/test-x.sh\ta,a\n' test-x.sh

make_sandbox skills/a/SKILL.md skills/b/SKILL.md skills/g/c/SKILL.md \
    skills/a/scripts/tests/test-x.sh skills/b/scripts/w.test.mjs skills/a/README.md \
    skills/g/c/scripts/tests/test-y.sh
got=$(sh "$LIST" "$SANDBOX" | tr '\n' ' ')
want="skills/a/scripts/tests/test-x.sh skills/b/scripts/w.test.mjs skills/g/c/scripts/tests/test-y.sh "
if [ "$got" = "$want" ]; then
    pass=$((pass + 1)); echo "  ok   - list-skill-tests は許可された配置だけを辞書順で出す"
else
    fail=$((fail + 1)); echo "  FAIL - list-skill-tests (got '$got')"
fi

echo
echo "passed: $pass / failed: $fail"
[ "$fail" -eq 0 ]

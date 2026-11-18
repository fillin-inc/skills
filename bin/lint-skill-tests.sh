#!/bin/sh
# skills/ 配下のテストファイルが、すべて make test で実行される場所にあるかを検証する。
#
# make test は bin/list-skill-tests.sh が列挙したテストだけを実行する。
# それ以外の場所に置いたテストは CI で回らず、壊れても検知されないため fail にする。
#
# テストファイルとみなす名前: test-*.sh / test-*.mjs / test-*.js / *.test.mjs /
#   *.test.js / *.spec.mjs / *.spec.js / *_test.sh / *.bats
# 除外: node_modules/ と fixtures/ 配下(テスト入力として置かれたファイル)
#
# あわせて、bin/tests のテストがすべて bin/tests/test-map.tsv(skill との対応表)に載っているかを検証する。
# 表に無いテストは make test SKILLS=<name> の絞り込みで漏れるため fail にする。
# 表にあってファイルが無い行、skills/ に無い skill 名を指す行も fail にする。
#
# 使い方: sh ./bin/lint-skill-tests.sh [<repo-root>]

set -eu

ROOT="${1:-.}"
HERE=$(cd "$(dirname "$0")" && pwd)

cd "$ROOT"
[ -d skills ] || { echo "lint-skill-tests: PASS (skills/ なし)"; exit 0; }

allowed=$(sh "$HERE/list-skill-tests.sh" .)

found=$(find skills -type f \
    \( -name 'test-*.sh' -o -name 'test-*.mjs' -o -name 'test-*.js' \
       -o -name '*.test.mjs' -o -name '*.test.js' \
       -o -name '*.spec.mjs' -o -name '*.spec.js' \
       -o -name '*_test.sh' -o -name '*.bats' \) \
    -not -path '*/node_modules/*' -not -path '*/fixtures/*' | sort)

count=0
bad=0
for f in $found; do
    count=$((count + 1))
    if ! printf '%s\n' "$allowed" | grep -qxF "$f"; then
        echo "lint-skill-tests: $f は make test で実行されない場所にあります" >&2
        bad=$((bad + 1))
    fi
done

map_bad=0
MAP=bin/tests/test-map.tsv
if [ -d bin/tests ]; then
    if [ ! -f "$MAP" ]; then
        echo "lint-skill-tests: $MAP がありません" >&2
        map_bad=$((map_bad + 1))
    else
        TAB=$(printf '\t')
        for f in bin/tests/test-*.sh bin/tests/test-*.mjs; do
            [ -f "$f" ] || continue
            if ! grep -q "^$f$TAB" "$MAP"; then
                echo "lint-skill-tests: $f が $MAP にありません(skill に紐付かないなら SKILLS 列を - にする)" >&2
                map_bad=$((map_bad + 1))
            fi
        done
        while IFS="$TAB" read -r t skills _; do
            case "$t" in ''|'#'*) continue ;; esac
            if [ ! -f "$t" ]; then
                echo "lint-skill-tests: $MAP の $t が存在しません" >&2
                map_bad=$((map_bad + 1))
            fi
            [ "$skills" = "-" ] && continue
            old_ifs=$IFS
            IFS=,
            for s in $skills; do
                found_skill=0
                [ -f "skills/$s/SKILL.md" ] && found_skill=1
                for g in skills/*/; do
                    # SKILL.md を持つディレクトリは skill で、group ではない
                    [ -f "${g}SKILL.md" ] && continue
                    [ -f "$g$s/SKILL.md" ] && found_skill=1
                done
                if [ "$found_skill" -eq 0 ]; then
                    echo "lint-skill-tests: $MAP の $t が存在しない skill $s を指しています" >&2
                    map_bad=$((map_bad + 1))
                fi
            done
            IFS=$old_ifs
        done < "$MAP"
    fi
fi

if [ "$bad" -gt 0 ] || [ "$map_bad" -gt 0 ]; then
    if [ "$bad" -gt 0 ]; then
        echo "skill 同梱テストは <skill>/scripts/tests/(test-*.sh / test-*.mjs / *.test.mjs)か <skill>/scripts/*.test.mjs に置いてください(<skill> は skills/<name> か skills/<group>/<name>)" >&2
    fi
    echo "lint-skill-tests: FAIL ($bad / $count files, test-map $map_bad errors)" >&2
    exit 1
fi
echo "lint-skill-tests: PASS ($count files checked)"

#!/usr/bin/env node
// bin/run-tests.mjs のユニットテスト。
// mkdtemp の sandbox に疑似リポジトリを組み立て、--root で runner を向けて検証する。

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const RUNNER = path.resolve(HERE, "..", "run-tests.mjs");
const SANDBOX = mkdtempSync(path.join(os.tmpdir(), "run-tests-"));
process.on("exit", () => rmSync(SANDBOX, { recursive: true, force: true }));

let pass = 0;
let fail = 0;

function write(root, rel, content = "") {
  const p = path.join(root, rel);
  mkdirSync(path.dirname(p), { recursive: true });
  writeFileSync(p, content);
  chmodSync(p, 0o755);
}

let seq = 0;
function makeRepo(files) {
  const root = path.join(SANDBOX, `repo${seq++}`);
  for (const dir of ["a", "b", "c", "g/d"]) write(root, `skills/${dir}/SKILL.md`, "# skill\n");
  for (const [rel, content] of Object.entries(files)) write(root, rel, content);
  return root;
}

function run(root, args = [], env = {}) {
  const r = spawnSync("node", [RUNNER, "--root", root, ...args], {
    encoding: "utf8",
    env: { ...process.env, JOBS: "", ...env },
  });
  return { code: r.status, out: r.stdout, err: r.stderr };
}

function check(desc, fn) {
  try {
    fn();
    pass++;
    console.log(`  ok   - ${desc}`);
  } catch (e) {
    fail++;
    console.log(`  FAIL - ${desc}\n${e.message}`);
  }
}

const OK = "#!/bin/bash\necho hello-$0\nexit 0\n";
const NG = "#!/bin/bash\necho failing-output-$0\necho err-line >&2\nexit 3\n";

console.log("# test-run-tests");


const full = {
  "bin/tests/test-one.sh": OK,
  "bin/tests/test-two.mjs": "console.log('two');\n",
  "bin/tests/test-map.tsv":
    "# header\nbin/tests/test-one.sh\ta\nbin/tests/test-two.mjs\tb,c\n",
  "skills/a/scripts/tests/test-a.sh": OK,
  "skills/b/scripts/tests/test-b.sh": OK,
  "skills/c/scripts/tests/z.test.mjs":
    "import { test } from 'node:test';\ntest('x', () => {});\n",
};

check("全件を実行して 0 で終わる", () => {
  const r = run(makeRepo(full));
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /PASS \(5 files/);
  assert.match(r.out, /==> bin\/tests\/test-one\.sh \[ok/);
});

check("失敗が 1 件でもあれば 1 で終わり、失敗一覧と出力を出す", () => {
  const r = run(makeRepo({ ...full, "bin/tests/test-bad.sh": NG, "bin/tests/test-map.tsv": full["bin/tests/test-map.tsv"] + "bin/tests/test-bad.sh\t-\n" }));
  assert.equal(r.code, 1);
  assert.match(r.out, /FAIL \(1 \/ 6 files/);
  assert.match(r.out, /failing-output-/);
  assert.match(r.out, /err-line/);
  assert.match(r.out, /bin\/tests\/test-bad\.sh \(exit 3\)/);
});

check("失敗したテストの出力は 1 ブロックにまとまり、並列でも混ざらない", () => {
  const slow = (n) =>
    `#!/bin/bash\nfor i in 1 2 3; do echo ${n}-$i; sleep 0.05; done\nexit 1\n`;
  const files = { ...full };
  let map = full["bin/tests/test-map.tsv"];
  for (const n of ["p", "q", "r", "s"]) {
    files[`bin/tests/test-${n}.sh`] = slow(n);
    map += `bin/tests/test-${n}.sh\t-\n`;
  }
  files["bin/tests/test-map.tsv"] = map;
  const r = run(makeRepo(files), ["--jobs", "4"]);
  assert.equal(r.code, 1);
  for (const n of ["p", "q", "r", "s"]) {
    assert.ok(r.out.includes(`${n}-1\n${n}-2\n${n}-3\n`), `${n} の出力が連続していない:\n${r.out}`);
  }
});

check("--jobs 1 は逐次実行する", () => {
  const r = run(makeRepo(full), ["--jobs", "1"]);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /jobs=1\b/);
});

check("JOBS 環境変数で同時実行数を上書きする", () => {
  const r = run(makeRepo(full), [], { JOBS: "2" });
  assert.match(r.out, /jobs=2\b/);
});

check("JOBS が不正なら 2 で終わる", () => {
  const r = run(makeRepo(full), [], { JOBS: "abc" });
  assert.equal(r.code, 2);
});

check("--skills は同梱テストと対応表の bin/tests だけを選ぶ", () => {
  const r = run(makeRepo(full), ["--skills", "a", "--list"]);
  assert.equal(r.out, "bin/tests/test-one.sh\nskills/a/scripts/tests/test-a.sh\n");
});

check("--skills は対応表で複数の skill に紐付いたテストを各 skill で選ぶ", () => {
  const forC = run(makeRepo(full), ["--skills", "c", "--list"]);
  assert.equal(forC.out, "bin/tests/test-two.mjs\nskills/c/scripts/tests/z.test.mjs\n");
  const forB = run(makeRepo(full), ["--skills", "b", "--list"]);
  assert.equal(forB.out, "bin/tests/test-two.mjs\nskills/b/scripts/tests/test-b.sh\n");
});

check("--skills は group 配下の skill の同梱テストと対応表にも効く", () => {
  const files = {
    ...full,
    "bin/tests/test-map.tsv": full["bin/tests/test-map.tsv"] + "bin/tests/test-three.sh\td\n",
    "bin/tests/test-three.sh": OK,
    "skills/g/d/scripts/tests/test-d.sh": OK,
  };
  const r = run(makeRepo(files), ["--skills", "d", "--list"]);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(r.out, "bin/tests/test-three.sh\nskills/g/d/scripts/tests/test-d.sh\n");
});

check("--skills に group 名を渡すと存在しない skill として 2 で終わる", () => {
  const r = run(makeRepo(full), ["--skills", "g"]);
  assert.equal(r.code, 2);
  assert.match(r.err, /存在しない skill: g/);
});

check("--skills はカンマと空白の区切りを受ける", () => {
  const r = run(makeRepo(full), ["--skills", "a, b", "--list"]);
  assert.match(r.out, /test-a\.sh/);
  assert.match(r.out, /test-b\.sh/);
});

check("--skills に存在しない skill を渡すと 2 で終わる", () => {
  const r = run(makeRepo(full), ["--skills", "nope"]);
  assert.equal(r.code, 2);
  assert.match(r.err, /nope/);
});

check("--skills を実行すると選んだテストだけ流れる", () => {
  const r = run(makeRepo(full), ["--skills", "a"]);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /PASS \(2 files/);
  assert.doesNotMatch(r.out, /test-b\.sh/);
});

check("対応表に無い bin/tests は絞り込みで実行せず警告する", () => {
  const r = run(makeRepo({ ...full, "bin/tests/test-new.sh": OK }), ["--skills", "a", "--list"]);
  assert.doesNotMatch(r.out, /test-new\.sh/);
  assert.match(r.err, /test-new\.sh/);
});

check("--quiet は成功したテストの出力を省く", () => {
  const r = run(makeRepo(full), ["--quiet"]);
  assert.doesNotMatch(r.out, /hello-/);
  const v = run(makeRepo(full));
  assert.match(v.out, /hello-/);
});

check("対象が 0 件なら 0 で終わる", () => {
  const r = run(makeRepo({}));
  assert.equal(r.code, 0);
});

check("所要時間の上位を出す", () => {
  const r = run(makeRepo(full));
  assert.match(r.out, /slowest/);
});

console.log(`\npassed: ${pass} / failed: ${fail}`);
process.exitCode = fail === 0 ? 0 : 1;

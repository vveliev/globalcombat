// Run: node --test scripts/check-internal-refs.test.mjs
// Each case builds a throwaway git repo so the scan is exercised the way CI and
// the pre-push hook call it, not by feeding the regexes strings directly.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { scanRange, scan, addedLines, resolveRange } from "./check-internal-refs.mjs";

function repo() {
  const dir = mkdtempSync(join(tmpdir(), "internal-refs-"));
  const g = (...args) =>
    execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@users.noreply.github.com", ...args], {
      cwd: dir,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  g("init", "-q", "-b", "main");
  const write = (name, body) => {
    mkdirSync(join(dir, name, ".."), { recursive: true });
    writeFileSync(join(dir, name), body);
  };
  const commit = (msg) => {
    g("add", "-A");
    g("commit", "-q", "-m", msg);
    return g("rev-parse", "HEAD");
  };
  return { dir, g, write, commit };
}

// scanRange shells out to git in process.cwd(); point it at the temp repo.
function inRepo(dir, fn) {
  const prev = process.cwd();
  process.chdir(dir);
  try {
    return fn();
  } finally {
    process.chdir(prev);
  }
}

const ids = (findings) => findings.map((f) => `${f.id}@${f.where}`).sort();

// Fixtures are assembled at runtime: written literally, the very shapes this
// scanner refuses would fail the gate on this file.
const tid = (prefix, n) => `${prefix}-${n}`;
const mail = (user, ...domain) => `${user}@${domain.join(".")}`;
const uuid = (...parts) => parts.join("-");

test("a renamed-and-edited file is scanned (rename detection kept)", () => {
  const r = repo();
  r.write("big.txt", "line one\nline two\nline three\nline four\nline five\n");
  const base = r.commit("base");
  r.g("mv", "big.txt", "big2.txt");
  r.write("big2.txt", `line one\nline two\nline three\nline four\nline five\nsee ${tid("GIF", 4)}\n`);
  r.commit("rename and edit");
  const { findings } = inRepo(r.dir, () => scanRange(`${base}..HEAD`));
  assert.deepEqual(ids(findings), ["tracker-id@big2.txt:6"]);
});

test("an added line starting with ++ is scanned and does not desync the line counter", () => {
  const r = repo();
  r.write("f.c", "a\n");
  const base = r.commit("base");
  r.write("f.c", `a\n++i;\n${tid("GIF", 1)}\n`);
  r.commit("edit");
  const { findings } = inRepo(r.dir, () => scanRange(`${base}..HEAD`));
  assert.deepEqual(ids(findings), ["tracker-id@f.c:3"]);
});

test("diff.noprefix in the user's config does not blind the scan", () => {
  const r = repo();
  r.g("config", "diff.noprefix", "true");
  r.write("f.c", "a\n");
  const base = r.commit("base");
  r.write("f.c", `a\n${tid("GIF", 3)}\n`);
  r.commit("edit");
  const { findings } = inRepo(r.dir, () => scanRange(`${base}..HEAD`));
  assert.deepEqual(ids(findings), ["tracker-id@f.c:2"]);
});

test("a touched file's pre-existing references are not re-flagged; only added lines count", () => {
  const r = repo();
  r.write("doc.md", `legacy ${tid("GIF", 1)} stays\n`);
  const base = r.commit("base");
  r.write("doc.md", `legacy ${tid("GIF", 1)} stays\nnew clean line\n`);
  r.commit("touch");
  const { findings } = inRepo(r.dir, () => scanRange(`${base}..HEAD`));
  assert.deepEqual(findings, []);
});

test("commit messages and author identities in the range are scanned in full", () => {
  const r = repo();
  r.write("f", "x\n");
  const base = r.commit("base");
  r.write("f", "y\n");
  r.commit(`fix thing\n\nCo-authored-by: Chief of Staff (Black Inc ${"agent"}) <${mail("agent", "example", "internal")}>`);
  const { findings } = inRepo(r.dir, () => scanRange(`${base}..HEAD`));
  assert.deepEqual(new Set(findings.map((f) => f.id)), new Set(["agent-trailer", "internal-email"]));
});

test("the branch name is scanned by name, not from the checked-out HEAD", () => {
  const r = repo();
  r.write("f", "x\n");
  const base = r.commit("base");
  r.write("f", "y\n");
  r.commit("clean");
  const { findings } = inRepo(r.dir, () => scanRange(`${base}..HEAD`, { branch: `work/${tid("GIF", 9)}-thing` }));
  assert.deepEqual(ids(findings), ["tracker-id@branch name:1"]);
  const uuidBranch = inRepo(r.dir, () =>
    scanRange(`${base}..HEAD`, { branch: `work/${uuid("8df7af72", "c192", "426b", "a612", "ab23ca4bbdc9")}` }),
  );
  assert.deepEqual(uuidBranch.findings, [], "the UUID rule does not apply to branch names");
});

test("an unreachable or all-zero base falls back to the merge-base with the fallback ref, then root", () => {
  const r = repo();
  r.write("f", "x\n");
  r.commit(`root with ${tid("GIF", 0)} in message`);
  r.write("f", "y\n");
  const mainTip = r.commit("main tip");
  r.g("checkout", "-q", "-b", "feature");
  r.write("f", "z\n");
  const tip = r.commit("feature commit");
  inRepo(r.dir, () => {
    assert.deepEqual(resolveRange(`${"0".repeat(40)}..HEAD`, "main"), { from: mainTip, to: tip });
    assert.deepEqual(resolveRange(`deadbeefdeadbeefdeadbeefdeadbeefdeadbeef..HEAD`, "main"), { from: mainTip, to: tip });
    // No fallback ref at all: the whole history is being published, so the root
    // commit's own message (and every file line) is scanned too.
    const { findings } = scanRange(`${"0".repeat(40)}..HEAD`);
    assert.deepEqual(findings.map((f) => [f.id, f.match, f.where.split(":")[0]]), [["tracker-id", tid("GIF", 0), "commit messages"]]);
    assert.deepEqual(addedLines(resolveRange(`${"0".repeat(40)}..HEAD`)).map((l) => `${l.file}:${l.line}`), ["f:1"]);
    // With the fallback the first-push case is clean, as it should be.
    assert.deepEqual(scanRange(`${"0".repeat(40)}..HEAD`, { fallback: "main" }).findings, []);
  });
});

test("regex reach: subdomains, uppercase UUIDs, ADR numbering and protocol names", () => {
  const f = [];
  scan(`mail ${mail("x", "sub", "example", "internal")} and y@users.noreply.github.com`, "t", f);
  assert.deepEqual(f.map((x) => x.match), [mail("x", "sub", "example", "internal")]);
  const u = [];
  scan(`id ${uuid("8DF7AF72", "C192", "426B", "A612", "AB23CA4BBDC9")}`, "t", u);
  assert.equal(u[0]?.id, "instance-uuid");
  const ok = [];
  scan("ADR-0001, GPT-4, TLS-1, SHA-256, RFC-2119, PROJ-12", "t", ok);
  assert.deepEqual(ok, []);
  const bad = [];
  scan(`see ${tid("GIF", 118)} and ${tid("BLA", 7)}`, "t", bad);
  assert.deepEqual(bad.map((x) => x.match), [tid("GIF", 118), tid("BLA", 7)]);
});

test("addedLines skips vendored paths", () => {
  const r = repo();
  r.write("keep", "x\n");
  const base = r.commit("base");
  r.write("node_modules/x/LICENSE", `${tid("GIF", 1)}\n`);
  r.write("dist/app.js", `${tid("GIF", 2)}\n`);
  r.write("keep", `x\n${tid("GIF", 3)}\n`);
  r.commit("vendored");
  const lines = inRepo(r.dir, () => addedLines(resolveRange(`${base}..HEAD`)));
  assert.deepEqual(lines.map((l) => l.file), ["keep"]);
});

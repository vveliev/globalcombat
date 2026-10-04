// Run: node --test scripts/check-internal-refs.test.mjs
// Each case builds a throwaway git repo so the scan is exercised the way CI and
// the pre-push hook call it, not by feeding the regexes strings directly.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, mkdirSync, readFileSync, symlinkSync, copyFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { scanRange, scan, addedLines, resolveRange, parsePatch, UNPARSED_PATH } from "./check-internal-refs.mjs";

const here = dirname(fileURLToPath(import.meta.url));

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
const host = (...labels) => labels.join(".");

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
    // Every commit's own added lines, the root's included.
    assert.deepEqual(addedLines(resolveRange(`${"0".repeat(40)}..HEAD`)).map((l) => `${l.file}:${l.line}`), ["f:1", "f:1", "f:1"]);
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

test("an id added by one commit and removed by a later one in the same push is still caught", () => {
  const r = repo();
  r.write("f", "x\n");
  const base = r.commit("base");
  r.write("f", `x\n${tid("GIF", 5)}\n`);
  const leaky = r.commit("add");
  r.write("f", "x\n");
  r.commit("remove again");
  const { findings } = inRepo(r.dir, () => scanRange(`${base}..HEAD`));
  assert.deepEqual(ids(findings), ["tracker-id@f:2"]);
  assert.equal(findings[0].commit, leaky.slice(0, 12));
});

test("a merge's own new lines are scanned; what its parents brought in is not re-flagged", () => {
  const r = repo();
  r.write("a", "a\n");
  r.write("b", "b\n");
  const base = r.commit("base");
  r.g("checkout", "-q", "-b", "side");
  r.write("a", "a\nside\n");
  r.commit("side");
  r.g("checkout", "-q", "main");
  r.write("b", `b\nmain ${tid("GIF", 12)}\n`);
  const mainTip = r.commit("main");
  r.g("merge", "-q", "--no-ff", "--no-edit", "side");
  r.write("c", `evil ${tid("GIF", 6)}\n`);
  r.g("add", "c");
  r.g("commit", "-q", "--amend", "--no-edit");
  // main's own line is main's finding; the merge adds only c.
  const { findings } = inRepo(r.dir, () => scanRange(`${mainTip}..HEAD`));
  assert.deepEqual(ids(findings), ["tracker-id@c:1"]);
  const all = inRepo(r.dir, () => scanRange(`${base}..HEAD`));
  assert.deepEqual(ids(all.findings), ["tracker-id@b:2", "tracker-id@c:1"]);
});

test("non-ASCII and escaped file names are parsed, never dropped", () => {
  const r = repo();
  r.write("keep", "x\n");
  const base = r.commit("base");
  r.write("café.md", `${tid("GIF", 7)}\n`);
  r.write("tab\there.md", `${tid("GIF", 8)}\n`);
  r.commit("odd names");
  const { findings } = inRepo(r.dir, () => scanRange(`${base}..HEAD`));
  assert.deepEqual(ids(findings), ["tracker-id@café.md:1", "tracker-id@tab\there.md:1"]);
  // A header the parser cannot read still has its lines scanned (fail closed),
  // and an unknown path is never mistaken for a skipped vendored one.
  const sha = "a".repeat(40);
  const odd = parsePatch(`\x01${sha}\n\ndiff --git x y\n+++ ???\n@@ -0,0 +1 @@\n+${tid("GIF", 9)}\n`);
  assert.deepEqual(odd.map((l) => [l.file, l.line, l.text]), [["???", 1, tid("GIF", 9)]]);
  const headerless = parsePatch(`\x01${sha}\n\ndiff --git x y\n@@ -0,0 +1 @@\n+${tid("GIF", 9)}\n`);
  assert.deepEqual(headerless.map((l) => l.file), [UNPARSED_PATH]);
});

test("a rewritten branch whose old tip is gone scans the pushed commits, not an empty range", () => {
  const r = repo();
  r.write("f", "x\n");
  const old = r.commit("base");
  // Rewrite history (as a force push does) and add an id in the new commits.
  r.g("checkout", "-q", "--orphan", "rewritten");
  r.write("f", `x\n${tid("GIF", 10)}\n`);
  const tip = r.commit("rewritten history");
  // CI's clone after the push: the pushed ref already points at the new tip,
  // origin/HEAD follows it, and another branch still has the old history.
  r.g("update-ref", "refs/remotes/origin/main", tip);
  r.g("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main");
  r.g("update-ref", "refs/remotes/origin/feature", old);
  const gone = "deadbeef".repeat(5);
  inRepo(r.dir, () => {
    // The old fallback: the merge-base with origin/main is the tip itself.
    assert.deepEqual(scanRange(`${gone}..HEAD`, { fallback: "origin/main" }).findings, []);
    const { findings } = scanRange(`${gone}..HEAD`, { publishedRemote: "origin", branch: "main" });
    assert.deepEqual(ids(findings), ["tracker-id@f:2"]);
    // Without a branch name, refs whose tip IS the pushed commit are distrusted.
    assert.deepEqual(ids(scanRange(`${gone}..HEAD`, { publishedRemote: "origin" }).findings), ["tracker-id@f:2"]);
  });
});

test("published-remote does not re-flag history for a branch cut from, or reset onto, main", () => {
  const r = repo();
  r.write("f", "x\n");
  r.commit(`legacy ${tid("GIF", 11)} message`);
  r.write("f", "y\n");
  const mainTip = r.commit("main tip");
  r.g("update-ref", "refs/remotes/origin/main", mainTip);
  r.g("update-ref", "refs/remotes/origin/topic", mainTip);
  inRepo(r.dir, () => {
    // A new branch (all-zero base) and a reset-onto-main force push alike.
    for (const a of ["0".repeat(40), "deadbeef".repeat(5)]) {
      assert.deepEqual(scanRange(`${a}..HEAD`, { publishedRemote: "origin", branch: "topic" }).findings, [], a);
    }
  });
});

test("the committer identity is scanned as well as the author", () => {
  const r = repo();
  r.write("f", "x\n");
  const base = r.commit("base");
  r.write("f", "y\n");
  r.g("add", "-A");
  r.g("-c", `user.email=${mail("bot", "corp", "internal")}`, "commit", "-q", "--author", "t <t@users.noreply.github.com>", "-m", "clean");
  const { findings } = inRepo(r.dir, () => scanRange(`${base}..HEAD`));
  assert.deepEqual(findings.map((f) => [f.id, f.match]), [["internal-email", mail("bot", "corp", "internal")]]);
});

test("lower-case tracker ids are caught where references sit, not in ordinary code", () => {
  const lower = tid("gif", 124);
  const found = (text) => {
    const f = [];
    scan(text, "t", f);
    return f.map((x) => x.match);
  };
  assert.deepEqual(found(`fix/${lower}`), [lower]);
  assert.deepEqual(found(`${lower}-polish`), [lower]);
  assert.deepEqual(found(`Merge branch '${lower}-x' into main`), [lower]);
  assert.deepEqual(found(`Merge pull request #3 from someone/${tid("Gif", 7)}-x`), [tid("Gif", 7)]);
  assert.deepEqual(found(`see https://tracker.example/browse/${lower}`), [lower]);
  // Tailwind classes, plan-style branch names, word-ids mid-branch, ADR files.
  assert.deepEqual(found(`<div class="mt-2 px-4 space-y-2 text-red-6 grid-cols-3">`), []);
  assert.deepEqual(found("mobile/task-1-stage"), []);
  assert.deepEqual(found("work/p2-finished-game-as-place-1-engine owner-6"), []);
  assert.deepEqual(found("docs/adr-0001-thing.md utf-8 sha-256"), []);
  // And through scanRange, for a real branch name.
  const r = repo();
  r.write("f", "x\n");
  const base = r.commit("base");
  r.write("f", "y\n");
  r.commit("clean");
  const { findings } = inRepo(r.dir, () => scanRange(`${base}..HEAD`, { branch: `fix/${lower}` }));
  assert.deepEqual(ids(findings), ["tracker-id@branch name:1"]);
});

test("internal hostnames are caught; identifiers, localhost and public names are not", () => {
  const found = (text) => {
    const f = [];
    scan(text, "t", f);
    return f.map((x) => `${x.id}:${x.match}`);
  };
  const flagged = [
    host("nas", "lab", "arpa"),
    host("router", "home", "arpa"),
    host("build-01", "internal"),
    host("printer", "lan"),
    host("wiki", "corp"),
    host("db1", "example", "internal"),
  ];
  for (const h of flagged) assert.deepEqual(found(`ssh ${h} now`), [`internal-host:${h}`], h);
  assert.deepEqual(found(`http://${host("grafana", "internal")}/d/x`), [`internal-host:${host("grafana", "internal")}`]);
  assert.deepEqual(found(`${host("cache", "local")}:6379`), [`internal-host:${host("cache", "local")}`]);
  assert.deepEqual(found(`see ${host("nas", "lab", "arpa")}.`), [`internal-host:${host("nas", "lab", "arpa")}`]);
  // An email on such a host is one finding, from the email rule.
  assert.deepEqual(found(`mail ${mail("ops", "corp", "internal")}`), [`internal-email:${mail("ops", "corp", "internal")}`]);
  const clean = [
    "http://localhost:4000/",
    "app.localhost",
    "socket.assigns.internal",
    "opts.local",
    "conn.local()",
    "Foo.Internal.Bar",
    "MyApp.Local",
    "1.0.168.192.in-addr.arpa",
    "b.a.ip6.arpa",
    "example.com dev.example.org",
    "Phoenix.LiveView, :local, mix phx.server",
  ];
  for (const t of clean) assert.deepEqual(found(t), [], t);
});

test("the workflow gates pushes to every branch and pull requests", () => {
  const yml = readFileSync(join(here, "..", ".github", "workflows", "internal-refs.yml"), "utf8");
  const on = yml.slice(yml.indexOf("\non:"), yml.indexOf("\npermissions:"));
  assert.match(on, /\n {2}pull_request:/);
  assert.match(on, /\n {2}push:/);
  assert.doesNotMatch(on, /branches:\s*\[\s*main\s*\]/);
  assert.match(yml, /--published-remote origin/);
});

test("the CLI runs when invoked through a symlink or from a path with a space", () => {
  const dir = mkdtempSync(join(tmpdir(), "internal refs "));
  const real = join(dir, "real copy.mjs");
  copyFileSync(join(here, "check-internal-refs.mjs"), real);
  const link = join(dir, "link.mjs");
  symlinkSync(real, link);
  for (const script of [real, link]) {
    let status = 0;
    let stderr = "";
    try {
      execFileSync(process.execPath, [script], { stdio: ["ignore", "pipe", "pipe"], encoding: "utf8" });
    } catch (err) {
      status = err.status;
      stderr = err.stderr;
    }
    // No arguments: main() must run and refuse with usage, not exit 0 silently.
    assert.equal(status, 2, script);
    assert.match(stderr, /usage:/);
  }
});

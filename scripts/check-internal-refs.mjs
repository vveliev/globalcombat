#!/usr/bin/env node
/**
 * Refuse to publish internal references to a public repository.
 *
 * This fork is PUBLIC (a fork of a public repo cannot be made private). Internal
 * tracker ids, an agent identity on an internal email domain, and operational
 * notes reached its history before this gate existed. This gate exists so
 * that stops here. Adopted from the fleet's other public forks.
 *
 * Matching is by SHAPE, never by name. A denylist enumerating internal company
 * names, committed to a public repo, publishes the inventory it protects — so
 * literal names live in a private wordlist outside the tree, pointed at by
 * INTERNAL_REFS_WORDLIST, and are optional.
 *
 * Usage:
 *   node scripts/check-internal-refs.mjs --staged     # pre-commit
 *   node scripts/check-internal-refs.mjs --range A..B # CI / pre-push
 *   node scripts/check-internal-refs.mjs --message F  # commit-msg hook
 */

import { execFileSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";

const PATTERNS = [
  {
    id: "tracker-id",
    re: /\b[A-Z]{2,5}-\d{1,5}\b/g,
    why: "internal tracker id",
    // Conventional-commit scopes and CVEs are not tracker ids.
    // Standards, licences and wire constants share the shape but are not tracker ids.
    // Standards, licences, wire constants, this repo's own ADR numbering -- and placeholder prefixes used as
    // test fixtures. PROJ- in particular is upstream's own fixture convention;
    // flagging it would fail their tests as if they were our leak.
    ignore: /^(UTF|ISO|RFC|CVE|SHA|HTTP|API|SDK|ACP|UI|CI|BSD|GPL|LGPL|MPL|AGPL|EPL|CC|MIT|ECMA|RGB|AES|SHA1|SHA256|PROJ|TEST|EXAMPLE|FOO|BAR|ISSUE|CHAT|ADR)-/,
  },
  {
    id: "agent-trailer",
    re: /^Co-authored-by:.*\((?:.*\b(?:agent|bot)\b.*)\)/gim,
    why: "internal agent identity in a commit trailer",
  },
  {
    id: "internal-email",
    re: /\b[\w.+-]+@(?!users\.noreply\.github\.com\b)[\w-]+\.(?:dev|internal|local|lan)\b/g,
    why: "internal email domain",
  },
  {
    id: "host-path",
    re: /(?:\/paperclip\/instances\/|~?\/\.paperclip-docker)/g,
    why: "internal host path",
  },
  {
    id: "instance-uuid",
    re: /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/g,
    why: "instance/company/agent UUID",
  },
];

const wordlistPath = process.env.INTERNAL_REFS_WORDLIST;
if (wordlistPath && existsSync(wordlistPath)) {
  const words = readFileSync(wordlistPath, "utf8")
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"));
  if (words.length) {
    PATTERNS.push({
      id: "private-wordlist",
      re: new RegExp(words.map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|"), "gi"),
      why: "term from the private wordlist",
    });
  }
}

// Generated or vendored files are not authored content; scanning them only
// produces noise from third-party licence strings.
const SKIP = [/(^|\/)package-lock\.json$/, /(^|\/)(dist|coverage|node_modules)(\/|$)/];
const skipped = (f) => SKIP.some((r) => r.test(f));

function git(args) {
  return execFileSync("git", args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
}

/**
 * @param exclude pattern ids to skip for this text. A branch name derived from
 *   an issue id is metadata that reveals nothing -- the UUID rule exists to
 *   catch instance/company/agent ids leaking into published *content*, and
 *   applying it to a branch name would forbid the safest template available.
 */
function scan(text, label, findings, exclude = []) {
  for (const p of PATTERNS) {
    if (exclude.includes(p.id)) continue;
    p.re.lastIndex = 0;
    for (const m of text.matchAll(p.re)) {
      if (p.ignore && p.ignore.test(m[0])) continue;
      const line = text.slice(0, m.index).split("\n").length;
      findings.push({ label, line, match: m[0].split("\n")[0].slice(0, 90), why: p.why, id: p.id });
    }
  }
}

const mode = process.argv[2];
const arg = process.argv[3];
const findings = [];

if (mode === "--text") {
  // Reads from an env var, never argv: PR titles and bodies are attacker-
  // controlled text and must not be interpolated into a shell command.
  scan(process.env[arg ?? "SCAN_TEXT"] ?? "", "pull request title/body", findings);
} else if (mode === "--message") {
  scan(readFileSync(arg, "utf8"), "commit message", findings);
} else if (mode === "--staged") {
  for (const f of git(["diff", "--cached", "--name-only", "--diff-filter=ACM"]).split("\n").filter(Boolean)) {
    if (skipped(f)) continue;
    scan(git(["show", `:${f}`]), f, findings);
  }
} else if (mode === "--range") {
  // Scan ADDED LINES, not whole files. A change that merely touches a file
  // carrying a legacy reference publishes nothing new, and failing it would
  // make the gate block almost every edit -- which is how a gate gets
  // switched off. `git diff -U0` gives exactly the lines this range adds.
  let currentFile = null;
  let lineNo = 0;
  for (const raw of git(["diff", "-U0", "--diff-filter=ACM", arg]).split("\n")) {
    if (raw.startsWith("+++ b/")) {
      currentFile = raw.slice(6);
      continue;
    }
    const hunk = /^@@ -\d+(?:,\d+)? \+(\d+)/.exec(raw);
    if (hunk) {
      lineNo = Number(hunk[1]);
      continue;
    }
    if (!raw.startsWith("+") || raw.startsWith("+++")) continue;
    if (currentFile && !skipped(currentFile)) {
      scan(raw.slice(1), `${currentFile}:${lineNo}`, findings);
    }
    lineNo++;
  }
  scan(git(["log", "--format=%B%n%an <%ae>", arg]), "commit messages", findings);
  scan(git(["rev-parse", "--abbrev-ref", "HEAD"]), "branch name", findings, ["instance-uuid"]);
} else {
  console.error("usage: check-internal-refs.mjs --staged | --range A..B | --message FILE | --text ENVVAR");
  process.exit(2);
}

if (findings.length === 0) {
  console.log("internal-refs: clean");
  process.exit(0);
}

console.error(`\n  Refusing to publish ${findings.length} internal reference(s) to a public repository.\n`);
const byFile = new Map();
for (const f of findings) {
  if (!byFile.has(f.label)) byFile.set(f.label, []);
  byFile.get(f.label).push(f);
}
for (const [label, list] of byFile) {
  console.error(`  ${label}`);
  for (const f of list.slice(0, 8)) console.error(`    ${String(f.line).padStart(5)}  ${f.match}   (${f.why})`);
  if (list.length > 8) console.error(`    …and ${list.length - 8} more`);
  console.error("");
}
console.error("  Rewrite the reference, or set INTERNAL_REFS_ALLOW=1 for a reviewed exception.\n");
process.exit(process.env.INTERNAL_REFS_ALLOW === "1" ? 0 : 1);

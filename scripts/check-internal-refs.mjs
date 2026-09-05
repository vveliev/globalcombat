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
 *   node scripts/check-internal-refs.mjs --range A..B [--base-fallback REF] [--branch NAME]
 *   node scripts/check-internal-refs.mjs --text ENVVAR        # PR title/body
 *   node scripts/check-internal-refs.mjs --branch NAME        # a branch name alone
 *
 * --range scans the lines A..B ADDS (never whole files: a change that merely
 * touches a file carrying a legacy reference publishes nothing new), plus the
 * full commit messages and author identities of A..B. When A is missing or
 * unreachable (a brand-new branch, or the first push after a history rewrite)
 * the range is re-based on the merge-base of B with --base-fallback, or on B's
 * root commit if that is unavailable too.
 */

import { execFileSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";

const ZERO_SHA = /^0{40}$/;
// git's well-known empty tree: diffing against it yields every line of B as
// added, which is what "publishing a whole new history" means.
const EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904";

export const PATTERNS = [
  {
    id: "tracker-id",
    re: /\b[A-Z]{2,5}-\d{1,5}\b/g,
    why: "internal tracker id",
    // Same shape, not tracker ids: standards, licences, protocols and model
    // names, this repo's own ADR numbering, and placeholder prefixes used as
    // test fixtures (PROJ- is upstream's fixture convention).
    ignore: /^(UTF|ISO|RFC|CVE|SHA|HTTP|API|SDK|ACP|UI|CI|BSD|GPL|LGPL|MPL|AGPL|EPL|CC|MIT|ECMA|RGB|AES|TLS|SSL|GPT|DNS|SMTP|OTP|ADR|PROJ|TEST|FOO|BAR|ISSUE|CHAT)-/,
  },
  {
    id: "agent-trailer",
    re: /^Co-authored-by:.*\((?:.*\b(?:agent|bot)\b.*)\)/gim,
    why: "internal agent identity in a commit trailer",
  },
  {
    // Any depth of subdomain counts: an address under a sub-host of an internal
    // domain is as internal as one directly under it.
    id: "internal-email",
    re: /\b[\w.+-]+@(?:[\w-]+\.)+(?:dev|internal|local|lan)\b/g,
    why: "internal email domain",
  },
  {
    id: "host-path",
    re: /(?:\/paperclip\/instances\/|~?\/\.paperclip-docker)/g,
    why: "internal host path",
  },
  {
    id: "instance-uuid",
    re: /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi,
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

function git(args, { allowFail = false } = {}) {
  try {
    return execFileSync("git", args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"] });
  } catch (err) {
    if (allowFail) return null;
    console.error(`internal-refs: git ${args.join(" ")} failed: ${(err.stderr || err.message || "").toString().trim()}`);
    process.exit(2);
  }
}

const commitExists = (rev) => git(["cat-file", "-e", `${rev}^{commit}`], { allowFail: true }) !== null;

/**
 * Every finding is `{ where, match, why, id }`; `where` already carries the
 * line ("path:line" for content, "commit messages:line" for text).
 * @param exclude pattern ids to skip. A branch name derived from an issue id is
 *   metadata that reveals nothing -- the UUID rule exists to catch instance/
 *   company/agent ids leaking into published *content*, and applying it to a
 *   branch name would forbid the safest template available.
 */
export function scan(text, label, findings, { exclude = [], line = null } = {}) {
  for (const p of PATTERNS) {
    if (exclude.includes(p.id)) continue;
    p.re.lastIndex = 0;
    for (const m of text.matchAll(p.re)) {
      if (p.ignore && p.ignore.test(m[0])) continue;
      const at = line ?? text.slice(0, m.index).split("\n").length;
      findings.push({ where: `${label}:${at}`, match: m[0].split("\n")[0].slice(0, 90), why: p.why, id: p.id });
    }
  }
}

/**
 * Resolves "A..B" to `{ from, to }` where `from` actually exists: a missing,
 * all-zero or unreachable A (new branch; first push after a history rewrite)
 * becomes the merge-base of B with `fallback`. With no usable fallback either,
 * `from` is null: the whole of B is being published, so every line (diffed
 * against the empty tree) and every commit is scanned — a plain `root..B`
 * would silently exclude the root commit itself.
 */
export function resolveRange(range, fallback) {
  const [a, b = "HEAD"] = range.split("..");
  const to = git(["rev-parse", "--verify", `${b}^{commit}`]).trim();
  if (a && !ZERO_SHA.test(a) && commitExists(a)) return { from: a, to };
  if (fallback && commitExists(fallback)) {
    const mb = git(["merge-base", fallback, to], { allowFail: true });
    if (mb) return { from: mb.trim(), to };
  }
  return { from: null, to };
}

/** Added lines of `{from, to}`, as { file, line, text } — renames included, headers parsed by shape. */
export function addedLines({ from, to }) {
  const out = [];
  // Explicit prefixes: the default `+++ b/` header depends on the user's
  // diff.noprefix / diff.mnemonicPrefix settings, and a mis-parsed header
  // would make the whole scan silently "clean".
  const diff = git([
    "diff", "-U0", "--diff-filter=ACMR", "--src-prefix=a/", "--dst-prefix=b/", from ?? EMPTY_TREE, to,
  ]);
  let file = null;
  let lineNo = 0;
  let afterMinusHeader = false;
  for (const raw of diff.split("\n")) {
    if (raw.startsWith("diff --git ")) {
      file = null;
      afterMinusHeader = false;
      continue;
    }
    if (raw.startsWith("--- ")) {
      afterMinusHeader = true;
      continue;
    }
    // Only a `+++ b/` that directly follows the `--- ` line is a header: an
    // ADDED line whose content starts with "++" (C's `++i;`, a diff quoted in
    // markdown) is "+++i;" and must be scanned, not swallowed.
    if (afterMinusHeader && raw.startsWith("+++ b/")) {
      file = raw.slice(6);
      afterMinusHeader = false;
      continue;
    }
    afterMinusHeader = false;
    const hunk = /^@@ -\d+(?:,\d+)? \+(\d+)/.exec(raw);
    if (hunk) {
      lineNo = Number(hunk[1]);
      continue;
    }
    if (!raw.startsWith("+")) continue;
    if (file && !skipped(file)) out.push({ file, line: lineNo, text: raw.slice(1) });
    lineNo++;
  }
  return out;
}

export function scanRange(range, { fallback, branch } = {}) {
  const findings = [];
  const resolved = resolveRange(range, fallback);
  for (const { file, line, text } of addedLines(resolved)) scan(text, file, findings, { line });
  const logRange = resolved.from ? `${resolved.from}..${resolved.to}` : resolved.to;
  scan(git(["log", "--format=%B%n%an <%ae>", logRange]), "commit messages", findings);
  if (branch) scan(branch, "branch name", findings, { exclude: ["instance-uuid"], line: 1 });
  return { findings, resolved };
}

function report(findings) {
  if (findings.length === 0) {
    console.log("internal-refs: clean");
    return 0;
  }
  console.error(`\n  Refusing to publish ${findings.length} internal reference(s) to a public repository.\n`);
  for (const f of findings.slice(0, 40)) console.error(`  ${f.where}  ${f.match}   (${f.why})`);
  if (findings.length > 40) console.error(`  …and ${findings.length - 40} more`);
  console.error("\n  Rewrite the reference, or set INTERNAL_REFS_ALLOW=1 for a reviewed exception.\n");
  return process.env.INTERNAL_REFS_ALLOW === "1" ? 0 : 1;
}

function main(argv) {
  const args = [...argv];
  const opt = (name) => {
    const i = args.indexOf(name);
    if (i === -1) return undefined;
    const v = args[i + 1];
    args.splice(i, 2);
    return v;
  };
  const range = opt("--range");
  const fallback = opt("--base-fallback");
  const branch = opt("--branch");
  const textVar = opt("--text");
  const findings = [];

  if (range) {
    findings.push(...scanRange(range, { fallback, branch }).findings);
  } else if (textVar) {
    // Reads from an env var, never argv: PR titles and bodies are attacker-
    // controlled text and must not be interpolated into a shell command.
    scan(process.env[textVar] ?? "", `$${textVar}`, findings);
  } else if (branch) {
    scan(branch, "branch name", findings, { exclude: ["instance-uuid"], line: 1 });
  } else {
    console.error("usage: check-internal-refs.mjs --range A..B [--base-fallback REF] [--branch NAME] | --text ENVVAR | --branch NAME");
    return 2;
  }
  return report(findings);
}

if (process.argv[1] && import.meta.url === `file://${process.argv[1]}`) {
  process.exit(main(process.argv.slice(2)));
}

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
 *   node scripts/check-internal-refs.mjs --range A..B [--base-fallback REF | --published-remote NAME] [--branch NAME]
 *   node scripts/check-internal-refs.mjs --text ENVVAR        # PR title/body
 *   node scripts/check-internal-refs.mjs --branch NAME        # a branch name alone
 *
 * --range scans the lines each commit of A..B ADDS — commit by commit, so a
 * reference added by one commit and removed by a later one in the same push is
 * still caught (the first commit publishes it) — never whole files: a change
 * that merely touches a file carrying a legacy reference publishes nothing new.
 * It also scans the full commit messages and the author AND committer
 * identities of A..B. When A is missing or unreachable see resolveRange().
 */

import { execFileSync } from "node:child_process";
import { readFileSync, existsSync, realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

const ZERO_SHA = /^0{40}$/;

// Same shape as a tracker id, but not one: standards, licences, protocols and
// model names, this repo's own ADR numbering, and placeholder prefixes used as
// test fixtures (PROJ- is upstream's fixture convention).
const NOT_TRACKERS = "UTF|ISO|RFC|CVE|SHA|HTTP|API|SDK|ACP|UI|CI|BSD|GPL|LGPL|MPL|AGPL|EPL|CC|MIT|ECMA|RGB|AES|TLS|SSL|GPT|DNS|SMTP|OTP|ADR|PROJ|TEST|FOO|BAR|ISSUE|CHAT";
// Ordinary words that lead lower-case branch segments in this repo (a plan's
// `task-3-dock`, a `step-2` spike). An allowlist of benign words, never a
// denylist of internal names.
const BENIGN_WORDS = "task|step|part|phase|stage|round|turn|item|page|pre|post|wip|try|fix|feat|chore|draft|demo|spike|issue";

// A DNS label, lower-case only: `Foo.Internal` is an Elixir module, not a host.
const LABEL = "[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?";
// A host starts where no host/identifier/email character precedes it (so the
// `user@host` of an email is left to the internal-email rule) and ends where
// no further label, identifier character or call follows — `foo.localhost`
// and `a.local.b` are not `.local` hosts.
const HOST_START = "(?<![\\w@.$-])";
const HOST_END = "(?![\\w-]|\\.[\\w]|\\()";

export const PATTERNS = [
  {
    id: "tracker-id",
    re: /\b[A-Z]{2,5}-\d{1,5}\b/g,
    why: "internal tracker id",
    ignore: new RegExp(`^(?:${NOT_TRACKERS})-`),
  },
  {
    // Lower/mixed case (a `fix/` branch named after a ticket). Matching every lower-case `xx-N`
    // would drown in Tailwind classes (`mt-2`, `space-4`, `red-6`), so only
    // the positions a tracker id takes in a reference count: the start of a
    // branch name or of a path segment (`fix/…`, `owner/…`, a tracker URL),
    // and the quoted branch of a local merge message (`Merge branch '…'`).
    // An all-upper match is left to the rule above.
    id: "tracker-id",
    re: /(?<=^|\/|\bbranch ')(?![A-Z]{2,5}-)[A-Za-z]{2,5}-\d{1,5}\b/g,
    why: "internal tracker id",
    ignore: new RegExp(`^(?:${NOT_TRACKERS}|${BENIGN_WORDS})-`, "i"),
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
  {
    // Private-network host suffixes that never name a public host: any
    // `*.arpa` zone other than the reverse-DNS ones (`home.arpa` is RFC 8375's
    // home-network zone), and the conventional LAN/corporate suffixes.
    id: "internal-host",
    re: new RegExp(
      `${HOST_START}(?:${LABEL}\\.)+(?:(?!in-addr\\.|ip6\\.)${LABEL}\\.arpa|lan|corp|intranet|localdomain)${HOST_END}`,
      "g",
    ),
    why: "internal hostname",
  },
  {
    // `.internal` and `.local` are also ordinary identifiers (`assigns.local`,
    // `opts.internal`), so they count only with evidence of being a host: a
    // URL (`//host`), a port or path after it, or a label carrying a digit or
    // hyphen (a `db-N` or `nasNN` first label) — which identifiers lack.
    id: "internal-host",
    re: new RegExp(`${HOST_START}(?:${LABEL}\\.)+(?:internal|local)${HOST_END}`, "g"),
    why: "internal hostname",
    keep: (m, text) =>
      /[\d-]/.test(m[0]) || text.slice(Math.max(0, m.index - 2), m.index) === "//" || /^(?::\d|\/)/.test(text.slice(m.index + m[0].length)),
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
export function scan(text, label, findings, { exclude = [], line = null, commit = null } = {}) {
  for (const p of PATTERNS) {
    if (exclude.includes(p.id)) continue;
    p.re.lastIndex = 0;
    for (const m of text.matchAll(p.re)) {
      if (p.ignore && p.ignore.test(m[0])) continue;
      if (p.keep && !p.keep(m, text)) continue;
      const at = line ?? text.slice(0, m.index).split("\n").length;
      const finding = { where: `${label}:${at}`, match: m[0].split("\n")[0].slice(0, 90), why: p.why, id: p.id };
      if (commit) finding.commit = commit;
      findings.push(finding);
    }
  }
}

/**
 * Resolves "A..B" to the set of commits being published, as `{ from, to }`
 * (the commits of from..to) or `{ from: null, to, not }` (the commits of `to`
 * reachable from none of the refs in `not`; with `not` absent or empty, the
 * whole history of `to`). A usable A is taken as is. Otherwise:
 *
 * - With `publishedRemote` (CI): A is all-zero (new branch) or no longer
 *   exists in the clone (a history rewrite — GitHub's `before` is the
 *   pre-force-push tip, which a fresh clone never fetched). What the remote
 *   already published is then every remote-tracking ref EXCEPT the pushed
 *   branch itself (and symrefs to it, e.g. `origin/HEAD`): CI fetches after
 *   the push, so the pushed ref already points at B, and treating it as
 *   "published" is what made a rewritten default branch scan an empty range.
 *   A new branch cut from main resolves to nothing; a branch reset onto main
 *   resolves to nothing; a rewritten main scans every rewritten commit not on
 *   some other branch. Known gap: a commit that ONLY exists on branches all
 *   created or rewritten by the same multi-ref push is excused by whichever
 *   of them is not the ref being scanned; the pre-push hook still covers it.
 *   Without `branch` the pushed ref cannot be named, so every ref whose tip IS
 *   B is distrusted instead.
 * - With `fallback` (pre-push hook, which reads the remote's state BEFORE the
 *   push): the merge-base of B with it.
 * - Otherwise the whole history of B — every commit including the root, whose
 *   diff `git log --root` shows against the empty tree.
 */
export function resolveRange(range, fallback, { publishedRemote, branch } = {}) {
  const [a, b = "HEAD"] = range.split("..");
  const to = git(["rev-parse", "--verify", "--end-of-options", `${b}^{commit}`]).trim();
  if (a && !ZERO_SHA.test(a) && commitExists(a)) return { from: git(["rev-parse", "--verify", "--end-of-options", `${a}^{commit}`]).trim(), to };
  if (publishedRemote) {
    const self = branch ? `refs/remotes/${publishedRemote}/${branch}` : null;
    const not = git(["for-each-ref", "--format=%(refname)%00%(symref)%00%(objectname)", `refs/remotes/${publishedRemote}/`])
      .split("\n")
      .filter(Boolean)
      .map((l) => l.split("\0"))
      .filter(([ref, symref, sha]) => (self ? ref !== self && symref !== self : sha !== to))
      .map(([ref]) => ref);
    return { from: null, to, not };
  }
  if (fallback && commitExists(fallback)) {
    const mb = git(["merge-base", fallback, to], { allowFail: true });
    if (mb) return { from: mb.trim(), to };
  }
  return { from: null, to };
}

const revArgs = ({ from, to, not = [] }) => (from ? [`${from}..${to}`] : not.length ? [to, "--not", ...not] : [to]);

// Undoes git's C-style quoting of a path ("caf\303\251.md", "t\tab.md"): with
// core.quotePath=false non-ASCII is left raw, but tabs, newlines, quotes and
// backslashes are still escaped, and octal escapes are UTF-8 BYTES.
function unquote(s) {
  if (!s.startsWith('"')) return s;
  const bytes = [];
  for (const [, esc, plain] of s.slice(1, s.lastIndexOf('"')).matchAll(/\\([0-7]{3}|.)|([^\\]+)/gs)) {
    if (plain !== undefined) bytes.push(...Buffer.from(plain, "utf8"));
    else if (/^[0-7]{3}$/.test(esc)) bytes.push(parseInt(esc, 8));
    else bytes.push({ a: 7, b: 8, t: 9, n: 10, v: 11, f: 12, r: 13 }[esc] ?? esc.charCodeAt(0));
  }
  return Buffer.from(bytes).toString("utf8");
}

// Label for added lines whose file header could not be parsed. The lines are
// still scanned (and never treated as vendored): a header the parser fails to
// read must not make the scan silently "clean".
export const UNPARSED_PATH = "(unparsed path)";

/**
 * Parses `git log -p --cc --format=%x01%H` output into added lines,
 * { commit, file, line, text }. Headers are recognised by position (between a
 * `diff ` line and the first hunk), never by content: an ADDED line whose text
 * starts with "++" (C's `++i;`) is "+++i;" and must be scanned, not taken for
 * a header. Merge commits arrive as combined diffs (`@@@`, one prefix column
 * per parent); only lines added relative to EVERY parent are new content —
 * the rest was published by the parents themselves.
 */
export function parsePatch(patch) {
  const out = [];
  let commit = null;
  let file = null;
  let inHeader = false;
  let cols = 1;
  let lineNo = 0;
  for (const raw of patch.split("\n")) {
    if (raw.startsWith("\x01")) {
      commit = raw.slice(1, 13);
      file = null;
      inHeader = false;
      continue;
    }
    if (raw.startsWith("diff ")) {
      file = null;
      inHeader = true;
      continue;
    }
    const hunk = /^(@@+) -.*? \+(\d+)(?:,\d+)? \1/.exec(raw);
    if (hunk) {
      inHeader = false;
      cols = hunk[1].length - 1;
      lineNo = Number(hunk[2]);
      continue;
    }
    if (inHeader) {
      if (raw.startsWith("+++ ")) {
        const path = unquote(raw.slice(4));
        file = path === "/dev/null" ? null : path.startsWith("b/") ? path.slice(2) : path;
      }
      continue;
    }
    const prefix = raw.slice(0, cols);
    if (prefix.length < cols || !/^[ +-]+$/.test(prefix) || prefix.includes("-")) continue;
    if (/^\++$/.test(prefix) && !(file && skipped(file))) {
      out.push({ commit, file: file ?? UNPARSED_PATH, line: lineNo, text: raw.slice(cols) });
    }
    lineNo++;
  }
  return out;
}

/** Lines each commit of the resolved range adds, as { commit, file, line, text }. */
export function addedLines(resolved) {
  // core.quotePath=false keeps non-ASCII paths readable (parsePatch unquotes
  // whatever git still escapes). Explicit prefixes: the default `+++ b/`
  // depends on diff.noprefix / diff.mnemonicPrefix. No textconv/ext-diff/
  // relative/signature output: user config must not reshape what is scanned.
  const patch = git([
    "-c", "core.quotePath=false",
    "log", "-p", "--cc", "--root", "-M", "-U0", "--no-color", "--no-ext-diff", "--no-textconv", "--no-relative",
    "--no-show-signature", "--diff-filter=ACMR", "--src-prefix=a/", "--dst-prefix=b/", "--format=%x01%H",
    ...revArgs(resolved),
  ]);
  return parsePatch(patch);
}

export function scanRange(range, { fallback, publishedRemote, branch } = {}) {
  const findings = [];
  const resolved = resolveRange(range, fallback, { publishedRemote, branch });
  for (const { commit, file, line, text } of addedLines(resolved)) scan(text, file, findings, { line, commit });
  scan(
    git(["log", "--no-show-signature", "--format=%B%n%an <%ae>%n%cn <%ce>", ...revArgs(resolved)]),
    "commit messages",
    findings,
  );
  if (branch) scan(branch, "branch name", findings, { exclude: ["instance-uuid"], line: 1 });
  return { findings, resolved };
}

function report(findings) {
  if (findings.length === 0) {
    console.log("internal-refs: clean");
    return 0;
  }
  console.error(`\n  Refusing to publish ${findings.length} internal reference(s) to a public repository.\n`);
  for (const f of findings.slice(0, 40)) console.error(`  ${f.where}${f.commit ? ` (commit ${f.commit})` : ""}  ${f.match}   (${f.why})`);
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
  const publishedRemote = opt("--published-remote");
  const branch = opt("--branch");
  const textVar = opt("--text");
  const findings = [];

  if (range) {
    findings.push(...scanRange(range, { fallback, publishedRemote, branch }).findings);
  } else if (textVar) {
    // Reads from an env var, never argv: PR titles and bodies are attacker-
    // controlled text and must not be interpolated into a shell command.
    scan(process.env[textVar] ?? "", `$${textVar}`, findings);
  } else if (branch) {
    scan(branch, "branch name", findings, { exclude: ["instance-uuid"], line: 1 });
  } else {
    console.error("usage: check-internal-refs.mjs --range A..B [--base-fallback REF | --published-remote NAME] [--branch NAME] | --text ENVVAR | --branch NAME");
    return 2;
  }
  return report(findings);
}

// Run main() only when executed, not when imported by the tests. Compared as
// real paths: a URL-built `file://${argv[1]}` never equals import.meta.url
// once the path holds a space (percent-encoded in the URL) or the script is
// reached through a symlink (node resolves it), and the gate would then exit
// 0 without scanning anything.
function invokedDirectly() {
  if (!process.argv[1]) return false;
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (invokedDirectly()) {
  process.exit(main(process.argv.slice(2)));
}

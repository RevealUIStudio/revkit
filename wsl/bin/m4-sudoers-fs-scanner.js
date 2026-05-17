#!/usr/bin/env node
// m4-sudoers-fs-scanner.js — Sudoers + filesystem invariant scanner
//
// Spec: internal fleet-security-hardening lane § M-4 (meta-durability-fixes)
// Companion designs: sprint-tier-0.md T0-1, T0-2, T0-3
//
// Source of truth: revkit/wsl/bin/m4-sudoers-fs-scanner.js (this file).
// Runtime location: ~/.claude/hooks/m4-sudoers-fs-scanner.js (copied by
//   bootstrap-wsl.sh step 7).
// Invoked from: ~/.claude/hooks/session-start.js (M-4 scan block).
//
// Read-only. No mutations. Pure stat + read + parse.
//
// Exit codes:
//   0  — clean: every invariant satisfied
//   2  — violation: at least one invariant failed; structured findings on stderr
//   1  — internal error (unexpected exception); stderr describes
//
// Output format on violation (stderr, one block per finding):
//   [M-4] <CLASS> VIOLATION: <where> — <rule failed>.
//     Remediation: <pointer to lane plan, file:line within the lane>
//
// No regex authored anywhere in this file (per fleet rule). All parsing
// uses String.prototype methods + line-by-line iteration + Set lookups.
//
// Test-mode env vars (for revkit/tests/m4-scanner/):
//   M4_SUDOERS_DIR_OVERRIDE  — read sudoers fixtures from this dir instead of /etc/sudoers.d
//   M4_FS_OVERRIDE_HOME      — pretend $HOME is this dir (for ~/.age-identity, ~/.ssh, ~/.revealui)
//   M4_FS_OVERRIDE_SUDOLOG   — path to use instead of /var/log/sudo.log

"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");

// ============================================================================
// Configuration
// ============================================================================

const SUDOERS_DIR = process.env.M4_SUDOERS_DIR_OVERRIDE || "/etc/sudoers.d";
const HOME_DIR = process.env.M4_FS_OVERRIDE_HOME || os.homedir();
const SUDOLOG = process.env.M4_FS_OVERRIDE_SUDOLOG || "/var/log/sudo.log";

// Remediation pointer shown on violation. Generic phrasing so this scanner
// is safe to publish in revkit (which is going public per T0-15) without
// leaking internal-repo paths. Fleet operators know where to find the spec;
// non-fleet contributors won't have this scanner installed at all.
const REMEDIATION_LANE =
  "your fleet's internal sprint-tier-0.md (M-4 spec)";

// System-binary prefixes that NOPASSWD can never legitimately reach.
const SYSTEM_BINARY_PREFIXES = [
  "/usr/bin/",
  "/bin/",
  "/usr/sbin/",
  "/sbin/",
];

// Glob/wildcard characters that must never appear in a NOPASSWD arg list.
const GLOB_CHARS = new Set(["*", "?", "[", "]"]);

// Required Defaults entries that must be present in /etc/sudoers.d/00-defaults.
// Stored as a Set for O(1) lookups during file scan. Each entry is the
// keyword to look for after a leading "Defaults" token.
const REQUIRED_DEFAULTS = new Set([
  "timestamp_timeout",
  "use_pty",
  "env_reset",
  "log_subcmds",
  "logfile",
  "passwd_tries",
]);

// Filesystem invariants — table-driven so adding a new file is one row.
// Each entry: {
//   path: absolute path (HOME-relative paths resolved at scan time),
//   kind: "file" | "dir" | "ssh-private-keys",
//   maxMode: octal mode (string) — file/dir mode bits must be <= this value
//             when masked with 0o777 (we ignore sticky/setuid/setgid bits),
//   exactMode: optional — if set, mode must equal exactly,
//   ownerMustBe: optional — uid that must own the file (root = 0),
//   missingOk: if true, missing file is not a violation,
// }
function fsInvariants() {
  return [
    {
      label: "age identity key",
      target: path.join(HOME_DIR, ".age-identity/keys.txt"),
      kind: "file",
      exactMode: 0o600,
      missingOk: false,
      ruleId: "fs-age-key-mode",
      ruleDesc: "~/.age-identity/keys.txt must be mode 600",
      remediationFile: "T0-1",
    },
    {
      label: "age identity directory",
      target: path.join(HOME_DIR, ".age-identity"),
      kind: "dir",
      exactMode: 0o700,
      missingOk: false,
      ruleId: "fs-age-dir-mode",
      ruleDesc: "~/.age-identity directory must be mode 700",
      remediationFile: "T0-1",
    },
    {
      label: "revealui passage store",
      target: path.join(HOME_DIR, ".revealui/passage-store"),
      kind: "dir",
      maxMode: 0o700,
      missingOk: true, // not all dev environments have revvault initialized
      ruleId: "fs-passage-store-mode",
      ruleDesc: "~/.revealui/passage-store directory must be mode 700 or stricter",
      remediationFile: "T0-1",
    },
    {
      label: "ssh private keys",
      target: path.join(HOME_DIR, ".ssh"),
      kind: "ssh-private-keys",
      exactMode: 0o600,
      missingOk: true,
      ruleId: "fs-ssh-private-key-mode",
      ruleDesc: "~/.ssh/id_* private keys must be mode 600",
      remediationFile: "T0-1",
    },
    {
      label: "sudo audit log",
      target: SUDOLOG,
      kind: "file",
      exactMode: 0o600,
      ownerMustBe: 0,
      missingOk: true, // doesn't exist until 00-defaults is applied + first sudo runs
      ruleId: "fs-sudolog-mode-owner",
      ruleDesc: "/var/log/sudo.log must be mode 600 owned by root",
      remediationFile: "T0-2",
    },
  ];
}

// ============================================================================
// Helpers — pure, no side effects beyond fs.statSync / fs.readFileSync
// ============================================================================

/**
 * Strip a trailing comment from a sudoers line, respecting the rule that
 * `#` starts a comment unless preceded by `\` (sudoers escape). Returns
 * the code portion only.
 */
function stripTrailingComment(line) {
  let out = "";
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === "#" && (i === 0 || line[i - 1] !== "\\")) break;
    out += ch;
  }
  return out;
}

/**
 * Tokenize a sudoers line by whitespace, after stripping trailing comments.
 * Returns an array of non-empty tokens.
 */
function tokenize(line) {
  const code = stripTrailingComment(line);
  const tokens = [];
  let buf = "";
  for (let i = 0; i < code.length; i++) {
    const ch = code[i];
    if (ch === " " || ch === "\t") {
      if (buf.length > 0) {
        tokens.push(buf);
        buf = "";
      }
      continue;
    }
    buf += ch;
  }
  if (buf.length > 0) tokens.push(buf);
  return tokens;
}

/**
 * Check whether the joined-arg portion of a NOPASSWD entry contains any
 * glob/wildcard char. Iterates char-by-char so we don't need regex.
 */
function containsGlob(s) {
  for (let i = 0; i < s.length; i++) {
    if (GLOB_CHARS.has(s[i])) return true;
  }
  return false;
}

/**
 * Detect whether a tokenized line is a NOPASSWD entry. Returns the index
 * within tokens where "NOPASSWD:" appears, or -1 if not present.
 *
 * Sudoers shape we care about:
 *   <user> <hostspec>=(<runas>) NOPASSWD: <cmdSpec>...
 * NOPASSWD: may also be combined with a tag list (NOPASSWD:SETENV:); we
 * accept any token that begins with "NOPASSWD" and contains ":".
 */
function findNopasswdIndex(tokens) {
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t.startsWith("NOPASSWD") && t.includes(":")) return i;
    // Some configs split as `NOPASSWD :`; treat bare `NOPASSWD` followed
    // by `:` as a hit too.
    if (t === "NOPASSWD" && i + 1 < tokens.length && tokens[i + 1].startsWith(":")) {
      return i;
    }
  }
  return -1;
}

/**
 * Extract the command + args portion that follows NOPASSWD: in a tokenized
 * sudoers entry. Returns the joined string (single space separator) or "".
 */
function extractNopasswdCmdSpec(tokens, nopasswdIdx) {
  const t = tokens[nopasswdIdx];
  let firstCmdToken;
  let startIdx;
  if (t === "NOPASSWD") {
    // Split form: NOPASSWD : /path/to/cmd arg
    startIdx = nopasswdIdx + 2;
    if (tokens[nopasswdIdx + 1] !== ":") return "";
  } else {
    // Joined form: NOPASSWD:/path/to/cmd  or  NOPASSWD: /path/to/cmd
    const colonIdx = t.indexOf(":");
    const after = t.slice(colonIdx + 1);
    if (after.length > 0) {
      firstCmdToken = after;
      startIdx = nopasswdIdx + 1;
    } else {
      startIdx = nopasswdIdx + 1;
    }
  }
  const parts = [];
  if (firstCmdToken) parts.push(firstCmdToken);
  for (let i = startIdx; i < tokens.length; i++) {
    parts.push(tokens[i]);
  }
  return parts.join(" ").trim();
}

/**
 * Test whether a path string starts with any of SYSTEM_BINARY_PREFIXES.
 */
function isSystemBinaryPath(p) {
  for (const prefix of SYSTEM_BINARY_PREFIXES) {
    if (p.startsWith(prefix)) return true;
  }
  return false;
}

/**
 * Check the line range [start, end] (inclusive) of file lines for a comment
 * that starts with `# justification:`. Returns true if found.
 */
function hasJustificationCommentIn(lines, startInclusive, endInclusive) {
  const lo = Math.max(0, startInclusive);
  const hi = Math.min(lines.length - 1, endInclusive);
  for (let i = lo; i <= hi; i++) {
    const trimmed = lines[i].trim();
    if (trimmed.startsWith("# justification:")) return true;
  }
  return false;
}

// ============================================================================
// Sudoers scan
// ============================================================================

/**
 * Scan all readable files in SUDOERS_DIR. Returns { findings, eaccesFiles }.
 *
 * findings: array of { class, where, ruleDesc, remediationFile }
 * eaccesFiles: array of file paths that couldn't be read (permission denied);
 *              the hook surfaces this as a separate warning so the user knows
 *              the scan was partial.
 */
function scanSudoersDir() {
  const findings = [];
  const eaccesFiles = [];

  let entries;
  try {
    entries = fs.readdirSync(SUDOERS_DIR);
  } catch (err) {
    if (err && err.code === "ENOENT") {
      // No sudoers.d at all is a violation of the 00-defaults requirement.
      findings.push({
        class: "SUDOERS",
        where: `${SUDOERS_DIR}/`,
        ruleDesc:
          `${SUDOERS_DIR} does not exist — required 00-defaults block cannot be present`,
        remediationFile: "T0-2",
      });
      return { findings, eaccesFiles };
    }
    if (err && err.code === "EACCES") {
      eaccesFiles.push(SUDOERS_DIR);
      return { findings, eaccesFiles };
    }
    throw err;
  }

  let sawDefaultsFile = false;
  let defaultsHasAllRequired = false;
  let defaultsMissingKeywords = [];

  for (const entry of entries) {
    // Skip backup files matching sudoers conventions (vim ~, dpkg .bak, etc.)
    // — sudo itself ignores files containing `.` or ending in `~`.
    if (entry.endsWith("~")) continue;
    if (entry.includes(".")) continue;

    const full = path.join(SUDOERS_DIR, entry);

    let stat;
    try {
      stat = fs.statSync(full);
    } catch (err) {
      if (err && err.code === "EACCES") {
        eaccesFiles.push(full);
        continue;
      }
      continue;
    }
    if (!stat.isFile()) continue;

    let content;
    try {
      content = fs.readFileSync(full, "utf8");
    } catch (err) {
      if (err && err.code === "EACCES") {
        eaccesFiles.push(full);
        continue;
      }
      continue;
    }

    const lines = content.split("\n");

    if (entry === "00-defaults") {
      sawDefaultsFile = true;
      const seenKeywords = new Set();
      for (const line of lines) {
        const code = stripTrailingComment(line).trim();
        if (!code.startsWith("Defaults")) continue;
        // After "Defaults" (optionally followed by spec qualifiers like
        // `Defaults:user` or `Defaults!cmd`) the next token is keyword[=val].
        // We just scan tokens for any keyword that matches REQUIRED_DEFAULTS.
        const tokens = tokenize(code);
        for (const t of tokens) {
          const eqIdx = t.indexOf("=");
          const keyword = eqIdx >= 0 ? t.slice(0, eqIdx) : t;
          if (REQUIRED_DEFAULTS.has(keyword)) seenKeywords.add(keyword);
        }
      }
      const missing = [];
      for (const k of REQUIRED_DEFAULTS) {
        if (!seenKeywords.has(k)) missing.push(k);
      }
      defaultsHasAllRequired = missing.length === 0;
      defaultsMissingKeywords = missing;
    }

    // Scan every line for NOPASSWD entries.
    for (let i = 0; i < lines.length; i++) {
      const raw = lines[i];
      const code = stripTrailingComment(raw).trim();
      if (code.length === 0) continue;

      const tokens = tokenize(raw);
      const nopasswdIdx = findNopasswdIndex(tokens);
      if (nopasswdIdx < 0) continue;

      const lineNum = i + 1; // human-readable

      // Rule: forbid NOPASSWD: ALL in any form.
      // Check the cmd spec for the literal token "ALL".
      const cmdSpec = extractNopasswdCmdSpec(tokens, nopasswdIdx);
      const cmdTokens = cmdSpec.split(",").map((s) => s.trim()).filter(Boolean);

      for (const cmd of cmdTokens) {
        const head = cmd.split(" ")[0];

        if (head === "ALL") {
          findings.push({
            class: "SUDOERS",
            where: `${full}:${lineNum}`,
            ruleDesc: "NOPASSWD: ALL is forbidden in any form (T0-2 hardline)",
            remediationFile: "T0-2",
          });
          continue;
        }

        // Rule: forbid NOPASSWD to /usr/bin/*, /bin/*, /usr/sbin/*, /sbin/*.
        if (isSystemBinaryPath(head)) {
          findings.push({
            class: "SUDOERS",
            where: `${full}:${lineNum}`,
            ruleDesc:
              `NOPASSWD to system-binary path ${head} is forbidden (T0-3 hardline)`,
            remediationFile: "T0-3",
          });
        }

        // Rule: forbid glob/wildcard chars (*, ?, [, ]) in args.
        if (containsGlob(cmd)) {
          findings.push({
            class: "SUDOERS",
            where: `${full}:${lineNum}`,
            ruleDesc:
              `NOPASSWD entry contains glob/wildcard char (one of * ? [ ]) in "${cmd}" — only literal args allowed`,
            remediationFile: "T0-3",
          });
        }

        // Rule: NOPASSWD to /usr/local/bin/* without exact literal arg.
        // Allowed shape is: /usr/local/bin/<script> <literalArg>
        // (exactly one arg after the script path).
        if (head.startsWith("/usr/local/bin/")) {
          const argsAfter = cmd.slice(head.length).trim();
          if (argsAfter.length === 0) {
            findings.push({
              class: "SUDOERS",
              where: `${full}:${lineNum}`,
              ruleDesc:
                `NOPASSWD to ${head} without a pinned literal arg — every NOPASSWD must be one-script-one-literal-arg`,
              remediationFile: "T0-3",
            });
          }
        }
      }

      // Rule: every NOPASSWD entry needs a `# justification:` comment within
      // the 5 lines preceding the entry.
      if (!hasJustificationCommentIn(lines, i - 5, i - 1)) {
        findings.push({
          class: "SUDOERS",
          where: `${full}:${lineNum}`,
          ruleDesc:
            "NOPASSWD entry has no `# justification: <reason>` comment in the 5 preceding lines",
          remediationFile: "T0-3",
        });
      }
    }
  }

  // Rule: 00-defaults must exist with the required Defaults block.
  if (!sawDefaultsFile) {
    findings.push({
      class: "SUDOERS",
      where: `${SUDOERS_DIR}/00-defaults`,
      ruleDesc:
        `Required file ${SUDOERS_DIR}/00-defaults is missing — must contain Defaults block with: ${Array.from(REQUIRED_DEFAULTS).join(", ")}`,
      remediationFile: "T0-2",
    });
  } else if (!defaultsHasAllRequired) {
    findings.push({
      class: "SUDOERS",
      where: `${SUDOERS_DIR}/00-defaults`,
      ruleDesc:
        `Required Defaults missing from 00-defaults: ${defaultsMissingKeywords.join(", ")}`,
      remediationFile: "T0-2",
    });
  }

  return { findings, eaccesFiles };
}

// ============================================================================
// Filesystem scan
// ============================================================================

function scanFilesystem() {
  const findings = [];
  const eaccesFiles = [];

  for (const inv of fsInvariants()) {
    let stat;
    try {
      stat = fs.lstatSync(inv.target);
    } catch (err) {
      if (err && err.code === "ENOENT") {
        if (!inv.missingOk) {
          findings.push({
            class: "FILESYSTEM",
            where: inv.target,
            ruleDesc: `${inv.ruleDesc} — file does not exist`,
            remediationFile: inv.remediationFile,
          });
        }
        continue;
      }
      if (err && err.code === "EACCES") {
        eaccesFiles.push(inv.target);
        continue;
      }
      continue;
    }

    if (inv.kind === "file") {
      if (!stat.isFile()) {
        findings.push({
          class: "FILESYSTEM",
          where: inv.target,
          ruleDesc: `${inv.ruleDesc} — exists but is not a regular file`,
          remediationFile: inv.remediationFile,
        });
        continue;
      }
      const mode = stat.mode & 0o777;
      if (inv.exactMode !== undefined && mode !== inv.exactMode) {
        findings.push({
          class: "FILESYSTEM",
          where: inv.target,
          ruleDesc: `${inv.ruleDesc} — currently mode ${mode.toString(8).padStart(3, "0")}`,
          remediationFile: inv.remediationFile,
        });
      } else if (inv.maxMode !== undefined && mode > inv.maxMode) {
        findings.push({
          class: "FILESYSTEM",
          where: inv.target,
          ruleDesc: `${inv.ruleDesc} — currently mode ${mode.toString(8).padStart(3, "0")}`,
          remediationFile: inv.remediationFile,
        });
      }
      if (inv.ownerMustBe !== undefined && stat.uid !== inv.ownerMustBe) {
        findings.push({
          class: "FILESYSTEM",
          where: inv.target,
          ruleDesc: `${inv.ruleDesc} — currently owned by uid ${stat.uid}, required uid ${inv.ownerMustBe}`,
          remediationFile: inv.remediationFile,
        });
      }
    } else if (inv.kind === "dir") {
      if (!stat.isDirectory()) {
        findings.push({
          class: "FILESYSTEM",
          where: inv.target,
          ruleDesc: `${inv.ruleDesc} — exists but is not a directory`,
          remediationFile: inv.remediationFile,
        });
        continue;
      }
      const mode = stat.mode & 0o777;
      if (inv.exactMode !== undefined && mode !== inv.exactMode) {
        findings.push({
          class: "FILESYSTEM",
          where: inv.target,
          ruleDesc: `${inv.ruleDesc} — currently mode ${mode.toString(8).padStart(3, "0")}`,
          remediationFile: inv.remediationFile,
        });
      } else if (inv.maxMode !== undefined && mode > inv.maxMode) {
        findings.push({
          class: "FILESYSTEM",
          where: inv.target,
          ruleDesc: `${inv.ruleDesc} — currently mode ${mode.toString(8).padStart(3, "0")}`,
          remediationFile: inv.remediationFile,
        });
      }
    } else if (inv.kind === "ssh-private-keys") {
      if (!stat.isDirectory()) continue;
      let dirEntries;
      try {
        dirEntries = fs.readdirSync(inv.target);
      } catch (err) {
        if (err && err.code === "EACCES") {
          eaccesFiles.push(inv.target);
          continue;
        }
        continue;
      }
      for (const name of dirEntries) {
        // SSH private keys: ~/.ssh/id_* that do NOT end in `.pub`.
        if (!name.startsWith("id_")) continue;
        if (name.endsWith(".pub")) continue;
        const keyPath = path.join(inv.target, name);
        let keyStat;
        try {
          keyStat = fs.lstatSync(keyPath);
        } catch {
          continue;
        }
        if (!keyStat.isFile()) continue;
        const mode = keyStat.mode & 0o777;
        if (mode !== inv.exactMode) {
          findings.push({
            class: "FILESYSTEM",
            where: keyPath,
            ruleDesc: `~/.ssh/${name} (private SSH key) must be mode 600 — currently ${mode.toString(8).padStart(3, "0")}`,
            remediationFile: inv.remediationFile,
          });
        }
      }
    }
  }

  return { findings, eaccesFiles };
}

// ============================================================================
// Output
// ============================================================================

function writeFinding(f) {
  process.stderr.write(
    `[M-4] ${f.class} VIOLATION: ${f.where} — ${f.ruleDesc}.\n` +
      `  Remediation: ${REMEDIATION_LANE} ${f.remediationFile}\n`
  );
}

function writePartialReadNotice(eaccesFiles) {
  if (eaccesFiles.length === 0) return;
  process.stderr.write(
    `[M-4] PARTIAL SCAN: ${eaccesFiles.length} path(s) unreadable (EACCES) — scan was incomplete:\n`
  );
  for (const p of eaccesFiles) {
    process.stderr.write(`  ${p}\n`);
  }
  process.stderr.write(
    `  Re-run with sudo (or after running ${REMEDIATION_LANE} T0-2 to apply the 10-min sudo cache) for full coverage.\n`
  );
}

// ============================================================================
// Main
// ============================================================================

function main() {
  let sudoersResult;
  let fsResult;
  try {
    sudoersResult = scanSudoersDir();
    fsResult = scanFilesystem();
  } catch (err) {
    process.stderr.write(
      `[M-4] INTERNAL ERROR: ${err && err.message ? err.message : String(err)}\n`
    );
    process.exit(1);
  }

  const allFindings = sudoersResult.findings.concat(fsResult.findings);
  const allEacces = sudoersResult.eaccesFiles.concat(fsResult.eaccesFiles);

  for (const f of allFindings) writeFinding(f);
  writePartialReadNotice(allEacces);

  if (allFindings.length > 0) {
    process.stderr.write(
      `[M-4] ${allFindings.length} violation(s) found. See ${REMEDIATION_LANE} for remediation steps.\n`
    );
    process.exit(2);
  }

  // Clean: silent unless --verbose was passed (kept for manual smoke runs).
  if (process.argv.includes("--verbose")) {
    process.stdout.write(
      `[M-4] OK — sudoers + filesystem invariants satisfied (${sudoersResult.findings.length + fsResult.findings.length} findings; ${allEacces.length} unreadable paths).\n`
    );
  }
  process.exit(0);
}

main();

"use strict";

// session-start.js — Claude Code SessionStart hook
// 1. Writes shell init commands to CLAUDE_ENV_FILE (PATH, direnv)
// 2. Validates hook scripts with node --check
// 3. Auto-registers agent row in {{PROJECT_NAME}} workboard
// 4. Prunes stale sessions (>4h)
//
// Placeholders:
//   {{PROJECT_DIR}}  — project root (e.g., ~/projects/MyApp)
//   {{PROJECT_NAME}} — project name (e.g., MyApp)
//
// Security: validates all paths before writing; never executes
// shell commands itself — only writes safe, deterministic shell
// snippets for bash to source later.

const { execFileSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const homeDir = os.homedir();
const envFile = process.env.CLAUDE_ENV_FILE;
if (!envFile) {
  // No env file means Claude Code doesn't need shell init.
  process.exit(0);
}

// --- Security: validate CLAUDE_ENV_FILE path ---
const resolvedEnvFile = path.resolve(envFile);
const tempDir = os.tmpdir();
const claudeSessionEnvDir = path.join(homeDir, ".claude", "session-env");
const inTempDir = resolvedEnvFile.startsWith(tempDir);
const inSessionEnvDir = resolvedEnvFile.startsWith(claudeSessionEnvDir);
if (!inTempDir && !inSessionEnvDir) {
  process.stderr.write(
    `session-start: CLAUDE_ENV_FILE outside allowed dirs: ${resolvedEnvFile}\n`
  );
  process.exit(1);
}

// --- Shell init: add ~/.local/bin to PATH ---
const lines = [];
const localBin = path.join(homeDir, ".local/bin");
if (fs.existsSync(localBin)) {
  lines.push(`export PATH="${localBin}:$PATH"`);
}

// --- direnv integration ---
const projectDir = process.env.CLAUDE_PROJECT_DIR;
if (projectDir) {
  const normalised = projectDir.replace(/\\/g, "/");
  if (/[;|&`$(){}!<>]/.test(normalised)) {
    process.stderr.write(
      `session-start: unsafe characters in CLAUDE_PROJECT_DIR\n`
    );
    process.exit(1);
  }
  lines.push(
    `cd "${normalised}" && command -v direnv >/dev/null 2>&1 && eval "$(timeout 5 direnv export bash 2>/dev/null)" || true`
  );
}

if (lines.length) {
  fs.appendFileSync(resolvedEnvFile, lines.join("\n") + "\n");
}

// --- Hook script validation ---
const hooksDir = path.dirname(__filename);
try {
  const scripts = fs.readdirSync(hooksDir).filter((f) => f.endsWith(".js"));
  const broken = [];
  for (const script of scripts) {
    const full = path.join(hooksDir, script);
    try {
      execFileSync("node", ["--check", full], { stdio: "pipe" });
    } catch {
      broken.push(script);
    }
  }
  if (broken.length > 0) {
    fs.appendFileSync(
      resolvedEnvFile,
      `echo "Warning: Hook syntax error(s): ${broken.join(", ")} — fix before session end"\n`
    );
  }
} catch {
  /* hooks dir missing — skip */
}

// =============================================================================
// Workboard registration
// =============================================================================

const STALE_MS = 4 * 60 * 60 * 1000; // 4 hours
const LOCK_TIMEOUT_MS = 2000;
const LOCK_RETRY_MS = 50;

// Resolve project root — {{PROJECT_DIR}} is rendered at setup time.
// At runtime, expand ~ to the actual home directory.
const PROJECT_ROOT = "{{PROJECT_DIR}}".replace(/^~/, homeDir);
const WORKBOARD = path.join(PROJECT_ROOT, ".claude/workboard.md");
const LOCK = WORKBOARD + ".lock";

function isPidAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function acquireLock() {
  const deadline = Date.now() + LOCK_TIMEOUT_MS;
  while (Date.now() < deadline) {
    try {
      const fd = fs.openSync(LOCK, "wx");
      fs.writeSync(fd, String(process.pid));
      fs.closeSync(fd);
      return true;
    } catch (err) {
      if (err.code !== "EEXIST") return false;
      try {
        const holderPid = parseInt(fs.readFileSync(LOCK, "utf8").trim(), 10);
        if (!isNaN(holderPid) && !isPidAlive(holderPid)) {
          fs.unlinkSync(LOCK);
          continue;
        }
      } catch {
        /* lock gone — retry */
      }
      const spinUntil = Date.now() + LOCK_RETRY_MS;
      while (Date.now() < spinUntil) {
        /* spin */
      }
    }
  }
  return false;
}

function releaseLock() {
  try {
    fs.unlinkSync(LOCK);
  } catch {
    /* non-fatal */
  }
}

function pruneStaleRows(contentLines) {
  const now = Date.now();
  return contentLines.filter((line) => {
    if (!line.startsWith("|")) return true;
    const parts = line.split("|");
    const cells = parts.slice(1, -1).map((c) => c.trim());
    if (cells.length < 6) return true;
    if (/^-+$/.test(cells[0])) return true; // separator row
    const ts = Date.parse(cells[5]);
    if (isNaN(ts)) return true;
    return now - ts <= STALE_MS;
  });
}

// --- Shared identity ---
const { getOwnId } = require("./lib/identity.js");

try {
  // Bail if the .claude directory doesn't exist yet
  if (!fs.existsSync(path.dirname(WORKBOARD))) process.exit(0);

  // Create workboard from template if it doesn't exist
  if (!fs.existsSync(WORKBOARD)) {
    const templatePath = path.join(path.dirname(__filename), "workboard.template.md");
    if (fs.existsSync(templatePath)) {
      fs.mkdirSync(path.dirname(WORKBOARD), { recursive: true });
      fs.copyFileSync(templatePath, WORKBOARD);
    } else {
      process.exit(0);
    }
  }

  const locked = acquireLock();
  if (!locked) process.exit(0);

  try {
    let content = fs.readFileSync(WORKBOARD, "utf8");
    const id = getOwnId();
    let contentLines = content.split("\n");

    // Prune stale rows
    contentLines = pruneStaleRows(contentLines);

    const now = new Date().toISOString().slice(0, 16) + "Z";
    const envDesc = process.env.CLAUDE_AGENT_ROLE || id;

    // Check if this session already has a row
    const existingIdx = contentLines.findIndex((line) => {
      if (!line.startsWith("|")) return false;
      const parts = line.split("|");
      const cells = parts.slice(1, -1).map((c) => c.trim());
      return cells.length >= 6 && cells[0] === id;
    });

    if (existingIdx >= 0) {
      // Row exists — update timestamp only
      const parts = contentLines[existingIdx].split("|");
      const cells = parts.slice(1, -1).map((c) => c.trim());
      cells[5] = now;
      contentLines[existingIdx] = "| " + cells.join(" | ") + " |";
    } else {
      // Insert new row after the Sessions table separator
      let insertIdx = -1;
      let inSessionsTable = false;
      for (let i = 0; i < contentLines.length; i++) {
        if (/sessions/i.test(contentLines[i]) && contentLines[i].startsWith("#")) {
          inSessionsTable = true;
        }
        if (inSessionsTable && /^\|[-\s|]+\|$/.test(contentLines[i])) {
          insertIdx = i + 1;
          break;
        }
      }
      const newRow = `| ${id} | ${envDesc} | ${now} | (starting) | — | ${now} |`;
      if (insertIdx >= 0) {
        contentLines.splice(insertIdx, 0, newRow);
      } else {
        // Fallback: append after last table row
        let lastTableRow = -1;
        for (let i = contentLines.length - 1; i >= 0; i--) {
          if (contentLines[i].startsWith("|")) {
            lastTableRow = i;
            break;
          }
        }
        if (lastTableRow >= 0) {
          contentLines.splice(lastTableRow + 1, 0, newRow);
        }
      }
    }

    // Atomic write
    const tmpPath = `${WORKBOARD}.tmp.${process.pid}`;
    fs.writeFileSync(tmpPath, contentLines.join("\n"), "utf8");
    fs.renameSync(tmpPath, WORKBOARD);
  } finally {
    releaseLock();
  }
} catch {
  /* non-fatal — never block session start */
}

process.exit(0);

"use strict";

// stop.js — Claude Code Stop hook
// 1. Validates hook scripts (node --check)
// 2. Warns about uncommitted changes
// 3. Removes agent row from workboard.md + prepends Recent entry
// 4. Emits handoff warning if in-flight files remain
// 5. Cleans up session cache
//
// Placeholders:
//   {{PROJECT_DIR}} — project root (e.g., ~/projects/MyApp)

const { execFileSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const homeDir = os.homedir();
const cwd = process.env.CLAUDE_WORKING_DIRECTORY || process.cwd();
const LOCK_TIMEOUT_MS = 2000;
const LOCK_RETRY_MS = 50;

// --- Hook script validation ---
const hooksDir = path.dirname(__filename);
try {
  const scripts = fs.readdirSync(hooksDir).filter((f) => f.endsWith(".js"));
  for (const script of scripts) {
    const full = path.join(hooksDir, script);
    try {
      execFileSync("node", ["--check", full], { stdio: "pipe" });
    } catch {
      console.log(`Warning: Hook syntax error: ${script}`);
    }
  }
} catch {
  /* hooks dir missing — skip */
}

// --- Uncommitted changes warning ---
try {
  const status = execFileSync("git", ["status", "--porcelain"], {
    cwd,
    stdio: ["pipe", "pipe", "pipe"],
  })
    .toString()
    .trim();
  if (status) {
    const count = status.split("\n").length;
    console.log(
      `Warning: ${count} uncommitted change${count > 1 ? "s" : ""} in ${cwd}`
    );
  }
} catch {
  /* not a git repo — silently skip */
}

// --- Shared identity ---
const { getOwnId, clearSessionCache } = require("./lib/identity.js");

// --- Workboard paths ---
const PROJECT_ROOT = "{{PROJECT_DIR}}".replace(/^~/, homeDir);
const WORKBOARD = path.join(PROJECT_ROOT, ".claude/workboard.md");
const LOCK = WORKBOARD + ".lock";

// --- File locking ---

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

// --- Workboard cleanup: remove row + prepend Recent entry ---

const agentId = getOwnId();

try {
  if (agentId && fs.existsSync(WORKBOARD)) {
    const locked = acquireLock();
    if (locked) {
      try {
        const content = fs.readFileSync(WORKBOARD, "utf8");
        const contentLines = content.split("\n");

        // Find and extract the session's row before removing it
        let taskDesc = "";
        let filesDesc = "";
        const filtered = contentLines.filter((line) => {
          if (!line.startsWith("|")) return true;
          const parts = line.split("|");
          const cells = parts.slice(1, -1).map((c) => c.trim());
          if (cells.length < 6 || /^-+$/.test(cells[0])) return true;
          if (cells[0] !== agentId) return true;
          // This is our row — capture task + files before dropping
          taskDesc = cells[3] || "";
          filesDesc = cells[4] || "";
          return false;
        });

        // Prepend a Recent entry if the agent did something beyond "(starting)"
        const hadWork = taskDesc && taskDesc !== "(starting)";
        if (hadWork) {
          const now = new Date();
          const dateStr = now.toISOString().slice(0, 10);
          const timeStr = now.toISOString().slice(11, 16);
          const hasFiles =
            filesDesc && filesDesc !== "\u2014" && filesDesc !== "";
          const filesNote = hasFiles ? ` (in-flight: ${filesDesc})` : "";
          const entry = `- [${dateStr} ${timeStr}] ${agentId}: ${taskDesc}${filesNote}`;

          const recentIdx = filtered.findIndex((l) => /^##\s+Recent/i.test(l));
          if (recentIdx >= 0) {
            filtered.splice(recentIdx + 1, 0, entry);
          }
        }

        const tmpPath = `${WORKBOARD}.tmp.${process.pid}`;
        fs.writeFileSync(tmpPath, filtered.join("\n"), "utf8");
        fs.renameSync(tmpPath, WORKBOARD);

        // Handoff warning — printed AFTER writing so it's visible in the terminal
        const hasInFlight =
          filesDesc && filesDesc !== "\u2014" && filesDesc !== "";
        if (hasInFlight) {
          console.log(
            `Warning: HANDOFF: ${agentId} stopped with in-flight files: ${filesDesc}`
          );
          console.log(
            `  Tag the next agent in the workboard Plans section.`
          );
        }
      } finally {
        releaseLock();
      }
    }
  }
} catch {
  /* non-fatal — never block session stop */
}

// --- Clean up session cache ---
clearSessionCache();

process.exit(0);

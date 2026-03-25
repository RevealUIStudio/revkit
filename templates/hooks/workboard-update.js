"use strict";

// workboard-update.js — Claude Code PostToolUse hook (Edit|Write)
// Stamps .claude/workboard.md with the file just edited.
// Updates the active session row's `files` and `updated` columns.
//
// Placeholders:
//   {{PROJECT_DIR}} — project root (e.g., ~/projects/MyApp)

const fs = require("fs");
const os = require("os");
const path = require("path");

const homeDir = os.homedir();
const MAX_FILES = 5;
const STALE_MS = 4 * 60 * 60 * 1000; // 4 hours
const LOCK_TIMEOUT_MS = 2000;
const LOCK_RETRY_MS = 50;

// --- Gate: only run for Edit or Write ---
const toolName = process.env.CLAUDE_TOOL_NAME || "";
if (!["Edit", "Write"].includes(toolName)) process.exit(0);

// --- Parse file path from tool input ---
let filePath = "";
try {
  filePath = JSON.parse(process.env.CLAUDE_TOOL_INPUT || "{}").file_path || "";
} catch {
  process.exit(0);
}
if (!filePath) process.exit(0);

// Normalise path separators
const normalised = filePath.replace(/\\/g, "/");

// Resolve project root — {{PROJECT_DIR}} is rendered at setup time.
const PROJECT_ROOT = "{{PROJECT_DIR}}".replace(/^~/, homeDir);

// Only track files within the project
if (!normalised.startsWith(PROJECT_ROOT)) process.exit(0);

// Relative path from project root
const relPath = normalised.slice(PROJECT_ROOT.length + 1);

// Don't self-update — prevent recursion on workboard edits
if (relPath.includes("workboard.md")) process.exit(0);

// --- Shared identity ---
const { getOwnId } = require("./lib/identity.js");

// --- Workboard / lock paths ---
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

function pruneStaleRows(contentLines) {
  const now = Date.now();
  return contentLines.filter((line) => {
    if (!line.startsWith("|")) return true;
    const parts = line.split("|");
    const cells = parts.slice(1, -1).map((c) => c.trim());
    if (cells.length < 6) return true;
    if (/^-+$/.test(cells[0])) return true;
    const ts = Date.parse(cells[5]);
    if (!isNaN(ts) && now - ts > STALE_MS) return false;
    return true;
  });
}

// --- Main ---

const sessionId = getOwnId();
if (!sessionId) process.exit(0);

// Bail if workboard doesn't exist (don't create it here)
if (!fs.existsSync(WORKBOARD)) process.exit(0);

const locked = acquireLock();
if (!locked) process.exit(0);

try {
  let workboard;
  try {
    workboard = fs.readFileSync(WORKBOARD, "utf8");
  } catch {
    process.exit(0);
  }

  const now = new Date().toISOString().slice(0, 16) + "Z";
  let contentLines = workboard.split("\n");

  // Prune stale rows
  contentLines = pruneStaleRows(contentLines);

  // Update the session's row
  let updated = false;
  for (let i = 0; i < contentLines.length; i++) {
    const line = contentLines[i];
    if (!line.startsWith("|")) continue;
    const parts = line.split("|");
    const cells = parts.slice(1, -1).map((c) => c.trim());
    if (cells.length < 6) continue;
    if (cells[0] !== sessionId) continue;

    // Merge new file into files column (deduplicate, keep last MAX_FILES)
    const existing = cells[4]
      .split(",")
      .map((f) => f.trim())
      .filter(Boolean);
    if (!existing.includes(relPath)) existing.push(relPath);
    const trimmed = existing.slice(-MAX_FILES);

    cells[4] = trimmed.join(", ");
    cells[5] = now;
    contentLines[i] = "| " + cells.join(" | ") + " |";
    updated = true;
    break;
  }

  if (!updated) process.exit(0);

  // Atomic write
  const tmpPath = `${WORKBOARD}.tmp.${process.pid}`;
  fs.writeFileSync(tmpPath, contentLines.join("\n"), "utf8");
  fs.renameSync(tmpPath, WORKBOARD);
} finally {
  releaseLock();
}

process.exit(0);

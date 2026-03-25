"use strict";

// workboard-inject.js — Claude Code UserPromptSubmit hook
// 1. Reads user prompt from stdin → auto-updates own task column in workboard
// 2. Outputs compact summary of other active agents → injected as context
//
// Both steps happen automatically on every user message.
//
// Placeholders:
//   {{PROJECT_DIR}}  — project root (e.g., ~/projects/MyApp)

const fs = require("fs");
const os = require("os");
const path = require("path");

const homeDir = os.homedir();
const STALE_MS = 4 * 60 * 60 * 1000; // 4 hours
const LOCK_TIMEOUT_MS = 1000; // shorter timeout for high-frequency hook
const LOCK_RETRY_MS = 30;

// --- Shared identity ---
const { getOwnId } = require("./lib/identity.js");

// --- Workboard path ---
const PROJECT_ROOT = "{{PROJECT_DIR}}".replace(/^~/, homeDir);
const WORKBOARD = path.join(PROJECT_ROOT, ".claude/workboard.md");
const LOCK = WORKBOARD + ".lock";

// --- Read user prompt from stdin ---
// Claude Code pipes UserPromptSubmit data as JSON to stdin and closes it.
let userPrompt = "";
try {
  const stat = fs.fstatSync(0); // fd 0 = stdin
  if (stat.isFIFO() || stat.isSocket()) {
    const raw = fs.readFileSync("/dev/stdin", "utf8").trim();
    if (raw) {
      const parsed = JSON.parse(raw);
      let text =
        parsed.prompt ??
        parsed.message ??
        parsed.userPrompt ??
        "";
      // If messages array, take the last user message.
      if (!text && Array.isArray(parsed.messages)) {
        const last = [...parsed.messages].reverse().find((m) => m.role === "user");
        if (last) {
          text = typeof last.content === "string"
            ? last.content
            : JSON.stringify(last.content);
        }
      }
      if (typeof text === "string") {
        userPrompt = text.trim().slice(0, 80);
      }
    }
  }
} catch {
  /* stdin not available, not a pipe, or not JSON */
}

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

// --- Main logic ---

const ownId = getOwnId();
if (!ownId) process.exit(0);

let workboard;
try {
  workboard = fs.readFileSync(WORKBOARD, "utf8");
} catch {
  process.exit(0);
}

// Step 1: Update own task column
if (userPrompt) {
  const locked = acquireLock();
  if (locked) {
    try {
      // Re-read inside the lock
      let content;
      try {
        content = fs.readFileSync(WORKBOARD, "utf8");
      } catch {
        content = workboard;
      }

      const now = new Date().toISOString().slice(0, 16) + "Z";
      const contentLines = content.split("\n");
      let updated = false;

      for (let i = 0; i < contentLines.length; i++) {
        if (!contentLines[i].startsWith("|")) continue;
        const cells = contentLines[i].split("|").slice(1, -1).map((c) => c.trim());
        if (cells.length < 6 || /^-+$/.test(cells[0])) continue;
        if (!/^\d{4}-\d{2}-\d{2}/.test(cells[5])) continue; // skip header
        if (cells[0] !== ownId) continue;

        const taskLabel = userPrompt + (userPrompt.length >= 80 ? "..." : "");
        cells[3] = taskLabel;
        cells[5] = now;
        contentLines[i] = "| " + cells.join(" | ") + " |";
        updated = true;
        break;
      }

      if (updated) {
        const tmpPath = `${WORKBOARD}.tmp.${process.pid}`;
        fs.writeFileSync(tmpPath, contentLines.join("\n"), "utf8");
        fs.renameSync(tmpPath, WORKBOARD);
        workboard = contentLines.join("\n");
      }
    } finally {
      releaseLock();
    }
  }
}

// Step 2: Output other agents' status for context injection
const now = Date.now();
const otherAgents = [];

for (const line of workboard.split("\n")) {
  if (!line.startsWith("|")) continue;
  const cells = line.split("|").slice(1, -1).map((c) => c.trim());
  if (cells.length < 6 || /^-+$/.test(cells[0])) continue;
  if (!/^\d{4}-\d{2}-\d{2}/.test(cells[5])) continue; // skip header
  if (cells[0] === ownId) continue;

  const ts = Date.parse(cells[5]);
  if (!isNaN(ts) && now - ts > STALE_MS) continue;

  otherAgents.push({ id: cells[0], task: cells[3], files: cells[4] });
}

if (otherAgents.length > 0) {
  const output = ["[workboard] Other active agents:"];
  for (const a of otherAgents) {
    const filesNote = a.files && a.files !== "\u2014" ? ` (files: ${a.files})` : "";
    output.push(`  ${a.id}: ${a.task}${filesNote}`);
  }
  process.stdout.write(output.join("\n") + "\n");
}

process.exit(0);

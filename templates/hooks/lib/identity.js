"use strict";

// identity.js — Shared session identity module (CJS)
// Generic version for any project. Detects the current agent identity
// using a 3-tier cascade: env var → session cache → hostname fallback.
//
// Placeholder: {{PROJECT_NAME}} — replaced by render.sh at setup time.

const os = require("os");
const path = require("path");
const fs = require("fs");

const CACHE_EXPIRE_MS = 8 * 60 * 60 * 1000; // 8 hours

/**
 * Path to the session ID cache file.
 * @param {number} [ppid] — parent process ID (defaults to process.ppid)
 * @returns {string}
 */
function sessionIdFile(ppid) {
  return path.join(os.tmpdir(), `devkit-session-${ppid || process.ppid || "0"}.id`);
}

/**
 * Read a cached session ID, returning null if absent or expired.
 * @param {number} [ppid]
 * @returns {string|null}
 */
function readSessionCache(ppid) {
  try {
    const raw = fs.readFileSync(sessionIdFile(ppid), "utf8").trim();
    const lines = raw.split("\n");
    if (lines.length >= 2) {
      const id = lines[0].trim();
      const ts = parseInt(lines[1].trim(), 10);
      if (!isNaN(ts) && Date.now() - ts < CACHE_EXPIRE_MS) return id;
      return null;
    }
    // Legacy single-line format
    const id = lines[0].trim();
    if (/^[a-z][\w-]{0,30}$/.test(id)) return id;
  } catch {
    /* not found */
  }
  return null;
}

/**
 * Write a session ID to the cache.
 * @param {number|undefined} ppid
 * @param {string} id
 */
function writeSessionCache(ppid, id) {
  try {
    fs.writeFileSync(sessionIdFile(ppid), `${id}\n${Date.now()}`, "utf8");
  } catch {
    /* non-fatal */
  }
}

/**
 * Remove the session cache file.
 * @param {number} [ppid]
 */
function clearSessionCache(ppid) {
  try {
    fs.unlinkSync(sessionIdFile(ppid));
  } catch {
    /* non-fatal */
  }
}

/**
 * Get own session ID — fast path (3-tier cascade).
 *
 * 1. Explicit CLAUDE_AGENT_ROLE env var
 * 2. Session cache (written by session-start)
 * 3. Fallback: hostname-derived ID
 *
 * @returns {string}
 */
function getOwnId() {
  // Tier 1: Explicit env var
  const role = (process.env.CLAUDE_AGENT_ROLE || "").trim();
  if (role) return role;

  // Tier 2: Session cache
  const cached = readSessionCache();
  if (cached) return cached;

  // Tier 3: Default to hostname + pid
  const id = `agent-${os.hostname().split(".")[0]}`;
  try {
    writeSessionCache(undefined, id);
  } catch {
    /* non-fatal */
  }
  return id;
}

module.exports = {
  getOwnId,
  readSessionCache,
  writeSessionCache,
  clearSessionCache,
  sessionIdFile,
};

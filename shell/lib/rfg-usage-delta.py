#!/usr/bin/env python3
"""Compare grok usage JSON for an rfg session vs a bare grok session (GAP-496)."""

from __future__ import annotations

import json
import subprocess
import sys


def grok_usage(sid: str) -> dict:
    proc = subprocess.run(
        ["grok", "usage", sid],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise SystemExit(f"rfg usage-delta: grok usage {sid} failed: {proc.stderr.strip() or proc.returncode}")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"rfg usage-delta: not JSON from grok usage {sid}: {exc}") from exc


def token_total(blob: dict) -> int:
    session = blob.get("session") if isinstance(blob.get("session"), dict) else blob
    keys = (
        "input_tokens",
        "output_tokens",
        "total_tokens",
        "prompt_tokens",
        "completion_tokens",
    )
    if isinstance(session.get("total_tokens"), (int, float)):
        return int(session["total_tokens"])
    total = 0
    found = False
    for k in keys:
        v = session.get(k)
        if isinstance(v, (int, float)):
            total += int(v)
            found = True
    if found:
        return total
    usage = session.get("usage") if isinstance(session.get("usage"), dict) else {}
    for k in keys:
        v = usage.get(k)
        if isinstance(v, (int, float)):
            total += int(v)
            found = True
    return total if found else -1


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: rfg usage-delta <rfg-session-id> [bare-grok-session-id]")
    rfg_sid = sys.argv[1]
    bare_sid = sys.argv[2] if len(sys.argv) > 2 else ""
    rfg_blob = grok_usage(rfg_sid)
    rfg_n = token_total(rfg_blob)
    print(f"rfg\t{rfg_sid}\t{rfg_n}")
    if not bare_sid:
        print("pass a bare grok session id as the second arg to print the delta")
        return
    bare_blob = grok_usage(bare_sid)
    bare_n = token_total(bare_blob)
    print(f"grok\t{bare_sid}\t{bare_n}")
    if rfg_n < 0 or bare_n < 0:
        print("delta\tunavailable (usage JSON missing token totals)")
        return
    print(f"delta\t{rfg_n - bare_n}")
    print("quality mapping is owner-side: same prompt in, compare outputs by hand")


if __name__ == "__main__":
    main()

#!/usr/bin/env bash
# GitHub disables scheduled workflows after 60 days without repo activity. The
# watchdog would switch itself off silently — the exact failure mode this whole
# exercise exists to remove. A weekly commit keeps the schedule alive.
set -uo pipefail
STAMP="last-run.txt"
LAST=$(git log -1 --format=%ct -- "$STAMP" 2>/dev/null || echo 0)
[ -z "$LAST" ] && LAST=0
[ $(($(date +%s) - LAST)) -lt 604800 ] && exit 0
date -u '+%Y-%m-%dT%H:%M:%SZ' >"$STAMP"
git config user.name "vm-watchdog"
git config user.email "watchdog@users.noreply.github.com"
git add "$STAMP" && git commit -m "keepalive: keep the scheduled watchdog enabled" && git push || true

#!/usr/bin/env bash
# Is the browser actually drivable?
#
# The relay answers `initialize` with a healthy 200 even when the Chrome
# extension is detached and no browser work is possible at all. `tools/list` is
# the call that tells the truth: a detached extension returns "Unknown remote
# session id" and zero tools.
#
# That gap — component healthy, capability dead — is the shape of every outage
# this week: a token that was installed but blank, a socket that was open but
# mute, a CDP port that was configured while adb held it. So this checks what a
# caller actually needs, not whether a server is up.
set -uo pipefail

[ -n "${URL:-}" ] || { echo "VIBE_MCP_URL not set"; exit 0; }

send() {
  [ -n "${TG_TOKEN:-}" ] && [ -n "${TG_CHAT:-}" ] || return 0
  curl -s --max-time 20 -o /dev/null \
    "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TG_CHAT}" \
    --data-urlencode "text=$1" --data-urlencode "parse_mode=Markdown" || true
}
getvar() { gh api "/repos/$REPO/actions/variables/$1" --jq .value 2>/dev/null || echo ""; }
setvar() {
  gh api -X PATCH "/repos/$REPO/actions/variables/$1" -f "name=$1" -f "value=$2" >/dev/null 2>&1 ||
    gh api -X POST "/repos/$REPO/actions/variables" -f "name=$1" -f "value=$2" >/dev/null 2>&1
}

# Never echo $URL: it is a credential that grants control of Dan's browser.
count_tools() {
  curl -s --max-time 25 -X POST "$URL" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' 2>/dev/null |
    python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read() or '{}')
except Exception:
    print(-1); raise SystemExit
print(0 if d.get('error') else len((d.get('result') or {}).get('tools') or []))
" 2>/dev/null || echo -1
}

n=$(count_tools)
echo "tools exposed: $n"
was_down=$(getvar VIBE_DOWN)

if [ "${n:-0}" -gt 0 ]; then
  echo "browser reachable"
  if [ "$was_down" = "1" ]; then
    setvar VIBE_DOWN 0
    send "✅ *Vibe browser is reachable again* — ${n} tools exposed."
  fi
  exit 0
fi

# Confirm once: a single failed probe during a Chrome restart is not an outage.
sleep 60
n=$(count_tools)
echo "second probe: $n"
if [ "${n:-0}" -gt 0 ]; then echo "recovered on second probe"; exit 0; fi

if [ "$was_down" = "1" ]; then echo "still detached, already alerted"; exit 0; fi
setvar VIBE_DOWN 1
send "🔻 *The browser agent cannot reach Chrome.* The Vibe relay answers, but the extension is detached — every browser task fails silently. Fix: open the Vibe extension settings, toggle *Enable external AI agent control* off and on; if it stays on \"waiting\", reload the extension at chrome://extensions."
exit 1

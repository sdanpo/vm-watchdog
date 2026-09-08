#!/usr/bin/env bash
# Cloud watchdog for the WhatsApp bot VM. See .github/workflows/watchdog.yml.
#
# ICMP is blocked on GitHub runners, so liveness is a TCP connect to sshd.
# That is a deliberately shallow check: this layer answers "is the machine on
# the network at all", which is exactly the failure it exists for. Bot-level
# health belongs to the on-VM liveness script and the Mac watchdog, both of
# which can only work when the machine is actually up.
set -uo pipefail

PORT="${PORT:-22}"

tg() {
  [ -n "${TG_TOKEN:-}" ] && [ -n "${TG_CHAT:-}" ] || return 0
  curl -s --max-time 20 -o /dev/null \
    "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TG_CHAT}" \
    --data-urlencode "text=$1" --data-urlencode "parse_mode=Markdown" || true
}

alive() { timeout 8 bash -c "</dev/tcp/$VM_IP/$PORT" >/dev/null 2>&1; }

vultr() {
  curl -s --max-time 25 -X "$1" -H "Authorization: Bearer $VULTR" \
    -H "Content-Type: application/json" "https://api.vultr.com/v2$2"
}

# Cooldown state lives in repo variables: no database to run, and a human who
# wonders what this thing has been doing can read it in the repo settings.
getvar() { gh api "/repos/$REPO/actions/variables/$1" --jq .value 2>/dev/null || echo ""; }
setvar() {
  gh api -X PATCH "/repos/$REPO/actions/variables/$1" -f "name=$1" -f "value=$2" >/dev/null 2>&1 ||
    gh api -X POST "/repos/$REPO/actions/variables" -f "name=$1" -f "value=$2" >/dev/null 2>&1
}

if alive; then
  echo "VM reachable"
  if [ "$(getvar WD_DOWN)" = "1" ]; then
    setvar WD_DOWN 0
    tg "✅ *VM is back up.*"
  fi
  exit 0
fi

# Confirm before acting. One dropped connect is not an outage, and a runner with
# flaky egress must never be able to reboot a healthy server.
echo "first probe failed; confirming"
sleep 45
if alive; then echo "recovered on second probe"; exit 0; fi
sleep 45
if alive; then echo "recovered on third probe"; exit 0; fi

now=$(date +%s)
last=$(getvar WD_LAST_REBOOT); last=${last:-0}
count=$(getvar WD_COUNT_24H);  count=${count:-0}
window=$(getvar WD_WINDOW_START); window=${window:-$now}
[ $((now - window)) -gt 86400 ] && { count=0; window=$now; }

if [ "${count:-0}" -ge 4 ]; then
  tg "🚨 *VM down and the watchdog is NOT rebooting.* ${count} reboots in 24h — rebooting is not fixing this. Open the Vultr console **before** rebooting; that is the only way to see the cause."
  exit 1
fi

if [ $((now - last)) -lt 1200 ]; then
  echo "cooldown active"
  exit 0
fi

state=$(vultr GET "/instances/$VM_ID" | python3 -c "
import sys, json
try:
    i = json.load(sys.stdin).get('instance', {})
    print('power=%s server=%s' % (i.get('power_status'), i.get('server_status')))
except Exception:
    print('unreadable')")
echo "pre-reboot vultr: $state"
tg "🔧 *VM unreachable — rebooting from the cloud watchdog.* Vultr reports: \`$state\`"

vultr POST "/instances/$VM_ID/reboot" >/dev/null
setvar WD_LAST_REBOOT "$now"
setvar WD_COUNT_24H "$((count + 1))"
setvar WD_WINDOW_START "$window"
setvar WD_DOWN 1

for _ in $(seq 1 40); do
  sleep 15
  if alive; then
    tg "✅ *Bot VM revived automatically* (cloud watchdog). Back on the network."
    setvar WD_DOWN 0
    echo "recovered"
    exit 0
  fi
done

tg "🚨 *Reboot did not bring the VM back* — still dark 10 minutes later. Needs you."
exit 1

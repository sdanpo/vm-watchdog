# VM watchdog

Watches a single Vultr instance and reboots it if it stops answering on the
network. It exists because that machine has twice gone completely dark while
Vultr's own control plane still reported `power=running server=ok`, and because
the two earlier watchdogs each had a blind spot: one ran *on* the machine that
was failing, the other on a laptop that is often asleep.

This one runs on GitHub's infrastructure, every 5 minutes.

- Confirms across three probes ~45s apart before acting — a single dropped
  connect is not an outage.
- 20-minute cooldown, 4 reboots per 24h. Past the cap it refuses to reboot and
  asks for a human, because a reboot that needs repeating is not a fix.
- Records the control-plane state *before* rebooting, so the evidence survives
  the action that would otherwise destroy it.

No credentials live in this repository. All of them are GitHub Secrets:
`VM_IP`, `VM_ID`, `VULTR_TOKEN`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`.

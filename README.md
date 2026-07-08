# cctop

AI usage and cost monitor for the KDE Plasma panel. Tracks what your AI coding
tools are really costing you — live Claude Code session limits, monthly spend
per provider and your subscriptions — with **100% local data**: no accounts,
no API keys, no telemetry.

## Features

- **Panel indicator** — live Claude session usage % (green → yellow → red),
  today's spend or subscriptions total (configurable)
- **Monthly spend** per provider with stacked bar and legend
- **Last 7 days** bar chart
- **Live limits** — current 5h session (%, reset time, model in use), weekly
  all-models and weekly top-model limits, straight from the same endpoint the
  Claude Code `/usage` command uses (via the OAuth token the CLI already
  stores locally)
- **Recent sessions** — last sessions with model and cost
- **Subscription auto-detection** — your Claude plan (Pro / Max 5x / Max 20x)
  and your ChatGPT plan (Plus / Pro / Team, from the Codex CLI login) are read
  from local CLI files
- **Monthly budget** — optional limit with progress bar and a notification
  when the spend crosses it
- **Privacy mode** — the eye button masks every money value (panel included)
- **Desktop notification** when the session crosses a configurable threshold
- **Scroll on the panel widget** to cycle session % / spend today / subscriptions
- **Languages**: English, Português (Brasil), Español

### Providers

| Provider | Source |
|---|---|
| Claude (Claude Code) | local JSONL logs + local OAuth token |
| OpenAI (Codex CLI) | local session logs (`~/.codex`) |
| Gemini (Gemini CLI) | local telemetry log (`~/.gemini`) |

Providers appear automatically when their CLI is used on the machine.

## Requirements

- KDE Plasma 6
- `jq`, `curl`
- Node.js **or** Bun (used to run [ccusage](https://github.com/ryoppippi/ccusage))
- [Claude Code](https://claude.com/claude-code) for the Claude data

## Install

From the KDE Store: right-click your panel → *Add Widgets* → *Get New Widgets* → search **cctop**.

Manual:

```sh
git clone https://github.com/nventatech-tech/cctop.git
kpackagetool6 --type Plasma/Applet --install cctop
```

Then add the **cctop** widget to your panel.

## Configuration

Right-click the widget → *Configure cctop*: language, what the panel label
shows, notification threshold, monthly budget and refresh interval.

## Donate

If cctop is useful to you, you can support development — the ❤ button in the
widget, [this PayPal link](https://www.paypal.com/donate/?business=SR28XBBCYSPHE&no_recurring=0&item_name=Help+me+buy+a+coffee.&currency_code=USD)
or the QR code:

<img src="contents/images/donate-qr.png" width="140" alt="PayPal donation QR code">

## License

[GPL-3.0-or-later](LICENSE) — © 2026 NventaTech

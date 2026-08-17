# grok-notify

A Grok plugin that plays a sound and sends a desktop notification when:

- **Grok finishes a turn** → "Task complete" sound + notification
- **Grok needs your input** (permission prompt, MCP elicitation) → "Needs your input" sound + notification

Zero extra dependencies. Uses built-in OS sounds (`/System/Library/Sounds/` on macOS, `C:\Windows\Media\` on Windows). Needs `jq` on `$PATH`.

Grok has the same style of lifecycle hooks as Claude Code (`Stop`, `Notification`, …). This is the Grok counterpart of [`claude-notify`](../claude-notify).

## What it hooks

| When | Grok event | Sound (macOS) | Notification |
|---|---|---|---|
| Turn actually finished | `Stop` with `reason == end_turn` | `Glass.aiff` | Task complete |
| Waiting on you | `Notification` (`permission_prompt`, `agent_needs_input`, `elicitation_dialog`) | `Tink.aiff` | Needs your input |

Not hooked on purpose:

- `idle_prompt` — Grok fires this about a minute after the session goes idle; it would double with `Stop`
- `SubagentStop` — too noisy
- Session-end `Stop` (`channel_closed` / `shutdown`) — script ignores those reasons

`Stop` is a **gate**. This script always exits 0 and never prints a `decision`, so it will not keep the agent working.

There is a second, TUI-only path (`[[ui.notifications.hooks]]` in `config.toml`) with events like `turn_complete`. This plugin uses lifecycle hooks instead, so it also works when the terminal is focused.

## Install

### Recommended: user plugin (auto-trusted)

`~/.grok/plugins/` is scanned for every project and trusted automatically:

```bash
mkdir -p ~/.grok/plugins
ln -sfn /Users/FireTable/OpenClaw/Code/grok-notify ~/.grok/plugins/grok-notify
```

Restart Grok, or open `/hooks` and press `r`. You should see two Plugin hooks: `Stop` and `Notification`.

Copy instead of symlink if you do not want live edits:

```bash
cp -R /Users/FireTable/OpenClaw/Code/grok-notify ~/.grok/plugins/grok-notify
```

### Manual: global hook file

```bash
mkdir -p ~/.grok/hooks
chmod +x hooks/notify.sh
```

`~/.grok/hooks/grok-notify.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "/Users/FireTable/OpenClaw/Code/grok-notify/hooks/notify.sh", "timeout": 5 }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|agent_needs_input|elicitation_dialog",
        "hooks": [
          { "type": "command", "command": "/Users/FireTable/OpenClaw/Code/grok-notify/hooks/notify.sh", "timeout": 5 }
        ]
      }
    ]
  }
}
```

Use **either** the plugin **or** this JSON, not both — sources merge and you will hear two chimes.

## Verify

```bash
# Task complete
echo '{"hookEventName":"stop","reason":"end_turn"}' | ~/.grok/plugins/grok-notify/hooks/notify.sh

# Needs input
echo '{"hookEventName":"notification","notificationType":"permission_prompt"}' | ~/.grok/plugins/grok-notify/hooks/notify.sh
```

You should hear a chime and see a desktop notification titled **Grok**.

## Troubleshooting

| Platform | Issue | Fix |
|---|---|---|
| macOS | No notification banner | System Settings → Notifications → grant Terminal / iTerm / the host app |
| macOS | `jq: command not found` | `brew install jq` |
| Both | Hook never fires | Confirm `~/.grok/plugins/grok-notify` exists; `/hooks` → reload (`r`); restart Grok |
| Both | Two sounds per turn | Installed as plugin **and** `~/.grok/hooks/grok-notify.json` |
| Both | Agent keeps talking after the chime | An old Stop hook is returning `block` / exit 2. This script must stay exit 0 |
| Grok | Almost no "needs input" sound | `[ui] permission_mode = "always-approve"` (or yolo) skips the permission UI. Complete chime still fires |
| Both | Edits not taking effect | Copy-install: re-copy. Symlink: reload `/hooks` |

## Files

```
grok-notify/
├── plugin.json                 # plugin metadata
├── hooks/
│   ├── hooks.json              # Stop + Notification
│   └── notify.sh               # the only code
├── skills/
│   └── grok-notify/
│       └── SKILL.md            # AI-facing install + verify guide
└── README.md
```

## Sounds used

| Scenario | macOS | Windows |
|---|---|---|
| Task complete | `Glass.aiff` (clear tap) | `chimes.wav` |
| Needs input | `Tink.aiff` (short tick) | `ding.wav` |

Swap by editing `notify.sh`.

## License

MIT.

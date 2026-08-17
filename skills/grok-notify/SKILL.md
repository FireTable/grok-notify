---
name: grok-notify
description: Install and troubleshoot the grok-notify plugin (sound + OS notification when Grok finishes a turn or needs input). Use when the user asks to "set up Grok notifications", "make Grok play a sound", "alert me when Grok is done", or asks why the plugin isn't working.
---

# grok-notify

Plays a sound + sends a desktop notification when:

- **Grok finishes a turn** (`Stop`, `reason == end_turn`) → "Task complete" + Glass
- **Grok needs human input** (`Notification`: `permission_prompt`, `agent_needs_input`, `elicitation_dialog`) → "Needs your input" + Tink

Does **not** hook `idle_prompt` (fires ~1 minute later and would double with `Stop`) or `SubagentStop` (too noisy).

Supported: macOS (`afplay` + `osascript`), Windows (`SoundPlayer` + WinRT Toast). No dependencies. Requires `jq`.

## Install

**Recommended — symlink into user plugins (auto-trusted, live edits):**

```bash
git clone git@github.com:FireTable/grok-notify.git
mkdir -p ~/.grok/plugins
ln -sfn "$(pwd)/grok-notify" ~/.grok/plugins/grok-notify
```

If the repo is already checked out, `ln -sfn "$(pwd)" ~/.grok/plugins/grok-notify` from inside it.

Then restart Grok, or press `r` in `/hooks`. Confirm the plugin appears under Plugin hooks.

**Copy instead of symlink:**

```bash
mkdir -p ~/.grok/plugins
cp -R grok-notify ~/.grok/plugins/grok-notify
```

Re-copy after source edits.

**Manual (global hook file, no plugin discovery):**

1. `chmod +x hooks/notify.sh`
2. Write `~/.grok/hooks/grok-notify.json` pointing `command` at the absolute path of `hooks/notify.sh` for `Stop` and `Notification` (same matcher as `hooks/hooks.json`).
3. Restart Grok or reload hooks.

Do not also install as a plugin if you use the global JSON — both sources merge and the sound fires twice.

## Critical install-path notes

- `~/.grok/plugins/<name>/` **is** auto-discovered and auto-trusted. This is the opposite of Claude Code's `~/.claude/plugins/`.
- Project plugins in `<repo>/.grok/plugins/` need `/hooks-trust`.
- `Stop` is a gate. `notify.sh` must exit 0 and print no `{"decision":"block"}` JSON, or Grok keeps working.

## Verify

```bash
# Task complete — Glass.aiff + "Task complete"
echo '{"hookEventName":"stop","reason":"end_turn"}' | ~/.grok/plugins/grok-notify/hooks/notify.sh

# Needs input — Tink.aiff + "Needs your input"
echo '{"hookEventName":"notification","notificationType":"permission_prompt"}' | ~/.grok/plugins/grok-notify/hooks/notify.sh
```

On macOS, if no banner: System Settings → Notifications → grant Terminal / iTerm / the app that launched Grok.

If hooks never fire: `/hooks` → check Plugin group is loaded and enabled. Session must be restarted after the first install.

## Troubleshoot

| Symptom | Likely cause | Fix |
|---|---|---|
| Hook never fires after install | Plugin not under `~/.grok/plugins/` | Symlink or copy there; restart Grok |
| Two sounds per turn | Installed as both plugin and `~/.grok/hooks/*.json` | Keep one source |
| Sound but agent keeps going | Old script printed Stop-gate JSON / exit 2 | Use this repo's `notify.sh`; it always exits 0 |
| No sound, no notification | `jq` missing | `brew install jq` |
| macOS notification silent | Terminal not granted permission | System Settings → Notifications |
| `always-approve` / yolo | Permission UI never appears | `needs_input` almost never fires; complete chime still should |
| Want `idle_prompt` too | Personal preference | Add it to the Notification matcher in `hooks/hooks.json` |
| Want different sounds | Personal preference | Edit the `afplay` / `SoundPlayer` lines in `notify.sh` |

## Do NOT do (without explicit user request)

- Register `SubagentStop`, `idle_prompt`, `StopFailure`, or `StopCancelled`
- Add TTS / webhook / ntfy / `ui.notifications.hooks` in `config.toml`
- Install the same script in both `~/.grok/plugins/` and `~/.grok/hooks/`
- Emit Stop-gate JSON from `notify.sh`

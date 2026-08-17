#!/usr/bin/env bash
# notify.sh — Grok hook: play sound + send OS notification
#
# Triggered by: Stop (turn complete) and Notification (needs human input)
# Reads hook JSON from stdin. Optional $1 override: "task_complete" | "needs_input"
# Platforms: macOS (afplay + osascript), Windows (SoundPlayer + WinRT Toast)
#
# Stop is a Grok gate. This script must exit 0 and print no decision JSON,
# or it will keep the agent working.

set -uo pipefail

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hookEventName // .hook_event_name // empty' 2>/dev/null)
[[ -z "$EVENT" ]] && EVENT="${GROK_HOOK_EVENT:-}"

NOTIF_TYPE=$(printf '%s' "$INPUT" | jq -r '.notificationType // .notification_type // empty' 2>/dev/null)
REASON=$(printf '%s' "$INPUT" | jq -r '.reason // empty' 2>/dev/null)
SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.subagentType // .subagent_type // empty' 2>/dev/null)

# Subagent stops are not the session going idle.
[[ -n "$SUBAGENT" ]] && exit 0

SCENARIO=""
case "$EVENT" in
    Stop|stop)
        # Genuine completion only. Session-end Stop uses channel_closed / shutdown.
        if [[ -z "$REASON" || "$REASON" == "end_turn" ]]; then
            SCENARIO="task_complete"
        fi
        ;;
    Notification|notification)
        case "$NOTIF_TYPE" in
            permission_prompt|agent_needs_input|elicitation_dialog)
                SCENARIO="needs_input"
                ;;
        esac
        ;;
esac

# Manual override for testing: ./notify.sh task_complete
[[ -n "${1:-}" ]] && SCENARIO="$1"

if [[ -z "$SCENARIO" ]]; then
    exit 0
fi

UNAME=$(uname -s)

notify_macos() {
    local sound="$1" title="$2" msg="$3"
    afplay -v 2.0 "$sound" &>/dev/null &
    osascript -e "display notification \"$msg\" with title \"$title\"" &>/dev/null &
}

notify_windows() {
    local sound="$1" title="$2" msg="$3"
    powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "
        (New-Object Media.SoundPlayer '$sound').Play();
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null;
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null;
        \$xml = New-Object Windows.Data.Xml.Dom.XmlDocument;
        \$xml.LoadXml('<toast duration=\"short\"><visual><binding template=\"ToastGeneric\"><text>$title</text><text>$msg</text></binding></visual></toast>');
        \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml);
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Grok').Show(\$toast);
    " &>/dev/null &
}

case "$UNAME" in
    Darwin)
        if [[ "$SCENARIO" == "task_complete" ]]; then
            notify_macos "/System/Library/Sounds/Glass.aiff" "Grok" "Task complete"
        else
            notify_macos "/System/Library/Sounds/Tink.aiff" "Grok" "Needs your input"
        fi
        ;;
    MINGW*|CYGWIN*|MSYS*)
        if [[ "$SCENARIO" == "task_complete" ]]; then
            notify_windows 'C:\Windows\Media\chimes.wav' "Grok" "Task complete"
        else
            notify_windows 'C:\Windows\Media\ding.wav' "Grok" "Needs your input"
        fi
        ;;
    *)
        exit 0
        ;;
esac

exit 0

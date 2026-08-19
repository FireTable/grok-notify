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

# Skip when launched from inside Cindy: Cindy orchestrates multiple agents and shows its own status, no need for OS notification + sound.
[[ "${CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST:-0}" == "1" || "${__CFBundleIdentifier:-}" == "com.xd.cindycn" ]] && exit 0

UNAME=$(uname -s)

notify_macos() {
    # ponytail: afplay lives in play_sequence now; this fn only fires the OS notification.
    local sound="$1" title="$2" msg="$3"
    osascript -e "display notification \"$msg\" with title \"$title\"" &>/dev/null &
}

# Layered 2-note sequence for brand-distinctive Grok chime (downward for complete, sonar-then-ping for input).
# ponytail: 2 layered system sounds beats 1 custom file; add per-agent .aiff when these still sound alike.
play_sequence() {
    local s1="$1" gap="$2" s2="$3"
    afplay -v 2.0 "$s1" &>/dev/null &
    ( sleep "$gap"; afplay -v 2.0 "$s2" &>/dev/null ) &
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
            play_sequence "/System/Library/Sounds/Sosumi.aiff" 0.25 "/System/Library/Sounds/Glass.aiff"
            notify_macos "" "Grok" "Task complete"
        else
            play_sequence "/System/Library/Sounds/Submarine.aiff" 0.20 "/System/Library/Sounds/Tink.aiff"
            notify_macos "" "Grok" "Needs your input"
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

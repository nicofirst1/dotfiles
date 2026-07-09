#!/usr/bin/env bash
# Close every macOS Space that has zero windows.
#
# Uses the Accessibility API to drive Mission Control. Does NOT require
# yabai, scripting additions, or disabling SIP.
#
# One-time setup:
#   System Settings -> Privacy & Security -> Accessibility
#   Add (and enable) the terminal app you'll run this from (Terminal,
#   iTerm, Ghostty, etc.). Without that permission, System Events cannot
#   enumerate Mission Control's UI.
#
# Usage:
#   close-empty-spaces.sh            # dry run: list what would be closed
#   close-empty-spaces.sh --apply    # actually remove empty spaces
#   close-empty-spaces.sh --list     # diagnostic: dump every readable AX
#                                    # attribute for each desktop button so
#                                    # we can figure out what distinguishes
#                                    # an empty space from a non-empty one
#   close-empty-spaces.sh --probe    # print the full UI hierarchy
#
# Caveats (read these):
#  - AXRemoveDesktop is an undocumented accessibility action. It has been
#    stable for years but Apple may change it in any macOS update.
#  - The UI element path below targets the layout used in recent macOS
#    versions. If the script reports "could not find desktop buttons",
#    run with --probe and adjust ELEMENT_PATH.
#  - We never remove the last remaining desktop (macOS would refuse anyway).
#  - "Empty" is detected by counting the children of each desktop's
#    button in Mission Control. A desktop with no window thumbnails has
#    zero (or one decorative) child element.

set -euo pipefail

MODE="dry"
case "${1:-}" in
  --apply) MODE="apply" ;;
  --probe) MODE="probe" ;;
  --list)  MODE="list"  ;;
  "" )     MODE="dry"   ;;
  *) echo "usage: $0 [--apply|--list|--probe]" >&2; exit 2 ;;
esac

# Path to the list of desktop buttons inside the Dock process.
# If this breaks on a future macOS version, use --probe to find the
# right path and update this string. Both halves of the OR are common.
read -r -d '' ELEMENT_PATH <<'EOF' || true
        try
                set deskList to list 1 of group 2 of group 1 of group 1 of process "Dock"
        on error
                set deskList to list 1 of group 1 of group 1 of process "Dock"
        end try
EOF

probe_script() {
  cat <<EOF
tell application "Mission Control" to launch
delay 0.4
tell application "System Events"
        tell process "Dock"
                set theDesc to entire contents
        end tell
        delay 0.3
        key code 53
end tell
return theDesc
EOF
}

# --list dumps every readable AX attribute of each desktop button so we
# can see what actually distinguishes empty from non-empty spaces. The
# user runs this, pastes the output, and we tune the detection.
list_script() {
  cat <<EOF
on safeGet(handler)
        try
                return (handler() as text)
        on error e
                return "<err: " & e & ">"
        end try
end safeGet

tell application "Mission Control" to launch
delay 0.45

set report to {}

tell application "System Events"
$ELEMENT_PATH
        set total to count of buttons of deskList
        set end of report to ("=== total buttons: " & total & " ===")

        repeat with i from 1 to total
                set btn to button i of deskList
                set end of report to ("--- button " & i & " ---")

                try
                        set end of report to ("  name: " & (name of btn))
                end try
                try
                        set end of report to ("  description: " & (description of btn))
                end try
                try
                        set end of report to ("  title: " & (title of btn))
                end try
                try
                        set end of report to ("  value: " & (value of btn))
                end try
                try
                        set end of report to ("  help: " & (help of btn))
                end try
                try
                        set end of report to ("  role: " & (role of btn))
                end try
                try
                        set end of report to ("  role description: " & (role description of btn))
                end try
                try
                        set end of report to ("  subrole: " & (subrole of btn))
                end try
                try
                        set end of report to ("  selected: " & (selected of btn))
                end try
                try
                        set kids to UI elements of btn
                        set end of report to ("  UI elements count: " & (count of kids))
                        repeat with k from 1 to (count of kids)
                                set kid to item k of kids
                                set kidLine to ("    child " & k)
                                try
                                        set kidLine to kidLine & " role=" & (role of kid)
                                end try
                                try
                                        set kidLine to kidLine & " desc=" & (description of kid)
                                end try
                                try
                                        set kidLine to kidLine & " name=" & (name of kid)
                                end try
                                try
                                        set inner to UI elements of kid
                                        set kidLine to kidLine & " inner=" & (count of inner)
                                end try
                                set end of report to kidLine
                        end repeat
                end try
                try
                        set acts to actions of btn
                        set actNames to {}
                        repeat with a in acts
                                try
                                        set end of actNames to (name of a)
                                end try
                        end repeat
                        set end of report to ("  actions: " & (actNames as text))
                end try
                try
                        set attrs to attributes of btn
                        set attrNames to {}
                        repeat with a in attrs
                                try
                                        set end of attrNames to (name of a)
                                end try
                        end repeat
                        set end of report to ("  attributes: " & (attrNames as text))
                end try
        end repeat

        delay 0.3
        key code 53
end tell

set AppleScript's text item delimiters to linefeed
return report as text
EOF
}

run_script() {
  local apply="$1"
  cat <<EOF
on countWindowsInDesktop(btn)
        tell application "System Events"
                try
                        set kids to UI elements of btn
                        return (count of kids)
                on error
                        return 0
                end try
        end tell
end countWindowsInDesktop

tell application "Mission Control" to launch
delay 0.45

set removed to 0
set kept to 0
set inspected to {}

tell application "System Events"
$ELEMENT_PATH
        set total to count of buttons of deskList

        -- Iterate from the last button to the first so removals don't
        -- shift the indices of buttons we still need to examine.
        repeat with i from total to 1 by -1
                if (count of buttons of deskList) <= 1 then exit repeat
                set btn to button i of deskList
                set kidCount to my countWindowsInDesktop(btn)
                set end of inspected to ("space " & i & " kids=" & kidCount)
                if kidCount <= 1 then
                        if ${apply} then
                                try
                                        perform action "AXRemoveDesktop" of btn
                                        set removed to removed + 1
                                        delay 0.15
                                on error errMsg
                                        set end of inspected to ("space " & i & " remove failed: " & errMsg)
                                end try
                        else
                                set removed to removed + 1
                        end if
                else
                        set kept to kept + 1
                end if
        end repeat

        delay 0.3
        key code 53 -- Esc to close Mission Control
end tell

return (("inspected: " as text) & (inspected as text) & linefeed & ¬
        "removed=" & removed & " kept=" & kept)
EOF
}

case "$MODE" in
  probe)
    osascript -e "$(probe_script)"
    ;;
  list)
    echo "Inspecting each desktop button. Mission Control will flash."
    echo "Paste the output below in chat so detection can be tuned."
    echo "----8<----"
    osascript -e "$(list_script)"
    echo "---->8----"
    ;;
  dry)
    echo "Dry run — opening Mission Control briefly to inspect spaces..."
    osascript -e "$(run_script false)"
    echo ""
    echo "Re-run with --apply to actually remove the empty spaces."
    ;;
  apply)
    echo "Closing empty spaces..."
    osascript -e "$(run_script true)"
    ;;
esac

#!/bin/bash
# <swiftbar.title>WireGuard home tunnel</swiftbar.title>
# <swiftbar.desc>FritzBox home split-tunnel state. Click to toggle.</swiftbar.desc>
# <swiftbar.author>nbrandizzi</swiftbar.author>

WG_CONF="$HOME/Documents/wg_config.conf"

# Resolve wg-quick (arm vs intel homebrew)
if [[ -x /opt/homebrew/bin/wg-quick ]]; then
    WG_QUICK="/opt/homebrew/bin/wg-quick"
elif [[ -x /usr/local/bin/wg-quick ]]; then
    WG_QUICK="/usr/local/bin/wg-quick"
else
    echo "⚠️"
    echo "---"
    echo "wg-quick not found | color=red"
    exit 0
fi

# Action dispatch (clicked from menu)
# Uses osascript for a native admin-privileges prompt instead of sudo in Terminal.
case "$1" in
    up)
        osascript -e "do shell script \"$WG_QUICK up $WG_CONF\" with administrator privileges" \
            >/dev/null 2>&1
        exit 0
        ;;
    down)
        osascript -e "do shell script \"$WG_QUICK down $WG_CONF\" with administrator privileges" \
            >/dev/null 2>&1
        exit 0
        ;;
esac

# State detection: wg-quick creates a utun with MTU 1420 (1500 - 80-byte WG overhead).
# False positive possible if another tool also creates a 1420-MTU tunnel — unlikely here.
if ifconfig 2>/dev/null | grep -qE "mtu 1420"; then
    echo "🔒"
    echo "---"
    echo "WireGuard: UP | color=green"
    echo "Down | bash=\"$0\" param1=down terminal=false refresh=true"
else
    echo "🔓"
    echo "---"
    echo "WireGuard: DOWN | color=gray"
    echo "Up | bash=\"$0\" param1=up terminal=false refresh=true"
fi

echo "---"
echo "Config: $WG_CONF | color=gray size=10"

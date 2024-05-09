export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
export PATH="${PATH:+${PATH}:}/opt/homebrew/opt/fzf/bin"

plugins=($plugins brew macos)
social() {
    print_usage() {
        printf "Usage: social [options] [arguments]\n"
        printf "Options:\n"
        printf "  -h, --help\t\t\t\tDisplay this help message\n"
        printf "  -p, --profile\t\t\tSpecify a profile, by default is 'Profile 1'\n\n"
        printf "Arguments:\n"
        printf "  tg, telegram\t\t\t\tOpen Telegram\n"
        printf "  wa, whatsapp\t\t\t\tOpen WhatsApp\n"
        printf "  rc, rocketchat\t\t\tOpen RocketChat\n"
        printf "  sk, slack\t\t\t\tOpen Slack\n"
        printf "  dc, discord\t\t\t\tOpen Discord\n"
        printf "  mm, mattermost\t\t\tOpen Mattermost\n"
        printf "  all\t\t\t\t\tOpen all social apps\n"
        printf "  work\t\t\t\t\tOpen all work-related social apps\n"
        printf "  personal\t\t\t\tOpen all personal social apps\n\n"
        printf "Examples:\n"
        printf "social tg\n"
        printf "social -p 'Profile 2' wa\n"
        printf "social all\n"
    }

    # Paths and profiles
    chrome_path="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    default_profile="Profile 1"
    profile=$default_profile

    # Application groups
    work_apps=("https://juchat.fz-juelich.de/home" "https://slack.com" "https://mattermost.hzdr.de/trustllm/channels/town-square")
    personal_apps=("https://web.telegram.org" "https://web.whatsapp.com" "http://discord.com/app")
    all_apps=("${work_apps[@]}" "${personal_apps[@]}")

    # Check for Chrome installation
    if [ ! -f "$chrome_path" ]; then
        echo "Google Chrome is not installed"
        return
    fi

    # Show usage if no arguments are passed
    if [ $# -eq 0 ]; then
        print_usage
        return
    fi

    # Helper function to open URLs in a single new window
    open_multiple_in_new_window() {
        local urls=("$@")
        osascript -e "tell application \"Google Chrome\"
                        activate
                        set newWindow to make new window
                        tell newWindow
                            repeat with url in {$(printf "\"%s\", " "${urls[@]}" | sed 's/, $//')}
                                set newTab to make new tab at end of tabs
                                set URL of newTab to url
                            end repeat
                        end tell
                    end tell"
    }

    # Process the arguments
    urls_to_open=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -h | --help)
                print_usage
                return
                ;;
            -p | --profile)
                profile=$2
                shift
                ;;
            tg | telegram)
                urls_to_open+=("https://web.telegram.org")
                ;;
            wa | whatsapp)
                urls_to_open+=("https://web.whatsapp.com")
                ;;
            rc | rocketchat)
                urls_to_open+=("https://juchat.fz-juelich.de/home")
                ;;
            sk | slack)
                urls_to_open+=("https://slack.com")
                ;;
            dc | discord)
                urls_to_open+=("http://discord.com/app")
                ;;
            mm | mattermost)
                urls_to_open+=("https://mattermost.hzdr.de/trustllm/channels/town-square")
                ;;
            all)
                urls_to_open=("${all_apps[@]}")
                ;;
            work)
                urls_to_open=("${work_apps[@]}")
                ;;
            personal)
                urls_to_open=("${personal_apps[@]}")
                ;;
            *)
                echo "Invalid argument: $1"
                print_usage
                return
                ;;
        esac
        shift
    done

    # If we have URLs to open, proceed
    if [ ${#urls_to_open[@]} -gt 0 ]; then
        open_multiple_in_new_window "${urls_to_open[@]}"
    fi
}

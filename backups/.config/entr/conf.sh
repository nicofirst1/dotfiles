update_latest_link() {
    local file_path="$1"
    local dir_name=$(dirname "$file_path")
    local file_name=$(basename "$file_path")

    # Extract job_name and type from the file name
    local job_name=$(echo "$file_name" | sed -n 's/^\([a-zA-Z0-9_-]*\)-[0-9]*\.\(err\|out\)\.log$/\1/p')
    local log_type=$(echo "$file_name" | sed -n 's/^[a-zA-Z0-9_-]*-[0-9]*\.\(err\|out\)\.log$/\1/p')

    # Create or update the symbolic link
    ln -sf "$file_path" "$dir_name/$job_name-latest.$log_type.log"
}

monitor_log() {
    # Directory to monitor
    local dir_to_monitor="$1"

    # Check if the directory exists
    if [ ! -d "$dir_to_monitor" ]; then
        echo "Directory does not exist: $dir_to_monitor"
        return 1
    fi

    # Use find to list existing relevant files and trigger the initial setup of links
    find "$dir_to_monitor" -type f -regex '.*-[0-9]+\.\(err\|out\)\.log' | while read -r file; do
        update_latest_link "$file"
    done

    # Monitor for new files
    echo "Monitoring directory: $dir_to_monitor for new SLURM logs..."
    inotifywait -m -e create --format '%w%f' "$dir_to_monitor" | while read -r new_file; do
        if [[ "$new_file" =~ .*-[0-9]+\.(err|out)\.log$ ]]; then
            update_latest_link "$new_file"
        fi
    done
}

# Usage: monitor_log /path/to/directory

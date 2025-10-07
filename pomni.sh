#!/bin/bash
set -e

progsfile="https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/progs.csv"
tmpfile=$(mktemp)

# Build a temporary checklist file (one line per item)
curl -Ls "$progsfile" | sed '/^#/d;/^$/d' | while IFS=, read -r tag program comment; do
    [[ -z "$program" ]] && continue
    if [[ "$tag" == "A" || -z "$tag" ]]; then
        # Short description (30 chars) to prevent wrapping
        desc=$(echo "$comment" | cut -c1-30)
        # Write: tag description OFF
        echo "$program \"$desc\" OFF" >> "$tmpfile"
    fi
done

# Build arguments from temp file
args=()
while read -r line; do
    # Split line into three fields
    name=$(echo "$line" | awk '{print $1}')
    desc=$(echo "$line" | awk -F\" '{print $2}')
    args+=("$name" "$desc" "OFF")
done < "$tmpfile"

# Show checklist
chosen=$(whiptail --title "Choose Browsers to Install" \
    --checklist "Select browsers:" 25 80 15 \
    "${args[@]}" 3>&1 1>&2 2>&3) || exit 1

# Cleanup
rm "$tmpfile"

# Remove quotes
chosen=$(echo "$chosen" | tr -d '"')

echo "You selected: $chosen"

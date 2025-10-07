#!/bin/bash
set -e

progsfile="https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/progs.csv"

# Download CSV to temp file
tmpcsv=$(mktemp)
curl -Ls "$progsfile" | sed '/^#/d;/^$/d' > "$tmpcsv"

# Build options array for whiptail
options_array=()
while IFS=, read -r tag program comment; do
    [[ -z "$program" ]] && continue
    if [[ "$tag" == "A" || -z "$tag" ]]; then
        # Shorten description
        desc=$(echo "$comment" | cut -c1-40)
        options_array+=("$program" "$desc" "OFF")
    fi
done < "$tmpcsv"

# Interactive checklist
chosen=$(whiptail --title "Choose Browsers to Install" \
    --checklist "Select the browsers you want to install:" 20 78 12 \
    "${options_array[@]}" 3>&1 1>&2 2>&3) || exit 1

# Clean up
rm "$tmpcsv"

# Remove quotes
chosen=$(echo "$chosen" | tr -d '"')

echo "You selected: $chosen"

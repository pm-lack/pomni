#!/bin/bash
set -e

progsfile="https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/progs.csv"

# Download CSV
tmpcsv=$(mktemp)
curl -Ls "$progsfile" | sed '/^#/d;/^$/d' > "$tmpcsv"

# Build dialog checklist items
items=()
while IFS=, read -r tag program comment; do
    [[ -z "$program" ]] && continue
    if [[ "$tag" == "A" || -z "$tag" ]]; then
        # Shorten description to avoid wrapping issues
        desc=$(echo "$comment" | cut -c1-50)
        items+=("$program" "$desc" "off")
    fi
done < "$tmpcsv"

# Show dialog checklist
chosen=$(dialog --title "Select Browsers to Install" \
    --checklist "Use SPACE to select, ENTER to confirm:" 25 80 15 \
    "${items[@]}" 3>&1 1>&2 2>&3)

# Clean up
rm "$tmpcsv"
clear

# Remove quotes
chosen=$(echo "$chosen" | tr -d '"')

echo "You selected: $chosen"

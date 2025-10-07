#!/bin/bash
set -e

progsfile="https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/progs.csv"
tmpcsv=$(mktemp)
curl -Ls "$progsfile" | sed '/^#/d;/^$/d' > "$tmpcsv"

selected=""

while IFS=, read -r tag program comment; do
    [[ -z "$program" ]] && continue
    if [[ "$tag" == "A" || -z "$tag" ]]; then
        desc=$(echo "$comment" | cut -c1-50)
        if whiptail --title "Install Browser?" --yesno "$program: $desc" 10 60; then
            selected="$selected $program"
        fi
    fi
done < "$tmpcsv"

rm "$tmpcsv"

echo "You selected:$selected"

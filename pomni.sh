#!/bin/bash
# Browser Installer from progs.csv (names only, clean layout)
# Author: pm

set -e
export TERM=ansi

progsfile="https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/progs.csv"
aurhelper="yay"
tmpcsv="/tmp/progs.csv"

# Download CSV and remove comments
curl -Ls "$progsfile" | sed '/^#/d' > "$tmpcsv"

# Extract only browser names (AUR type) into a temporary checklist file
checklistfile="/tmp/browser_checklist.txt"
> "$checklistfile"
while IFS=, read -r tag program comment; do
    [ "$tag" != "A" ] && continue
    echo "$program OFF" >> "$checklistfile"
done < "$tmpcsv"

# Build whiptail command dynamically
cmd=(whiptail --title "Browser Selection" --checklist "Select browsers to install:" 20 60 15)
while read -r line; do
    browser=$(echo "$line" | awk '{print $1}')
    status=$(echo "$line" | awk '{print $2}')
    cmd+=("$browser" "" "$status")
done < "$checklistfile"

# Show checklist
selected=$("${cmd[@]}" 3>&1 1>&2 2>&3) || exit 0
selected=$(echo "$selected" | tr -d '"')

# Install selected browsers
if [ -n "$selected" ]; then
    for browser in $selected; do
        echo "Installing $browser..."
        sudo $aurhelper -S --noconfirm "$browser"
    done
else
    echo "No browsers selected. Exiting."
fi

echo "All done!"

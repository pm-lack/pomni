#!/bin/bash
# Browser Installer from progs.csv (names only)
# Author: pm
# License: GNU GPLv3

set -e
export TERM=ansi

progsfile="https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/progs.csv"
aurhelper="yay"
tmpcsv="/tmp/progs.csv"

# Download CSV and remove comments
curl -Ls "$progsfile" | sed '/^#/d' > "$tmpcsv"

# Function to install an AUR package
aurinstall() {
    sudo $aurhelper -S --noconfirm "$1"
}

# Build checklist with names only
checklist_items=()
while IFS=, read -r tag program comment; do
    [ "$tag" != "A" ] && continue  # only AUR browsers
    checklist_items+=("$program" "" "OFF")
done < "$tmpcsv"

# Show checklist
selected=$(whiptail --title "Browser Selection" --checklist \
    "Select the browser(s) you want to install:" 20 78 12 \
    "${checklist_items[@]}" 3>&1 1>&2 2>&3) || exit 0

# Cleanup quotes
selected=$(echo "$selected" | tr -d '"')

# Install selected browsers
for browser in $selected; do
    echo "Installing $browser..."
    aurinstall "$browser"
done

echo "All selected browsers installed!"

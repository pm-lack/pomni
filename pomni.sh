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

# Build flattened checklist arguments
checklist_args=()
while IFS=, read -r tag program comment; do
    [ "$tag" != "A" ] && continue  # only AUR browsers
    checklist_args+=("$program" " " "OFF") # tag, description, status
done < "$tmpcsv"

# Show checklist
selected=$(whiptail --title "Browser Selection" --checklist \
    "Select the browser(s) you want to install:" 20 60 15 \
    "${checklist_args[@]}" 3>&1 1>&2 2>&3) || exit 0

# Cleanup quotes
selected=$(echo "$selected" | tr -d '"')

# Install selected browsers
if [ -n "$selected" ]; then
    for browser in $selected; do
        echo "Installing $browser..."
        aurinstall "$browser"
    done
else
    echo "No browsers selected. Exiting."
fi

echo "Done!"

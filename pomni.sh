#!/bin/bash
# Browser Installer from progs.csv
# Author: pm
# License: GNU GPLv3

set -e
export TERM=ansi

# URL to CSV with browsers
progsfile="https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/progs.csv"

# AUR helper
aurhelper="yay"

# Temporary CSV
tmpcsv="/tmp/progs.csv"

# Download CSV or use local copy
curl -Ls "$progsfile" | sed '/^#/d' > "$tmpcsv"

# Function to install a pacman package
installpkg() {
    sudo pacman --noconfirm --needed -S "$1"
}

# Function to install an AUR package
aurinstall() {
    sudo $aurhelper -S --noconfirm "$1"
}

# Build checklist items for whiptail (only AUR browsers)
mapfile -t browsers < <(awk -F, '$1=="A" {gsub(/"/,"",$3); print $2 " \"" $3 "\" OFF"}' "$tmpcsv")
checklist_items=$(printf "%s " "${browsers[@]}")

# Show checklist
selected=$(whiptail --title "Browser Selection" --checklist \
    "Select the browser(s) you want to install:" 20 78 12 \
    $checklist_items 3>&1 1>&2 2>&3) || exit 0

# Cleanup quotes
selected=$(echo "$selected" | tr -d '"')

# Install selected browsers
for browser in $selected; do
    # Find comment for display
    comment=$(awk -F, -v b="$browser" '$2==b {gsub(/"/,"",$3); print $3}' "$tmpcsv")
    echo "Installing $browser - $comment..."
    aurinstall "$browser"
done

echo "All selected browsers installed!"

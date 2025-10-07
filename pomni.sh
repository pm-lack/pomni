#!/bin/sh
# POMNI-style Interactive Browser Installer
# By pm
# --------------------------------------------
# This script is intended to fetch a list of browsers
# from a CSV, let the user select them via whiptail,
# and install the selected browsers from pacman/AUR.

set -e  # Exit immediately if any command fails
export TERM=ansi  # Set terminal type for consistent output (important for whiptail/dialog)

# --------------------------------------------
# VARIABLES

progsfile="https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/progs.csv"
aurhelper="yay"                 # AUR helper to install AUR packages
repodir="$HOME/.local/src"      # Directory to store cloned git repos

# --------------------------------------------
# FUNCTIONS

# Install a package from pacman
installpkg() {
    pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

# Install an AUR package using yay
aurinstall() {
    echo "Installing AUR package: $1"
    $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

# --------------------------------------------
# Fetch browsers from CSV and build whiptail checklist string
fetch_browsers() {
    # Download the CSV and remove comments/empty lines
    curl -Ls "$progsfile" | sed '/^#/d;/^$/d' | awk -F, '
        $1=="A" || $1=="" {printf "\"%s\" \"%s\" OFF ", $2, $3}
    '
    # --------------------------------------------
    # POTENTIAL ISSUE #1:
    # - All items are printed into one giant line.
    # - If there are too many items, whiptail may fail silently.
    # - Whiptail requires each item to have three fields: "name" "description" ON|OFF
    # - Names with spaces, quotes, or commas can break whiptail.
}

# --------------------------------------------
# Let user select browsers interactively
choose_browsers() {
    echo "==> Fetching browser list..."
    options=$(fetch_browsers)

    # Show checklist dialog
    chosen=$(whiptail --title "Choose Browsers to Install" \
        --checklist "Select the browsers you want to install:" 20 78 12 \
        $options 3>&1 1>&2 2>&3) || exit 1
    # --------------------------------------------
    # POTENTIAL ISSUE #2:
    # - $options is **not quoted** when passed to whiptail. 
    # - This means spaces in descriptions or names break argument splitting.
    # - Whiptail sees the wrong number of arguments and exits, which explains a blank dialog.

    # Remove quotes from output
    chosen=$(echo "$chosen" | tr -d '"')
    echo "$chosen"
}

# --------------------------------------------
# Install the selected browsers
installationloop() {
    for program in $1; do
        echo
        echo "Installing $program..."
        case "$program" in
            *A*|firefox*|palemoon*|mullvad*|icecat*|floorp*|midori*|zen* )
                aurinstall "$program" ;;
            *) installpkg "$program" ;;
        esac
    done
}

# --------------------------------------------
# MAIN EXECUTION

# Must be run as root
[ "$(id -u)" -eq 0 ] || { echo "Please run as root."; exit 1; }

# Install dependencies
for x in curl git base-devel whiptail; do
    command -v "$x" >/dev/null 2>&1 || installpkg "$x"
done

# Ensure repo directory exists
mkdir -p "$repodir"

# Install AUR helper if missing
if ! command -v "$aurhelper" >/dev/null 2>&1; then
    echo "==> Installing AUR helper ($aurhelper)..."
    mkdir -p "$repodir/$aurhelper"
    git -C "$repodir" clone --depth 1 "https://aur.archlinux.org/$aurhelper.git" "$repodir/$aurhelper"
    cd "$repodir/$aurhelper"
    makepkg --noconfirm -si >/dev/null 2>&1
fi

# --------------------------------------------
# INTERACTIVE BROWSER SELECTION
to_install=$(choose_browsers)

# Install the selected browsers
installationloop "$to_install"

echo "==> Installation complete."

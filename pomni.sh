#!/bin/sh
# POMNI-style Minimal Installer for Browsers
# Installs only from progs.csv
# By pm (based on Luke Smith’s LARBS)
# License: GNU GPLv3

# Stop the script immediately if any command fails
set -e

# Force basic terminal capabilities
export TERM=ansi

### VARIABLES ###

# URL to the CSV file containing programs to install
# Each line: TAG,NAME_IN_REPO (or git url),DESCRIPTION
progsfile="https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/progs.csv"

# Name of the AUR helper to use
aurhelper="yay"

# Directory to clone source code into for manual builds
repodir="$HOME/.local/src"

### FUNCTIONS ###

# Install a package from official repos
installpkg() {
	pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
	# Note: output is suppressed
}

# Print error and exit
error() {
	printf "%s\n" "$1" >&2
	exit 1
}

# Manually install an AUR package by cloning and running makepkg
manualinstall() {
	# Skip if already installed
	pacman -Qq "$1" >/dev/null 2>&1 && return 0
	echo "Installing $1 manually from AUR..."

	# Create directory for this package
	mkdir -p "$repodir/$1"

	# Clone repo (or update if it exists)
	git -C "$repodir" clone --depth 1 --single-branch --no-tags -q \
		"https://aur.archlinux.org/$1.git" "$repodir/$1" ||
		(cd "$repodir/$1" && git pull --force origin master)

	# Build and install package quietly
	cd "$repodir/$1"
	makepkg --noconfirm -si >/dev/null 2>&1
}

# Install a package via AUR helper
aurinstall() {
	echo "Installing AUR package: $1"
	# Suppresses all output
	$aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

# Clone a git repo and run make/make install
gitmakeinstall() {
	# Extract repo name from URL
	progname="${1##*/}"
	progname="${progname%.git}"

	dir="$repodir/$progname"
	echo "Installing $progname from git source..."

	# Make sure directory exists and clone repo
	mkdir -p "$repodir"
	git -C "$repodir" clone --depth 1 --single-branch --no-tags -q "$1" "$dir" ||
		(cd "$dir" && git pull --force origin master)

	cd "$dir"

	# Build and install (output suppressed)
	make >/dev/null 2>&1 && make install >/dev/null 2>&1
}

# Install Python package via pip
pipinstall() {
	echo "Installing Python package: $1"
	# Ensure pip exists
	command -v pip >/dev/null 2>&1 || installpkg python-pip
	# Automatically confirm install
	yes | pip install "$1"
}

# Loop through CSV and install each program
installationloop() {
	echo "==> Fetching progs.csv..."

	# If the CSV exists locally, copy it; else download from URL
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) ||
		curl -Ls "$progsfile" | sed '/^#/d;/^$/d' >/tmp/progs.csv
	# Note: sed removes comments and empty lines

	# Count total lines for progress
	total=$(wc -l </tmp/progs.csv)
	n=0

	# Read CSV line by line
	while IFS=, read -r tag program comment; do
		n=$((n + 1))
		[ -z "$program" ] && continue  # skip empty lines

		echo
		echo "[$n/$total] Installing $program ..."

		# Decide installation method based on TAG
		case "$tag" in
			A) aurinstall "$program" ;;     # AUR package
			G) gitmakeinstall "$program" ;; # Git source
			P) pipinstall "$program" ;;     # Python package
			*) installpkg "$program" ;;     # Official repo package
		esac
	done </tmp/progs.csv
}

### MAIN EXECUTION ###

# Check if running as root
[ "$(id -u)" -eq 0 ] || error "Please run as root (sudo)."

# Ensure basic tools are installed
for x in curl base-devel git pacman; do
	command -v "$x" >/dev/null 2>&1 || installpkg "$x"
done

# Make sure repo directory exists
mkdir -p "$repodir"

# Install AUR helper if missing
if ! command -v "$aurhelper" >/dev/null 2>&1; then
	echo "==> Installing AUR helper ($aurhelper)..."
	manualinstall "$aurhelper"
fi

# Run the main installation loop
installationloop

echo
echo "==> Installation complete."

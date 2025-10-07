#!/bin/sh
# POMNI-style Interactive Browser Installer
# By pm

set -e
export TERM=ansi

progsfile="https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/progs.csv"
aurhelper="yay"
repodir="$HOME/.local/src"

installpkg() {
	pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

aurinstall() {
	echo "Installing AUR package: $1"
	$aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

# Fetch browsers from CSV and build checklist items
fetch_browsers() {
	curl -Ls "$progsfile" | sed '/^#/d;/^$/d' | awk -F, '
		$1=="A" || $1=="" {printf "\"%s\" \"%s\" OFF ", $2, $3}
	'
}

# Main interactive loop
choose_browsers() {
	echo "==> Fetching browser list..."
	options=$(fetch_browsers)

	chosen=$(whiptail --title "Choose Browsers to Install" \
		--checklist "Select the browsers you want to install:" 20 78 12 \
		$options 3>&1 1>&2 2>&3) || exit 1

	# whiptail outputs choices as "firefox-bin" "palemoon-bin"
	# remove quotes
	chosen=$(echo "$chosen" | tr -d '"')
	echo "$chosen"
}

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

### MAIN EXECUTION ###
[ "$(id -u)" -eq 0 ] || { echo "Please run as root."; exit 1; }

# Install basic dependencies
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

# Choose browsers
to_install=$(choose_browsers)

# Install the selected browsers
installationloop "$to_install"

echo "==> Installation complete."

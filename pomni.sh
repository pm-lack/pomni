#!/bin/sh

# Check root
if [ "$(id -u)" -ne 0 ]; then
	printf '%s\n' "This script must be run as root."
	exit 1
fi

# Temporary directory
TMPDIR=$(mktemp -d) || exit 1

# Cleanup when the script exits
cleanup() {
	rm -rf "$TMPDIR"

	if [ -f /etc/sudoers.d/wheel ]; then
		printf '%s\n' \
			'%wheel ALL=(ALL:ALL) ALL' \
			'%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown, /usr/bin/halt, /usr/bin/reboot' \
			> /etc/sudoers.d/wheel
			chmod 440 /etc/sudoers.d/wheel
	fi
}
trap cleanup EXIT

die() {
	whiptail --title "Error" --fullbuttons --msgbox "$1" 8 60
	exit 1
}

# Whiptail colors
export NEWT_COLORS='
root=white,black
window=white,black
border=white,black
shadow=black,black
title=white,black
button=black,white
actbutton=white,magenta
compactbutton=black,white
checkbox=white,black
actcheckbox=white,magenta
entry=white,black
label=white,black
listbox=white,black
actlistbox=white,magenta
textbox=white,black
helpline=white,black
roottext=white,black
'

# Welcome
whiptail \
	--title "pm's Opinionated Minimal Nest Installer" \
	--fullbuttons \
	--msgbox \
	"Welcome!\n\nWIP Artix/Arch bootstrapper. This is a minimal Artix/Arch setup script. This will make changes to your system." \
	12 61 || exit 1

# User creation
name=$(whiptail \
	--title "User Creation" \
	--fullbuttons \
	--inputbox "Enter the username to create or configure:" \
	10 60 \
	3>&1 1>&2 2>&3) || exit 1

# Make sure a username was entered
if [ -z "$name" ]; then
	die "No username was entered."
fi

# Check whether the user already exists
if id -u "$name" >/dev/null 2>&1; then
	if ! whiptail \
		--title "WARNING" \
		--fullbuttons \
		--yes-button "Yes" \
		--no-button "No wait..." \
		--yesno \
		"The user \`$name\` already exists on this system.\n\nDelete \`$name\` and continue?" \
		13 60
	then
		exit 0
	fi
fi

# Password
password=$(whiptail \
	--title "User Password" \
	--fullbuttons \
	--passwordbox "Enter the password for $name:" \
	10 60 \
	3>&1 1>&2 2>&3) || exit 1

if [ -z "$password" ]; then
	die "No password was entered."
fi

# Confirm password
password_confirm=$(whiptail \
	--title "Confirm Password" \
	--fullbuttons \
	--passwordbox "Enter the password again:" \
	10 60 \
	3>&1 1>&2 2>&3) || exit 1

if [ "$password" != "$password_confirm" ]; then
	die "The passwords do not match."
fi

unset password_confirm

# Install git and zsh
whiptail \
	--title "Installing" \
	--infobox \
	"Installing Git and Zsh..." \
	8 50

pacman -S --needed --noconfirm git zsh zsh-autosuggestions >/dev/null 2>&1 ||
	die "Failed to install Git and Zsh."

# Create user if necessary
if ! id -u "$name" >/dev/null 2>&1; then
	useradd -m -s /bin/zsh "$name" ||
		die "Failed to create user $name."
else
	usermod -s /bin/zsh "$name" ||
		die "Failed to set Zsh as the login shell for $name."
fi

# Get user's home directory
home=$(getent passwd "$name" | cut -d: -f6)

if [ -z "$home" ]; then
	die "Failed to determine the home directory for $name."
fi

# Add user to wheel
usermod -aG wheel "$name" ||
	die "Failed to add $name to the wheel group."

# Set password
printf '%s:%s\n' "$name" "$password" | chpasswd ||
	die "Failed to set the user's password."

unset password

# Sudo fix
printf '%s\n' '%wheel ALL=(ALL) NOPASSWD: ALL' \
	>/etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Zsh config
# Fast syntax highlighting
git clone --depth 1 https://github.com/zdharma-continuum/fast-syntax-highlighting /usr/share/zsh/plugins/fast-syntax-highlighting >/dev/null 2>&1 ||
		die "Failed to clone fast-syntax-highlighting."

sudo -u "$name" mkdir -p "$home/.local/bin"
sudo -u "$name" mkdir -p "$home/.config/zsh"
sudo -u "$name" mkdir -p "$home/.cache/zsh"
sudo -u "$name" sh -c 'cat > "$HOME/.zshenv"' <<'EOF'
export ZDOTDIR="$HOME/.config/zsh"
EOF
sudo -u "$name" sh -c 'cat > "$HOME/.config/zsh/.zshrc"' <<'EOF'
# Enable colors and change prompt
autoload -U colors && colors
PS1="%{$fg[magenta]%}%n%{$reset_color%} %~ %# "

# History in cache directory
HISTSIZE=10000000
SAVEHIST=10000000
HISTFILE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/history"
setopt inc_append_history

# Basic auto/tab complete
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)

# Alias
alias ll='ls -lah'
alias susu='sudo su root'

# Load zsh plugins; should be last.
source /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh 2>/dev/null
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh 2>/dev/null
EOF
sudo -u "$name" sh -c 'cat > "$HOME/.config/zsh/.zprofile"' <<'EOF'
# Add ~/.local/bin to $PATH
export PATH="$HOME/.local/bin:$PATH"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export TERMINAL="st"
export XINITRC="$XDG_CONFIG_HOME/x11/xinitrc"
export MOZ_USE_XINPUT2=1                  # Mozilla smooth scrolling/touchpads.
# Start graphical server on user's current tty if not already running.
#[ "$(tty)" = "/dev/tty1" ] && ! pidof -s Xorg >/dev/null 2>&1 && exec startx "$XINITRC"
EOF

# Lib32
whiptail \
	--title "Adding repo" \
	--infobox \
	"Setting up Lib32..." \
	8 50

sleep 1
if ! grep -q '^\[lib32\]' /etc/pacman.conf; then
	sed -i '/^\[galaxy\]/i [lib32]\nInclude = /etc/pacman.d/mirrorlist\n' /etc/pacman.conf
fi

# XLibre
whiptail \
	--title "Installing" \
	--infobox \
	"Setting up XLibre..." \
	8 50

# Download XLibre signing key
curl -fsSL \
	-o "$TMPDIR/xlibre-artixlinux.asc" \
	https://xlibre-artix.github.io/xlibre-artixlinux.asc ||
	die "Failed to download the XLibre signing key."

# Add XLibre signing key
pacman-key --add "$TMPDIR/xlibre-artixlinux.asc" >/dev/null 2>&1 ||
	die "Failed to add the XLibre signing key."

# Locally sign XLibre signing key
pacman-key --lsign-key 2AFFCD7B42ADD2E7 >/dev/null 2>&1 ||
	die "Failed to locally sign the XLibre signing key."

# Add XLibre repository
if ! grep -q '^\[xlibre-stable\]' /etc/pacman.conf; then
	sed -i '/^\[world\]/i [xlibre-stable]\nServer = https://github.com/xlibre-artix/stable/releases/download/$arch\n' /etc/pacman.conf
fi

# Refresh package databases and upgrade
pacman -Syyu --noconfirm >/dev/null 2>&1 ||
	die "Failed to update the package databases."

# Install XLibre
pacman -S --needed --noconfirm xlibre-meta >/dev/null 2>&1 ||
	die "Failed to install XLibre."

# X dependencies 
whiptail \
	--title "Installing" \
	--infobox \
	"Setting up X dependencies..." \
	8 50

pacman -S --needed --noconfirm libxinerama libxft xorg-xinit >/dev/null 2>&1 ||
	die "Failed to install X dependencies."
sudo -u "$name" mkdir -p "$home/.config/x11"
sudo -u "$name" sh -c 'cat > "$HOME/.config/x11/xinitrc"' <<'EOF'
# Key Repeat / Auto-repeat behavior
xset r rate 400 32

# Activate dbus variables
dbus-update-activation-environment --all
dbus-launch ssh-agent dwm
EOF

# Finished
whiptail \
	--title "Installation Complete" \
	--fullbuttons \
	--msgbox \
	"Everything is done!\n\nUser: $name\nShell: Zsh\nYou can now log in as $name." \
	12 60

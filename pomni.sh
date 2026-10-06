#!/bin/sh

# Check root
if [ "$(id -u)" -ne 0 ]; then
	printf '%s\n' "This script must be run as root."
	exit 1
fi

# Temporary directory
TMPDIR=$(mktemp -d) || exit 1

# Delete the temporary directory when the script exits
trap 'rm -rf "$TMPDIR"' EXIT

# Install whiptail
pacman -S --needed --noconfirm libnewt || exit 1

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
	--title "pm's Optimized Minimal Nest Installer" \
	--fullbuttons \
	--msgbox \
	"Welcome!\n\nWIP Artix/Arch bootstrapper. This installer will create or configure your user account and install a minimal Zsh environment." \
	10 60 || exit 1

# User creation
name=$(whiptail \
	--title "User Creation" \
	--fullbuttons \
	--inputbox "Enter the username to create or configure:" \
	10 60 \
	3>&1 1>&2 2>&3) || exit 1

# Make sure a username was entered
if [ -z "$name" ]; then
	whiptail \
		--title "Error" \
		--fullbuttons \
		--msgbox \
		"No username was entered." \
		8 50
	exit 1
fi

# Check whether the user already exists
if id -u "$name" >/dev/null 2>&1; then
	if ! whiptail \
		--title "WARNING" \
		--fullbuttons \
		--yes-button "CONTINUE" \
		--no-button "No wait..." \
		--yesno \
		"The user \`$name\` already exists on this system. The installer can install for an existing user, but it may OVERWRITE conflicting settings or dotfiles on the account.\n\nThe installer will NOT overwrite your personal files, documents, videos, etc.\n\nIt will also change $name's password to the one you provide.\n\nContinue?" \
		14 70
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
	whiptail \
		--title "Error" \
		--fullbuttons \
		--msgbox \
		"No password was entered." \
		8 50
	exit 1
fi

# Confirm password
password_confirm=$(whiptail \
	--title "Confirm Password" \
	--fullbuttons \
	--passwordbox "Enter the password again:" \
	10 60 \
	3>&1 1>&2 2>&3) || exit 1

if [ "$password" != "$password_confirm" ]; then
	whiptail \
		--title "Error" \
		--fullbuttons \
		--msgbox \
		"The passwords do not match." \
		8 50
	exit 1
fi

unset password_confirm

# Install git and zsh
whiptail \
	--title "Installing" \
	--infobox \
	"Installing Git and Zsh..." \
	8 50

pacman -S --needed --noconfirm git zsh || {
	whiptail \
		--title "Error" \
		--fullbuttons \
		--msgbox \
		"Failed to install Git and Zsh." \
		8 50
	exit 1
}

# Create user if necessary
if ! id -u "$name" >/dev/null 2>&1; then
	useradd -m -s /bin/zsh "$name" || {
		whiptail \
			--title "Error" \
			--fullbuttons \
			--msgbox \
			"Failed to create user $name." \
			8 50
		exit 1
	}
fi

# Get user's home directory
home=$(getent passwd "$name" | cut -d: -f6)

if [ -z "$home" ]; then
	whiptail \
		--title "Error" \
		--fullbuttons \
		--msgbox \
		"Failed to determine the home directory for $name." \
		8 60
	exit 1
fi

# Make sure the user has Zsh
usermod -s /bin/zsh "$name" || {
	whiptail \
		--title "Error" \
		--fullbuttons \
		--msgbox \
		"Failed to set Zsh as $name's shell." \
		8 50
	exit 1
}

# Add user to wheel
usermod -aG wheel "$name" || {
	whiptail \
		--title "Error" \
		--fullbuttons \
		--msgbox \
		"Failed to add $name to the wheel group." \
		8 50
	exit 1
}

# Set password
printf '%s:%s\n' "$name" "$password" | chpasswd || {
	whiptail \
		--title "Error" \
		--fullbuttons \
		--msgbox \
		"Failed to set the user's password." \
		8 50
	exit 1
}

unset password

# Sudo fix
printf '%s\n' '%wheel ALL=(ALL) NOPASSWD: ALL' \
	>/etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Zsh config
sudo -u "$name" mkdir -p "$home/.config/zsh"
sudo -u "$name" sh -c 'cat > "$HOME/.zshenv"' <<'EOF'
export ZDOTDIR="$HOME/.config/zsh"
EOF
sudo -u "$name" sh -c 'cat > "$HOME/.config/zsh/.zshrc"' <<'EOF'
# Enable colors and change prompt
autoload -U colors && colors
PS1="%B%{$fg[red]%}[%{$fg[yellow]%}%n%{$fg[green]%}@%{$fg[blue]%}%M %{$fg[magenta]%}%~%{$fg[red]%}]%{$reset_color%}$%b "

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

# Load syntax highlighting; should be last
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh 2>/dev/null
EOF
chsh -s /bin/zsh "$name" >/dev/null 2>&1

# Finished
whiptail \
	--title "Installation Complete" \
	--fullbuttons \
	--msgbox \
	"Everything is done!\n\nUser: $name\nShell: Zsh\nSudo: wheel (passwordless)\n\nYou can now log in as $name." \
	12 60
```

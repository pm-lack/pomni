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

# Welcome
whiptail --title "pm's Optimized Minimal Nest Installer" \
	--msgbox \
	"Welcome!\n\nThis installer will create your user account and configure a minimal Zsh environment." \
	10 60

# User creation
name=$(whiptail \
	--title "User Creation" \
	--inputbox "Enter the username to create:" \
	10 60 \
	3>&1 1>&2 2>&3) || exit 1

# Make sure a username was entered
if [ -z "$name" ]; then
	whiptail --title "Error" \
		--msgbox "No username was entered." 8 50
	exit 1
fi

# Check whether the user already exists
if id "$name" >/dev/null 2>&1; then
	whiptail --title "Error" \
		--msgbox "The user \`$name\` already exists on this system." 8 60
	exit 1
fi

# Password
password=$(whiptail \
	--title "User Password" \
	--passwordbox "Enter the password for $name:" \
	10 60 \
	3>&1 1>&2 2>&3) || exit 1

if [ -z "$password" ]; then
	whiptail --title "Error" \
		--msgbox "No password was entered." 8 50
	exit 1
fi

# Confirm password
password_confirm=$(whiptail \
	--title "Confirm Password" \
	--passwordbox "Enter the password again:" \
	10 60 \
	3>&1 1>&2 2>&3) || exit 1

if [ "$password" != "$password_confirm" ]; then
	whiptail --title "Error" \
		--msgbox "The passwords do not match." 8 50
	exit 1
fi

unset password_confirm

# Install git and zsh
whiptail --title "Installing" \
	--infobox "Installing Git and Zsh..." 8 50

pacman -S --needed --noconfirm git zsh || {
	whiptail --title "Error" \
		--msgbox "Failed to install Git and Zsh." 8 50
	exit 1
}

# Create user
useradd -m -s /bin/zsh "$name" || {
	whiptail --title "Error" \
		--msgbox "Failed to create user $name." 8 50
	exit 1
}

usermod -aG wheel "$name" || {
	whiptail --title "Error" \
		--msgbox "Failed to add $name to the wheel group." 8 50
	exit 1
}

printf '%s:%s\n' "$name" "$password" | chpasswd || {
	whiptail --title "Error" \
		--msgbox "Failed to set the user's password." 8 50
	exit 1
}

unset password

# Sudo fix
printf '%s\n' '%wheel ALL=(ALL) NOPASSWD: ALL' \
	>/etc/sudoers.d/wheel

chmod 440 /etc/sudoers.d/wheel

# Install zsh-autosuggestions
whiptail --title "Installing" \
	--infobox "Installing zsh-autosuggestions..." 8 50

mkdir -p "/home/$name/.local/share/zsh/plugins"

git clone --depth 1 \
	https://github.com/zsh-users/zsh-autosuggestions.git \
	"$TMPDIR/zsh-autosuggestions" || {
		whiptail --title "Error" \
			--msgbox "Failed to download zsh-autosuggestions." 8 60
		exit 1
	}

cp "$TMPDIR/zsh-autosuggestions/zsh-autosuggestions.zsh" \
	"/home/$name/.local/share/zsh/plugins/" || {
		whiptail --title "Error" \
			--msgbox "Failed to install zsh-autosuggestions." 8 60
		exit 1
	}

chown -R "$name:$name" "/home/$name/.local/share/zsh"

# Finished
whiptail --title "Installation Complete" \
	--msgbox \
	"pm's Optimized Minimal Nest Installer has finished successfully.\n\nUser: $name\nShell: Zsh\nSudo: wheel (passwordless)\n\nYou can now log in as $name." \
	12 65

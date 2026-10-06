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

# Install git and zsh
pacman -S --needed --noconfirm git zsh || exit 1

# User creation
printf 'Username: '
read -r name
useradd -m -s /bin/zsh "$name" || exit 1
usermod -aG wheel "$name" || exit 1
printf 'Password for %s: ' "$name"
stty -echo
read -r password
stty echo
printf '\n'
printf '%s:%s\n' "$name" "$password" | chpasswd || exit 1
unset password

# Sudo fix
printf '%s\n' '%wheel ALL=(ALL) NOPASSWD: ALL' \
	>/etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Install zsh-autosuggestions
mkdir -p "/home/$name/.local/share/zsh/plugins"
git clone --depth 1 \
	https://github.com/zsh-users/zsh-autosuggestions.git \
	"$TMPDIR/zsh-autosuggestions" || exit 1
cp "$TMPDIR/zsh-autosuggestions/zsh-autosuggestions.zsh" \
	"/home/$name/.local/share/zsh/plugins/" || exit 1
chown -R "$name:$name" "/home/$name/.local/share/zsh"

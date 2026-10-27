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
}
trap cleanup EXIT

die() {
	whiptail --title "Error" --fullbuttons --msgbox "$1" 9 60
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
	"Welcome!\n\nPomni is a minimal Artix setup script designed to install a basic opinionated dwm environment. This will make changes to your system." \
	13 61 || exit 1

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
	uid=$(id -u "$name")
	if [ "$uid" -lt 1000 ]; then
		die "Refusing to modify the system account \`$name\`."
	fi

	whiptail \
		--title "WARNING" \
		--fullbuttons \
		--yes-button "Continue" \
		--no-button "Cancel" \
		--yesno \
		"The user \`$name\` already exists.\n\nTheir password, login shell, groups, and zsh/X config files will be overwritten. Other files in their home directory are kept." \
		13 60 || exit 0
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
	"Installing requirements..." \
	8 50

pacman -S --needed --noconfirm git zsh zsh-autosuggestions >/dev/null 2>&1 ||
	die "Failed to install requirements."

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

# Sudo rules
cat > /etc/sudoers.d/pomni-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/halt,/usr/bin/reboot,/usr/bin/pacman -Syu
EOF
chmod 440 /etc/sudoers.d/pomni-wheel
if ! visudo -cf /etc/sudoers.d/pomni-wheel >/dev/null 2>&1; then
	rm -f /etc/sudoers.d/pomni-wheel
	die "The generated sudoers rules are invalid."
fi

# Zsh config
git clone --depth 1 https://github.com/zdharma-continuum/fast-syntax-highlighting /usr/share/zsh/plugins/fast-syntax-highlighting >/dev/null 2>&1 ||
		die "Failed to clone fast-syntax-highlighting."

as_user() {
	sudo -u "$name" "$@"
}

as_user mkdir -p "$home/.local/bin"
as_user mkdir -p "$home/.config/zsh"
as_user mkdir -p "$home/.cache/zsh"
as_user sh -c 'cat > "$HOME/.zshenv"' <<'EOF'
export ZDOTDIR="$HOME/.config/zsh"
EOF
as_user sh -c 'cat > "$HOME/.config/zsh/.zshrc"' <<'EOF'
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
alias lf='lfub'

# Fetch
fastfetch -l ~/.config/fastfetch/rose_ascii.txt

# Load zsh plugins; should be last.
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh 2>/dev/null
source /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh 2>/dev/null
EOF
as_user sh -c 'cat > "$HOME/.config/zsh/.zprofile"' <<'EOF'
# Add all directories in `~/.local/bin` to $PATH
export PATH="$PATH:$(find ~/.local/bin -type d | paste -sd ':' -)" # NEEDED FOR DWMBLOCKS
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export TERMINAL="st"
export XINITRC="$XDG_CONFIG_HOME/x11/xinitrc"
export MOZ_USE_XINPUT2=1                  # Mozilla smooth scrolling/touchpads.
# Start graphical server on user's current tty if not already running.
[ "$(tty)" = "/dev/tty1" ] && ! pidof -s Xorg >/dev/null 2>&1 && exec startx "$XINITRC"
EOF

# Laptop detection
laptop=0
has_battery=0
for bat in /sys/class/power_supply/BAT*; do
	[ -e "$bat" ] && has_battery=1 && break
done
if [ "$has_battery" -eq 1 ]; then
	if whiptail \
		--title "Battery detected" \
		--fullbuttons \
		--yesno \
		"This script has detected a battery.\n\nAre you on a laptop?" \
		11 60; then
		laptop=1
	fi
fi

# Resolution detection
detect_vertical() {
	for c in /sys/class/drm/card*-*; do
		[ -r "$c/status" ] || continue
		read -r st < "$c/status" || continue
		[ "$st" = connected ] || continue
		read -r mode < "$c/modes" 2>/dev/null || continue
		v=${mode#*x}
		v=${v%%[!0-9]*}
		[ -n "$v" ] || continue
		printf '%s\n' "$v"
		return 0
	done
	return 1
}

bucket() {
	if   [ "$1" -le 800 ];  then echo 1
	elif [ "$1" -le 1200 ]; then echo 2
	elif [ "$1" -le 1440 ]; then echo 3
	else                         echo 4
	fi
}

pick_resolution() {
	choice=$(whiptail \
		--title "Display scaling" \
		--fullbuttons \
		--default-item "$1" \
		--menu \
		"Select the option matching your display:" \
		16 60 4 \
		1 "800px or less" \
		2 "801px - 1200px" \
		3 "1201px - 1440px" \
		4 "More than 1440px" \
		3>&1 1>&2 2>&3) || choice=""
	case $choice in
		1|2|3|4) printf '%s\n' "$choice" ;;
		*)       echo 1 ;;
	esac
}

vertical=$(detect_vertical) || vertical=""
case $vertical in
	''|*[!0-9]*) vertical=""; resolution=1 ;;
	*)           resolution=$(bucket "$vertical") ;;
esac

if [ -z "$vertical" ]; then
	resolution=$(pick_resolution 1)
else
	whiptail \
		--title "Resolution detected" \
		--fullbuttons \
		--yesno \
		"Detected vertical resolution: ${vertical}px\n\nIs this correct?" \
		11 60
	case $? in
		0) ;;
		1) resolution=$(pick_resolution "$resolution") ;;
		*) resolution=1 ;;
	esac
fi

# Extras
vesktop=0
if whiptail \
	--title "Extras" \
	--fullbuttons \
	--yesno \
	"Would you like to install extras?\n\n(BTOP, musescore3, qBittorrent, Vesktop)" \
	11 60; then
	whiptail \
		--title "Installing" \
		--infobox \
		"Setting up extras..." \
		8 50
pacman -S --needed --noconfirm qbittorrent fuse2 btop >/dev/null 2>&1 ||
	die "Failed to install btop and/or qBittorrent."
as_user mkdir -p "$home/.config/qBittorrent"
as_user curl -fsSL \
	-o "$home/.config/qBittorrent/mocha.qbtheme" \
	"https://github.com/catppuccin/qbittorrent/releases/download/v2.0.1/catppuccin-mocha.qbtheme" ||
	die "Failed to download qBittorrent theme."
as_user sh -c 'cat > "$HOME/.config/qBittorrent/qBittorrent.conf"' <<'EOF'
[Application]
FileLogger\Age=1
FileLogger\AgeType=1
FileLogger\Backup=true
FileLogger\DeleteOld=true
FileLogger\Enabled=true
FileLogger\MaxSizeBytes=66560
FileLogger\Path=/home/@NAME@/.local/share/qBittorrent/logs
GUI\Notifications\TorrentAdded=false

[BitTorrent]
Session\Port=20157
Session\QueueingSystemEnabled=false
Session\SSL\Port=21198
Session\StartPaused=false

[Core]
AutoDeleteAddedTorrentFile=Never

[GUI]
DownloadTrackerFavicon=false
Log\Enabled=false
Qt6\TorrentProperties\FilesListState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x2X\0\0\0\x6\x1\x1\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x81\0\0\0\0\0\0\0\x6\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\0\0\0\x64\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)
Qt6\TorrentProperties\PeerListState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\x1\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\xf@@\0\0\0\x2\0\0\0\xe\0\0\0\x64\0\0\0\x6\0\0\0\x64\0\0\x5\x14\0\0\0\xf\x1\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x81\0\0\0\0\0\0\0\xf\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\xff\xff\xff\xff\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)
Qt6\TorrentProperties\TrackerListState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x4L\0\0\0\v\x1\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x81\0\0\0\0\0\0\0\v\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\xff\xff\xff\xff\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)
Qt6\TransferList\HeaderState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\x1\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0&\t\xfa\xff\x7f?\0\0\0\x1d\0\0\0\x1d\0\0\0\x64\0\0\0\x18\0\0\0\x64\0\0\0\x14\0\0\0\x64\0\0\0\x3\0\0\0\x64\0\0\0\"\0\0\0\x64\0\0\0#\0\0\0\x64\0\0\0!\0\0\0\x64\0\0\0\x17\0\0\0\x64\0\0\0\x19\0\0\0\x64\0\0\0\xe\0\0\0\x64\0\0\0 \0\0\0\x64\0\0\0\x1a\0\0\0\x64\0\0\0\x1b\0\0\0\x64\0\0\0\x15\0\0\0\x64\0\0\0\x12\0\0\0\x64\0\0\0\x10\0\0\0\x64\0\0\0%\0\0\0\x64\0\0\0\x16\0\0\0\x64\0\0\0\0\0\0\0\x64\0\0\0\v\0\0\0\x64\0\0\0\xf\0\0\0\x64\0\0\0$\0\0\0\x64\0\0\0\t\0\0\0\x64\0\0\0\x1c\0\0\0\x64\0\0\0\x1e\0\0\0\x64\0\0\0\x11\0\0\0\x64\0\0\0\r\0\0\0\x64\0\0\0\x13\0\0\0\x64\0\0\0\f\0\0\0\x64\0\0\x3\x84\0\0\0&\x1\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x81\0\0\0\0\0\0\0&\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\0\0\0\x64\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)
StartUpWindowState=Normal

[LegalNotice]
Accepted=true

[MainWindow]
geometry=@ByteArray(\x1\xd9\xd0\xcb\0\x3\0\0\xff\xff\xff\xfd\0\0\0\f\0\0\x4\xfc\0\0\x3\x1c\0\0\0\0\0\0\0\xf\0\0\x4\xf9\0\0\x3\x19\0\0\0\0\0\0\0\0\x5\0\0\0\0\0\0\0\0\xf\0\0\x4\xf9\0\0\x3\x19)

[Meta]
MigrationVersion=8

[Network]
Cookies=@Invalid()

[OptionsDialog]
HorizontalSplitterSizes=111, 642
LastViewedPage=0
Size=@Size(779 591)

[Preferences]
General\CustomUIThemePath=/home/@NAME@/.config/qBittorrent/mocha.qbtheme
General\Locale=en
General\UseCustomUITheme=true

[RSS]
AutoDownloader\DownloadRepacks=true
AutoDownloader\SmartEpisodeFilter=s(\\d+)e(\\d+), (\\d+)x(\\d+), "(\\d{4}[.\\-]\\d{1,2}[.\\-]\\d{1,2})", "(\\d{1,2}[.\\-]\\d{1,2}[.\\-]\\d{4})"

[TorrentProperties]
SplitterSizes="200,471"
Visible=false
EOF
as_user sed -i "s|@NAME@|$name|g" "$home/.config/qBittorrent/qBittorrent.conf" ||
	die "Failed to configure qBittorrent."
as_user curl -fsSL \
	-o "$home/.local/bin/vesktop" \
	"https://vencord.dev/download/vesktop/amd64/appimage" ||
	die "Failed to download Vesktop."
chmod +x "$home/.local/bin/vesktop"
as_user curl -fsSL \
	-o "$home/.local/bin/musescore" \
	"https://github.com/musescore/MuseScore/releases/download/v3.6.2/MuseScore-3.6.2.548021370-x86_64.AppImage" ||
	die "Failed to download musescore."
chmod +x "$home/.local/bin/musescore"
vesktop=1
fi

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

# Install audio
whiptail \
	--title "Installing" \
	--infobox \
	"Setting up audio..." \
	8 50
pacman -S --needed --noconfirm wireplumber pipewire-pulse pulsemixer >/dev/null 2>&1 ||
	die "Failed to install audio."
wpctl set-volume @DEFAULT_SINK@ 70%

# Create pipewire exec
as_user mkdir -p "$home/.config/pipewire/pipewire.conf.d"
as_user sh -c 'cat > "$HOME/.config/pipewire/pipewire.conf.d/user-session.conf"' <<'EOF'
context.exec = [
    { path = "/usr/bin/wireplumber" args = "" condition = [ { exec.session-manager = null } { exec.session-manager = true } ] }
    { path = "/usr/bin/pipewire" args = "-c pipewire-pulse.conf" condition = [ { exec.pipewire-pulse = null } { exec.pipewire-pulse = true } ] }
]
EOF

# X dependencies 
whiptail \
	--title "Installing" \
	--infobox \
	"Setting up X dependencies..." \
	8 50

pacman -S --needed --noconfirm libxinerama xorg-xbacklight xorg-xrandr xwallpaper libxft xorg-xinit libx11 xorg-xset freetype2 fontconfig harfbuzz xcompmgr openssh >/dev/null 2>&1 ||
	die "Failed to install X dependencies."
as_user mkdir -p "$home/.config/x11"
as_user sh -c 'cat > "$HOME/.config/x11/xinitrc"' <<'EOF'
#!/bin/sh
# Key Repeat / Auto-repeat behavior
xset r rate 400 32
xrandr --dpi 96

# Example Monitor config
#xrandr \
#  --output HDMI-0 --mode 2560x1440 --rate 240 --primary --pos 0x0 \
#  --output DP-0 --mode 2560x1440 --rate 165 --pos 2560x0

# Set wallpaper on start
setbg &

# xprofile
[ -r "$HOME/.config/x11/xprofile" ] &&
	. "$HOME/.config/x11/xprofile"

# Activate dbus variables
dbus-update-activation-environment --all

# Disable unused accessibility services
pkill -f '^/usr/lib/at-spi2-registryd'
pkill -f '^/usr/lib/at-spi-bus-launcher'
export NO_AT_BRIDGE=1 GTK_A11Y=none

# Launch DWM
dbus-launch ssh-agent dwm
EOF

# Additional GTK accessibility fix
as_user mkdir -p "$home/.local/share/dbus-1/services"
as_user sh -c 'cat > "$HOME/.local/share/dbus-1/services/org.a11y.Bus.service"' <<'EOF'
[D-BUS Service]
Name=org.a11y.Bus
Exec=/bin/false
EOF

as_user sh -c 'cat > "$HOME/.config/x11/xprofile"' <<'EOF'
#!/bin/sh
for program in xcompmgr dunst unclutter pipewire; do
	pidof -sx "$program" >/dev/null 2>&1 && continue
	"$program" >/dev/null 2>&1 &
done

# Volume block fix
(
	while ! pidof -sx dwmblocks >/dev/null 2>&1; do sleep 1; done
	pkill -RTMIN+10 dwmblocks
) &
EOF

# Fonts
whiptail \
	--title "Installing" \
	--infobox \
	"Installing fonts..." \
	8 50
git clone --depth 1 https://github.com/sunaku/tamzen-font.git "$TMPDIR/tamzen-font" >/dev/null 2>&1 ||
	die "Failed to clone tamzen-font."
mkdir -p /usr/local/share/fonts/tamzen ||
	die "Failed to create the Tamzen font directory."
cp "$TMPDIR"/tamzen-font/pcf/*.pcf \
   "$TMPDIR"/tamzen-font/otb/*.otb \
   "$TMPDIR"/tamzen-font/ttf/*.ttf \
   /usr/local/share/fonts/tamzen/ ||
	die "Failed to copy the Tamzen fonts."
mkdir -p /etc/fonts/conf.d/
rm -f /etc/fonts/conf.d/70-no-bitmaps*.conf
ln -sf /usr/share/fontconfig/conf.avail/70-yes-bitmaps.conf /etc/fonts/conf.d/70-yes-bitmaps.conf
sh -c 'cat > "/etc/fonts/conf.d/60-tamzen.conf"' <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer><family>Tamzen</family></prefer>
  </alias>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Tamzen</family></prefer>
  </alias>
</fontconfig>
EOF

pacman -S --needed --noconfirm ttf-sarasa-gothic >/dev/null 2>&1 ||
	die "Failed to install CJK font."

fc-cache -f >/dev/null 2>&1 ||
	die "Failed to update the font cache."

# Suckless software
whiptail \
	--title "Installing" \
	--infobox \
	"Building dwm, dwmblocks, dmenu and st..." \
	8 50

as_user mkdir -p "$home/.local/src"

for repo in dwm-6.8 dmenu st dwmblocks; do
	dest="$home/.local/src/$repo"

# Clone as the user so everything stays user-owned
as_user env GIT_TERMINAL_PROMPT=0 \
	git clone --depth 1 "https://github.com/pm-lack/$repo" "$dest" >/dev/null 2>&1 ||
	die "Failed to clone $repo."

# Enable the battery block on laptops
if [ "$repo" = "dwmblocks" ] && [ "$laptop" -eq 1 ]; then
	as_user sed -i '/sb-battery/{s|/\* *||;s| *\*/||;}' "$dest/config.h" ||
		die "Failed to edit the dwmblocks config."
	grep -q '^[[:space:]]*{.*sb-battery' "$dest/config.h" ||
		die "Failed to enable the battery block."
fi

# Scale the fonts
if [ "$resolution" -gt 1 ]; then
	case $resolution in
		2) fontsize=13 ;;
		3) fontsize=18 ;;
		4) fontsize=27 ;;
	esac
	case $repo in
		dwm-6.8)   cfg="$dest/config.def.h" ;;
		st|dmenu)  cfg="$dest/config.h" ;;
		*)         cfg="" ;;
	esac
	if [ -n "$cfg" ]; then
		as_user sed -i "s|\(Misc Tamzen:size=\)[0-9][0-9]*|\1${fontsize}|g" "$cfg" ||
			die "Failed to edit the $repo font size."
		grep -q "Misc Tamzen:size=${fontsize}" "$cfg" ||
			die "Failed to set the $repo font size."
	fi
fi

# Add Discord keybind
if [ "$repo" = "dwm-6.8" ] && [ "$vesktop" -eq 1 ]; then
	as_user sed -i \
		-e '/^#define THUNAR /s~$~\n#define DISCORD "vesktop"~' \
		-e '/XK_t,.*THUNAR/s~$~\n\t{ MODKEY|ShiftMask,\t\tXK_v,          spawn,                  {.v = (const char*[]){ DISCORD, NULL } } },~' \
		"$dest/config.def.h" ||
		die "Failed to edit the dwm config."
	grep -q '^#define DISCORD "vesktop"' "$dest/config.def.h" ||
		die "Failed to add the DISCORD define."
	grep -q 'XK_v,.*DISCORD' "$dest/config.def.h" ||
		die "Failed to add the DISCORD keybind."
fi

# Build as the user so build files stay user-owned; install as root
as_user make -C "$dest" clean >/dev/null 2>&1 &&
    as_user make -C "$dest" >/dev/null 2>&1 ||
    die "Failed to build $repo."
make -C "$dest" install >/dev/null 2>&1 ||
    die "Failed to install $repo."
done

# Creating blocks
whiptail \
	--title "Installing" \
	--infobox \
	"Creating blocks..." \
	8 50
sleep 1
as_user mkdir -p "$home/.local/bin/statusbar"
as_user sh -c 'cat > "$HOME/.local/bin/statusbar/sb-volume"' <<'EOF'
#!/bin/sh
PATH="/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin"
export PATH
case $BLOCK_BUTTON in
	1) setsid -f st -e pulsemixer ;;
	2) wpctl set-mute @DEFAULT_SINK@ toggle ;;
	4) wpctl set-volume @DEFAULT_SINK@ 1%+ ;;
	5) wpctl set-volume @DEFAULT_SINK@ 1%- ;;
esac
vol=$(wpctl get-volume @DEFAULT_SINK@) || exit 1
case "$vol" in
	*"MUTED"*) echo "[mute]"; exit ;;
esac
vol=${vol#Volume: }
vol=$(awk -v v="$vol" 'BEGIN { printf "%.0f", v * 100 }')
echo "[vol:$vol%]"
EOF
as_user sh -c 'cat > "$HOME/.local/bin/statusbar/sb-clock"' <<'EOF'
#!/bin/sh
date '+[%m-%d %H:%M]'
EOF
as_user sh -c 'cat > "$HOME/.local/bin/statusbar/sb-internet"' <<'EOF'
#!/bin/sh
case $BLOCK_BUTTON in
1) "$TERMINAL" -e nmtui; pkill -RTMIN+4 "${STATUSBAR:-dwmblocks}" ;;
3) notify-send "internet status" "click: open NetworkManager
wifi: wireless signal strength (%)
eth: wired connection
off: no active connection" ;;
6) setsid -f "$TERMINAL" -e "$EDITOR" "$0" ;;
esac

wifi=""
ethernet=""
for iface in /sys/class/net/*; do
	dev=${iface##*/}
	# Skip loopback and virtual interfaces (docker, tun, bridges, ...)
	[ "$dev" = lo ] && continue
	[ -e "$iface/device" ] || continue
	[ "$(cat "$iface/operstate" 2>/dev/null)" = up ] || continue
	if [ -d "$iface/wireless" ] || [ -d "$iface/phy80211" ]; then
		signal=$(awk -v d="$dev:" '$1 == d {
			q = $3; sub(/\./, "", q)
			s = int(q * 100 / 70); if (s > 100) s = 100
			print s; exit
		}' /proc/net/wireless 2>/dev/null)
		wifi="${signal:-0}%"
	else
		ethernet="eth"
	fi
done

status="$wifi"
[ -n "$ethernet" ] && status="${status:+$status }$ethernet"
printf '%s\n' "${status:-off}"
EOF
# Laptop only script
if [ "$laptop" -eq 1 ]; then
as_user sh -c 'cat > "$HOME/.local/bin/statusbar/sb-battery"' <<'EOF'
#!/bin/sh
BAT_PATH="/sys/class/power_supply/BAT0"
if [ -f "$BAT_PATH/capacity" ]; then
    PERCENT=$(cat "$BAT_PATH/capacity")
    echo "[bat:${PERCENT}%]"
else
    echo "[bat:N/A]"
fi
EOF
fi
# Make blocks runable
chmod +x "$home"/.local/bin/statusbar/sb-*

# TLP (laptops only)
if [ "$laptop" -eq 1 ]; then
whiptail \
--title "Installing" \
--infobox \
	"Setting up laptop power management..." \
	8 50
pacman -S --needed --noconfirm tlp-runit >/dev/null 2>&1 ||
	die "Failed to install TLP."
ln -sf /etc/runit/sv/tlp /etc/runit/runsvdir/default/ ||
	die "Failed to enable TLP."
fi

# Enable tap to click (laptops only)
if [ "$laptop" -eq 1 ] && [ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ]; then
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/40-libinput.conf <<'EOF'
Section "InputClass"
	Identifier "libinput touchpad catchall"
	MatchIsTouchpad "on"
	MatchDevicePath "/dev/input/event*"
	Driver "libinput"
	# Enable left mouse button by tapping
	Option "Tapping" "on"
EndSection
EOF
fi

# Install librewolf
whiptail \
	--title "Installing" \
	--infobox \
	"Setting up LibreWolf.\n\nThis may take a while..." \
	9 50
pacman -S --needed --noconfirm librewolf >/dev/null 2>&1 ||
	die "Failed to install LibreWolf."
lwdir="$home/.config/librewolf/librewolf"

# Start LibreWolf headless once so it generates a profile
as_user env HOME="$home" XDG_CONFIG_HOME="$home/.config" \
	librewolf --headless >/dev/null 2>&1 &

# Wait for the profile to be generated
i=0
while [ "$i" -lt 30 ] && [ ! -f "$lwdir/profiles.ini" ]; do
	i=$((i + 1))
	sleep 1
done

# Give it a moment to finish writing, then stop the throwaway instance
sleep 2
pkill -u "$name" -f librewolf
sleep 1

[ -f "$lwdir/profiles.ini" ] ||
	die "LibreWolf did not generate a profile."

# Prefer the profile this install actually uses, else the first one listed
profile=$(sed -n '/^\[Install/,/^\[Profile/ s/^Default=//p' "$lwdir/profiles.ini" | head -n 1)
[ -n "$profile" ] ||
	profile=$(sed -n 's/^Path=//p' "$lwdir/profiles.ini" | head -n 1)

case "$profile" in
	/*) pdir="$profile" ;;
	*)  pdir="$lwdir/$profile" ;;
esac

[ -n "$profile" ] && [ -d "$pdir" ] ||
	die "Could not locate the LibreWolf profile."

# FirefoxCSS theme
#GIT_TERMINAL_PROMPT=0 git clone --depth 1 \
#	https://github.com/Bali10050/FirefoxCSS "$TMPDIR/FirefoxCSS" >/dev/null 2>&1 ||
#	die "Failed to clone FirefoxCSS."
#mkdir -p "$pdir/chrome"
#cp -a "$TMPDIR/FirefoxCSS/chrome/." "$pdir/chrome/" ||
#	die "Failed to copy the FirefoxCSS theme."
#chown -R "$name": "$pdir/chrome"

# FoxOne theme
GIT_TERMINAL_PROMPT=0 git clone --depth 1 \
	https://github.com/Firnschnee/FoxOne "$TMPDIR/FoxOne" >/dev/null 2>&1 ||
	die "Failed to clone FoxOne."
mkdir -p "$pdir/chrome"
cp -a "$TMPDIR/FoxOne/chrome/." "$pdir/chrome/" ||
	die "Failed to copy the FoxOne theme."
chown -R "$name": "$pdir/chrome"

# Extensions (sideloaded into the profile)
mkdir -p "$pdir/extensions"
while read -r slug id; do
	curl -fsSL \
		-o "$pdir/extensions/$id.xpi" \
		"https://addons.mozilla.org/firefox/downloads/latest/$slug/latest.xpi" ||
		die "Failed to download the $slug extension."
done <<'EOF'
dollchan_extension dollchan_extension@dollchan.net
EOF
chown -R "$name": "$pdir/extensions"

# Betterfox-based prefs
curl -fsSL \
	-o "$TMPDIR/betterfox-user.js" \
	https://raw.githubusercontent.com/pm-lack/pm-betterfox.js/refs/heads/main/user.js ||
	die "Failed to download the LibreWolf user.js."
as_user sh -c 'cat > "$1/user.js"' sh "$pdir" < "$TMPDIR/betterfox-user.js"

# Pomni-specific prefs
as_user sh -c 'cat >> "$1/user.js"' sh "$pdir" <<'EOF'
 
/** pomni overrides ***/
user_pref("browser.toolbars.bookmarks.visibility", "never");
user_pref("browser.download.autohideButton", true);
user_pref("browser.tabs.tabmanager.enabled", false);
user_pref("svg.context-properties.content.enabled", true);
user_pref("layout.css.has-selector.enabled", true);
user_pref("extensions.autoDisableScopes", 0);
user_pref("browser.uidensity", 1);
user_pref("privacy.clearOnShutdown_v2.cookiesAndStorage", false);
user_pref("privacy.clearOnShutdown.cookies", false);
user_pref("privacy.clearOnShutdown.offlineApps", false);
user_pref("privacy.clearOnShutdown.sessions", false);
user_pref("accessibility.force_disabled", 1);
user_pref("gfx.use_text_smoothing_setting", false);
user_pref("layout.css.osx-font-smoothing.enabled", false);
user_pref("media.mediacapabilities.webrtc-encode-smooth-override", 0);
user_pref("toolkit.scrollbox.smoothScroll", true);
user_pref("fission.webContentIsolationStrategy", 2);
user_pref("dom.ipc.processCount", 6);
user_pref("dom.ipc.processPrelaunch.enabled", false);
user_pref("browser.sessionhistory.max_total_viewers", 3);
user_pref("browser.sessionhistory.max_entries", 25);
user_pref("image.mem.surfacecache.max_size_kb", 262144);
user_pref("browser.sessionstore.max_tabs_undo", 15);
user_pref("browser.startup.page", 3);
user_pref("privacy.resistFingerprinting", false);
user_pref("layout.css.font-visibility.resistFingerprinting", 3);
user_pref("layout.css.prefers-color-scheme.content-override", 0);

/** DRM / Widevine ***/
user_pref("media.eme.enabled", true);
user_pref("media.gmp-provider.enabled", true);
user_pref("media.gmp-widevinecdm.visible", true);
user_pref("media.gmp-widevinecdm.enabled", true);
user_pref("media.gmp-widevinecdm.autoupdate", true);
EOF


# Homepage
as_user sh -c 'cat >> "$1/prefs.js"' sh "$pdir" <<'EOF'
user_pref("browser.startup.homepage", "https://lackthereof.xyz/");
user_pref("browser.startup.page", 1);
EOF

# Square corners tweak / Remove All Tabs button
as_user sh -c 'cat >> "$1/chrome/userChrome.css"' sh "$pdir" <<'EOF'
 
* { border-radius: 0px !important; }
#alltabs-button { display: none !important; }
EOF

# Fix for extensions not loading on first launch
as_user env HOME="$home" XDG_CONFIG_HOME="$home/.config" \
	librewolf --headless >/dev/null 2>&1 &
i=0
while [ "$i" -lt 30 ]; do
	if grep -q 'dollchan_extension@dollchan.net' "$pdir/extensions.json" 2>/dev/null; then
		break
	fi
	i=$((i + 1))
	sleep 1
done
sleep 3
pkill -u "$name" -f librewolf
sleep 1

# Install utilities
whiptail \
	--title "Installing" \
	--infobox \
	"Setting up utilities.\n\nThis may take a while..." \
	9 50

pacman -S --needed --noconfirm lf ueberzugpp adw-gtk-theme mousepad vim libnotify dunst nsxiv ffmpeg ffmpegthumbnailer tumbler mpv maim tesseract tesseract-data-eng unclutter xclip thunar tumbler fastfetch xdg-user-dirs >/dev/null 2>&1 ||
	die "Failed to install utilities."

# Make and pin user directories
as_user sh -c '
	xdg-user-dirs-update
	. "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
	bm="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/bookmarks"
	mkdir -p "$(dirname "$bm")"
	touch "$bm"
	for dir in "$XDG_DOCUMENTS_DIR" "$XDG_DOWNLOAD_DIR" "$XDG_MUSIC_DIR" \
	           "$XDG_PICTURES_DIR" "$XDG_VIDEOS_DIR"; do
		line="file://$dir"
		grep -qxF "$line" "$bm" || echo "$line" >> "$bm"
	done
' || die "Failed to set up the user directories."

# Dunst
as_user mkdir -p "$home/.config/dunst"
case $resolution in
	2) dunstfont=13 ;;
	3) dunstfont=14 ;;
	4) dunstfont=15 ;;
	*) dunstfont=12 ;;
esac
as_user sh -c 'cat > "$HOME/.config/dunst/dunstrc"' <<'EOF'
[global]
    monitor = 0
    follow = keyboard
    width = 370
    offset = 0x19
    padding = 2
    horizontal_padding = 2
    frame_width = 3
    frame_color = "#e4e4e4"
    transparency = 25
    font = Monospace @SIZE@
    format = "<b>%s</b>\n%b"
    background = "#222222"
    foreground = "#cdd6f4"
[urgency_low]
    foreground = "#bbbbbb"
    timeout = 3
[urgency_normal]
    timeout = 5
[urgency_critical]
    frame_color = "#f5c2e7"
    timeout = 10
EOF
as_user sed -i "s|@SIZE@|$dunstfont|g" "$home/.config/dunst/dunstrc" ||
	die "Failed to configure dunst."

# GTK 4 Dark Theme
as_user gsettings set org.gnome.desktop.interface color-scheme prefer-dark

# Wallpaper
as_user sh -c 'cat > "$HOME/.local/bin/setbg"' <<'EOF'
#!/bin/sh
# Location of link to wallpaper link.
bgloc="${XDG_DATA_HOME:-$HOME/.local/share}/bg"
trueloc="$(readlink -f "$1")" &&
case "$(file --mime-type -b "$trueloc")" in
	image/* ) ln -sf "$trueloc" "$bgloc" ;;
	inode/directory ) ln -sf "$(find "$trueloc" -iregex '.*.\(jpg\|jpeg\|png\|gif\)' -type f | shuf -n 1)" "$bgloc" ;;
	*) exit 1 ;;
esac
xwallpaper --zoom "$bgloc"
EOF
chmod +x "$home"/.local/bin/setbg
as_user mkdir -p "$home/Pictures/wallpaper"
as_user curl -fsSL -o "$home/Pictures/wallpaper/eva.jpg" \
	"https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/eva.jpg"
as_user mkdir -p "$home/.local/share"
as_user ln -sf "$home/Pictures/wallpaper/eva.jpg" "$home/.local/share/bg"

# Fastfetch
as_user mkdir -p "$home/.config/fastfetch"
as_user sh -c 'cat > "$HOME/.config/fastfetch/config.jsonc"' <<'EOF'
{ "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json", "modules": [ "title", "separator", "os", "kernel", "uptime", "packages", "cpu", "wm", "memory", "colors" ] }
EOF
as_user sh -c 'cat > "$HOME/.config/fastfetch/rose_ascii.txt"' <<'EOF'
$1           ,
$1       .--'|}
$1      /    /}}
$1    .=$1\.--'`\}
$1   //`$1 '---./`
$1   ||  /|
$1    \\| |
$1  |\_\\/
$1  \__/\\
$1       \\
$1        \|
EOF

# lfub
as_user sh -c 'cat > "$HOME/.local/bin/lfub"' <<'EOF'
#!/bin/sh
# lf with image previews via ueberzugpp.
set -e
cleanup() {
	exec 3>&-
	if [ -n "$UEBERZUG_PID" ]; then
		kill "$UEBERZUG_PID" 2>/dev/null || true
	fi
	rm -f "$FIFO_UEBERZUG"
}
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
	exec lf "$@"
fi
mkdir -p "$HOME/.cache/lf"
export FIFO_UEBERZUG="$HOME/.cache/lf/ueberzug-$$"
mkfifo "$FIFO_UEBERZUG"
trap cleanup HUP INT QUIT TERM EXIT
ueberzugpp layer -s -o x11 -p json <"$FIFO_UEBERZUG" &
UEBERZUG_PID=$!
exec 3>"$FIFO_UEBERZUG"
lf "$@" 3>&-
EOF
chmod +x "$home"/.local/bin/lfub
as_user mkdir -p "$home/.config/lf"
as_user sh -c 'cat > "$HOME/.config/lf/cleaner"' <<'EOF'
#!/bin/sh
if [ -n "$FIFO_UEBERZUG" ]; then
	printf '{"action": "remove", "identifier": "PREVIEW"}\n' > "$FIFO_UEBERZUG"
fi
EOF
chmod +x "$home"/.config/lf/cleaner
as_user sh -c 'cat > "$HOME/.config/lf/scope"' <<'EOF'
#!/bin/sh
# lf previewer. Args: $1 file, $2 width, $3 height, $4 x, $5 y
set -C -f
IFS="$(printf '%b_' '\n')"; IFS="${IFS%_}"
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/lf"
# Sets $CACHE to a per-file thumbnail path (without extension).
cache() {
	CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/lf/thumb.$(stat --printf '%n\0%i\0%F\0%s\0%W\0%Y' -- "$(readlink -f "$1")" | md5sum)"
	CACHE="${CACHE%% *}"
}
# image PATH W H X Y ORIGINAL
image() {
	if [ -f "$1" ] && [ -n "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ] && [ -n "$FIFO_UEBERZUG" ]; then
		printf '{"action": "add", "identifier": "PREVIEW", "x": "%s", "y": "%s", "width": "%s", "height": "%s", "scaler": "contain", "path": "%s"}\n' "$4" "$5" "$(($2-1))" "$(($3-1))" "$1" > "$FIFO_UEBERZUG"
	else
		ffprobe -hide_banner "$6" 2>&1
	fi
}
case "$(file --dereference --brief --mime-type -- "$1")" in
	image/svg+xml) head -n 100 -- "$1" ;;
	image/vnd.djvu | image/x-xcf) file --brief -- "$1" ;;
	image/*) image "$1" "$2" "$3" "$4" "$5" "$1" ;;
	video/*)
		cache "$1"
		[ -f "$CACHE.jpg" ] || ffmpegthumbnailer -i "$1" -o "$CACHE.jpg" -s 0 >/dev/null 2>&1
		image "$CACHE.jpg" "$2" "$3" "$4" "$5" "$1" ;;
	audio/*) ffprobe -hide_banner "$1" 2>&1 ;;
	text/* | */xml | application/json | application/x-ndjson) head -n 200 -- "$1" ;;
	application/zip | application/x-tar | application/gzip | application/x-xz | application/zstd | application/x-bzip2 | application/x-7z-compressed | application/vnd.rar)
		bsdtar -tf "$1" ;;
	*) file --brief -- "$1" ;;
esac
# Non-zero exit tells lf not to cache the preview, so images are redrawn.
exit 1
EOF
chmod +x "$home"/.config/lf/scope
as_user sh -c 'cat > "$HOME/.config/lf/lfrc"' <<'EOF'
set shellopts '-eu'
set ifs "\n"
set scrolloff 10
set period 1
set hiddenfiles ".*"
set cleaner '~/.config/lf/cleaner'
set previewer '~/.config/lf/scope'
set autoquit true
cmd open ${{
	case "$(file --mime-type -b "$(readlink -f "$f")")" in
		text/*|application/json|inode/x-empty|application/x-subrip) ${EDITOR:-vi} $fx ;;
		application/pdf|image/svg+xml) setsid -f librewolf $fx >/dev/null 2>&1 ;;
		image/*) setsid -f nsxiv -a -- $fx >/dev/null 2>&1 ;;
		audio/*) mpv --audio-display=no $fx ;;
		video/*) setsid -f mpv -quiet $fx >/dev/null 2>&1 ;;
		*) notify-send "lf" "No opener for: $(file -b "$f")" ;;
	esac
}}
map b $setbg "$f"
map m $mpv $f
EOF

# GTK
as_user mkdir -p "$home/.config/gtk-3.0"
case $resolution in
	2) gtkfont=12 ;;
	3) gtkfont=13 ;;
	4) gtkfont=14 ;;
	*) gtkfont=11 ;;
esac
as_user sh -c 'cat > "$HOME/.config/gtk-3.0/settings.ini"' <<EOF
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Adwaita
gtk-font-name=Tamzen ${gtkfont}
gtk-cursor-theme-size=0
gtk-toolbar-style=GTK_TOOLBAR_TEXT
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=1
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintfull
gtk-xft-rgba=rgb
gtk-cursor-theme-name=Adwaita
gtk-application-prefer-dark-theme=true
EOF
as_user sh -c 'cat > "$HOME/.config/gtk-3.0/gtk.css"' <<'EOF'
@define-color theme_bg_color #424242;
@define-color theme_base_color #424242;
@define-color theme_fg_color #e4e4e4;
@define-color theme_text_color #e4e4e4;
@define-color theme_selected_bg_color #575757;
@define-color theme_selected_fg_color #e4e4e4;
EOF

# Host blocker
whiptail \
	--title "Installing" \
	--infobox \
	"Setting up host blocker..." \
	8 50

curl -fsSL \
	-o "$TMPDIR/hosts" \
	https://raw.githubusercontent.com/pm-lack/hosts/refs/heads/master/hosts ||
	die "Failed to download the hosts file."
[ -s "$TMPDIR/hosts" ] ||
	die "The downloaded hosts file is empty."

# Drop any block from a previous run, then append the fresh one
sed -i '/^# BEGIN pomni hosts$/,/^# END pomni hosts$/d' /etc/hosts
{
	printf '\n# BEGIN pomni hosts\n'
	cat "$TMPDIR/hosts"
	printf '\n# END pomni hosts\n'
} >> /etc/hosts
sleep 1

# Beep fix
rmmod pcspkr >/dev/null 2>&1 || true
echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf

# Finished
whiptail \
	--title "Finished" \
	--fullbuttons \
	--msgbox \
	"Success! Please reboot." \
	9 50

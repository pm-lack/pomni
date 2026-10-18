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

# Sudo fix
printf '%s\n' '%wheel ALL=(ALL) NOPASSWD: ALL' \
	>/etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Zsh config
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
alias lf='lfub'

# Fetch
fastfetch -l ~/.config/fastfetch/rose_ascii.txt

# Load zsh plugins; should be last.
source /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh 2>/dev/null
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh 2>/dev/null
EOF
sudo -u "$name" sh -c 'cat > "$HOME/.config/zsh/.zprofile"' <<'EOF'
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

# Create pipewire exec
sudo -u "$name" mkdir -p "$home/.config/pipewire/pipewire.conf.d"
sudo -u "$name" sh -c 'cat > "$HOME/.config/pipewire/pipewire.conf.d/user-session.conf"' <<'EOF'
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

pacman -S --needed --noconfirm libxinerama xorg-xrandr xwallpaper libxft xorg-xinit libx11 freetype2 fontconfig harfbuzz xcompmgr openssh >/dev/null 2>&1 ||
	die "Failed to install X dependencies."
sudo -u "$name" mkdir -p "$home/.config/x11"
sudo -u "$name" sh -c 'cat > "$HOME/.config/x11/xinitrc"' <<'EOF'
#!/bin/sh
# Key Repeat / Auto-repeat behavior
xset r rate 400 32

# xprofile
[ -r "$HOME/.config/x11/xprofile" ] &&
	. "$HOME/.config/x11/xprofile"

# Activate dbus variables
dbus-update-activation-environment --all
dbus-launch ssh-agent dwm
EOF
sudo -u "$name" sh -c 'cat > "$HOME/.config/x11/xprofile"' <<'EOF'
#!/bin/sh
xrandr --dpi 96		# Set DPI. User may want to use a larger number for larger screens.
setbg &
autostart="xcompmgr dunst unclutter pipewire"

for program in $autostart; do
	pidof -sx "$program" || "$program" &
	
done >/dev/null 2>&1
#Volume block fix
(
while ! pidof -sx dwmblocks >/dev/null 2>&1; do
sleep 1
done
pkill -RTMIN+10 dwmblocks
) &
EOF

# Tamzen font
whiptail \
	--title "Installing" \
	--infobox \
	"Installing tamzen font..." \
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

fc-cache -f >/dev/null 2>&1 ||
	die "Failed to update the font cache."

# Suckless software
whiptail \
	--title "Installing" \
	--infobox \
	"Building dwm, dwmblocks, dmenu and st..." \
	8 50

sudo -u "$name" mkdir -p "$home/.local/src"

for repo in dwm-6.8 dmenu st dwmblocks; do
	dest="$home/.local/src/$repo"

	# Clone as the user so everything stays user-owned
	sudo -u "$name" env GIT_TERMINAL_PROMPT=0 \
		git clone --depth 1 "https://github.com/pm-lack/$repo" "$dest" >/dev/null 2>&1 ||
		die "Failed to clone $repo."

	# Build as the user; sudo only for the install step
	sudo -u "$name" sudo make -C "$dest" clean install >/dev/null 2>&1 ||
		die "Failed to build and install $repo."
done

# Creating blocks
whiptail \
	--title "Installing" \
	--infobox \
	"Creating blocks..." \
	8 50
sleep 1
sudo -u "$name" mkdir -p "$home/.local/bin/statusbar"
sudo -u "$name" sh -c 'cat > "$HOME/.local/bin/statusbar/sb-volume"' <<'EOF'
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
sudo -u "$name" sh -c 'cat > "$HOME/.local/bin/statusbar/sb-clock"' <<'EOF'
#!/bin/sh
date '+[%m-%d %H:%M]'
EOF
sudo -u "$name" sh -c 'cat > "$HOME/.local/bin/statusbar/sb-internet"' <<'EOF'
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
sudo -u "$name" sh -c 'cat > "$HOME/.local/bin/statusbar/sb-battery"' <<'EOF'
BAT_PATH="/sys/class/power_supply/BAT0"
if [ -f "$BAT_PATH/capacity" ]; then
    PERCENT=$(cat "$BAT_PATH/capacity")
    echo "[bat:${PERCENT}%]"
else
    echo "[bat:N/A]"
fi
EOF

# Make blocks runable
chmod +x "$home"/.local/bin/statusbar/sb-*

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
sudo -u "$name" env HOME="$home" XDG_CONFIG_HOME="$home/.config" \
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
GIT_TERMINAL_PROMPT=0 git clone --depth 1 \
	https://github.com/Bali10050/FirefoxCSS "$TMPDIR/FirefoxCSS" >/dev/null 2>&1 ||
	die "Failed to clone FirefoxCSS."
mkdir -p "$pdir/chrome"
cp -a "$TMPDIR/FirefoxCSS/chrome/." "$pdir/chrome/" ||
	die "Failed to copy the FirefoxCSS theme."
chown -R "$name": "$pdir/chrome"

# Extensions (sideloaded into the profile)
mkdir -p "$pdir/extensions"
while read -r slug id; do
	curl -fsSL \
		-o "$pdir/extensions/$id.xpi" \
		"https://addons.mozilla.org/firefox/downloads/latest/$slug/latest.xpi" ||
		die "Failed to download the $slug extension."
done <<'EOF'
darkreader addon@darkreader.org
dollchan_extension dollchan_extension@dollchan.net
EOF
chown -R "$name": "$pdir/extensions"

# Prefs the theme needs
sudo -u "$name" sh -c 'cat >> "$1/user.js"' sh "$pdir" <<'EOF'
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("svg.context-properties.content.enabled", true);
user_pref("layout.css.has-selector.enabled", true);
user_pref("extensions.autoDisableScopes", 0);
user_pref("browser.uidensity", 1);
EOF

# Betterfox-based prefs
curl -fsSL \
	-o "$TMPDIR/betterfox-user.js" \
	https://raw.githubusercontent.com/pm-lack/pm-betterfox.js/refs/heads/main/user.js ||
	die "Failed to download the LibreWolf user.js."
{ printf '\n'; cat "$TMPDIR/betterfox-user.js"; } |
	sudo -u "$name" sh -c 'cat >> "$1/user.js"' sh "$pdir"

echo "* { border-radius: 0px !important; }" >> "$pdir/chrome/userChrome.css"

# Install utilities
whiptail \
	--title "Installing" \
	--infobox \
	"Setting up utilities.\n\nThis may take a while..." \
	9 50

pacman -S --needed --noconfirm lf ueberzugpp adw-gtk-theme mousepad vim libnotify dunst nsxiv ffmpeg ffmpegthumbnailer tumbler mpv maim unclutter xclip thunar tumbler fastfetch >/dev/null 2>&1 ||
	die "Failed to install utilities."

# Wallpaper
sudo -u "$name" sh -c 'cat > "$HOME/.local/bin/setbg"' <<'EOF'
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
sudo -u "$name" mkdir -p "$home/Pictures/wallpaper"
sudo -u "$name" curl -fsSL -o "$home/Pictures/wallpaper/eva.jpg" \
	"https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/eva.jpg"
sudo -u "$name" mkdir -p "$home/.local/share"
sudo -u "$name" ln -sf "$home/Pictures/wallpaper/eva.jpg" "$home/.local/share/bg"

# Fastfetch
sudo -u "$name" mkdir -p "$home/.config/fastfetch"
sudo -u "$name" sh -c 'cat > "$HOME/.config/fastfetch/config.jsonc"' <<'EOF'
{ "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json", "modules": [ "title", "separator", "os", "kernel", "uptime", "packages", "cpu", "wm", "memory", "colors" ] }
EOF
sudo -u "$name" sh -c 'cat > "$HOME/.config/fastfetch/rose_ascii.txt"' <<'EOF'
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
sudo -u "$name" sh -c 'cat > "$HOME/.local/bin/lfub"' <<'EOF'
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
sudo -u "$name" mkdir -p "$home/.config/lf"
sudo -u "$name" sh -c 'cat > "$HOME/.config/lf/cleaner"' <<'EOF'
#!/bin/sh
if [ -n "$FIFO_UEBERZUG" ]; then
	printf '{"action": "remove", "identifier": "PREVIEW"}\n' > "$FIFO_UEBERZUG"
fi
EOF
chmod +x "$home"/.config/lf/cleaner
sudo -u "$name" sh -c 'cat > "$HOME/.config/lf/scope"' <<'EOF'
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
sudo -u "$name" sh -c 'cat > "$HOME/.config/lf/lfrc"' <<'EOF'
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
sudo -u "$name" mkdir -p "$home/.config/gtk-3.0"
sudo -u "$name" sh -c 'cat > "$HOME/.config/gtk-3.0/settings.ini"' <<'EOF'
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Adwaita
gtk-font-name=Tamzen 11
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
EOF
sudo -u "$name" sh -c 'cat > "$HOME/.config/gtk-3.0/gtk.css"' <<'EOF'
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

# Beep fix
rmmod pcspkr
echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf

# Finished
whiptail \
	--title "Finished" \
	--fullbuttons \
	--msgbox \
	"Success! Please reboot." \
	9 50

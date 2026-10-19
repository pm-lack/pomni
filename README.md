## pm’s Opinionated Minimal Nest Installer (pomni)
![ScreenShot](https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/screenshot.png)
Pomni is a post-install setup script intended for use on artix-base-runit.
What it does:
- Creates a new user (or reconfigures an existing one), sets the password, adds them to wheel, and sets zsh as the login shell
- Configures zsh with a custom prompt, history, completion, autosuggestions, fast-syntax-highlighting and a fastfetch greeting
- Adds the XLibre [repository](https://github.com/xlibre-artix/xlibre-artix) and signing key, then installs [XLibre](https://github.com/X11Libre/xserver) as the X server
- Installs and configures PipeWire and WirePlumber with PulseAudio compatibility
- Builds and installs pre-patched [dwm](https://github.com/pm-lack/dwm-6.8), [dmenu](https://github.com/pm-lack/dmenu), [st](https://github.com/pm-lack/st) and [dwmblocks](https://github.com/pm-lack/dwmblocks) from source, with statusbar blocks for volume, battery (must be enabled manually), clock, and network
- Installs LibreWolf with a custom [FirefoxCSS](https://github.com/Bali10050/FirefoxCSS) theme, Dark Reader and Dollchan extensions, and [Betterfox-based hardening prefs](https://github.com/pm-lack/pm-betterfox.js)
- Installs utilities like lf (with image previews via ueberzugpp), nsxiv, mpv, Thunar, dunst, maim, xcompmgr, unclutter and more
- Installs the [Tamzen](https://github.com/sunaku/tamzen-font) bitmap font, applies a dark GTK3 theme, and sets a wallpaper
- Appends a hosts-based ad/tracker [blocklist](https://github.com/pm-lack/hosts) to /etc/hosts

All this WITHOUT the AUR! 🎉

## Install

Pomni must be run as root.
```
# curl -LO https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/pomni.sh
# chmod +x pomni.sh
# sh pomni.sh
```

## Post Install
Add your monitor details to your xinitrc (in ~/.config/x11/) above dbus. Example:  
```
xrandr \
  --output HDMI-0 --mode 2560x1440 --rate 240 --primary --pos 0x0 \
  --output DP-0 --mode 2560x1440 --rate 165 --pos 2560x0
```

## Keybinds
Common
- Mod+Enter,                Spawn terminal
- Mod+q,                    Close window
- ModShift+q,               Close window
- Mod+d,                    dmenu
- ModShift+d,               dmenu
- Mod+j,                    Cycle thru windows by stack order
- Mod+k,                    Cycle thru windows by reverse stack order
- Mod+Space,                Swap focused window with master (zoom)
- ModShift+Space,           Toggle floating for the focused window
- Mod+f,                    Toggle fullscreen
- Mod+b,                    Toggle the status bar
- Alt+Tab,                  Cycle through windows
- ModCtrl+Shift+q,          Quit dwm

Layout & Navigation
- Mod+y,                    Toggle between dwindle and half-screen dwindle layouts
- Mod+Backspace,            Toggle blank side
- ModShift+Backspace,       Toggle blank side
- Mod+o,                    Increase number of master windows
- ModShift+o,               Decrease number of master windows
- Mod+h,                    Shrink master area
- Mod+l,                    Grow master area
- Mod+[1-9],                View tag
- Mod+0,                    View all tags
- Mod+Tab,                  Go back to the previously viewed tag
- ModShift+[1-9],           Move focused window to tag
- ModShift+0,               Make focused window visible on all tags
- ModCtrl+[1-9],            Move focused window to tag and follow to it
- Mod+Left,                 Focus previous monitor
- Mod+Right,                Focus next monitor
- ModShift+Left,            Send window to previous monitor
- ModShift+Right,           Send window to next monitor

Basic Programs
- Mod+r,                    lf (terminal-based file browser/manager)
- Mod+t,                    Thunar (gui file explorer)
- ModShift+b,               Web Browser (librewolf)
- ModShift+w,               Nmtui (for connecting to wireless internet)
- Mod+F11,                  Webcam preview (mpv)

Audio
- Mod+-,                    Volume down 5%
- ModShift+-,               Volume down 15%
- Mod+=,                    Volume up 5%
- ModShift+=,               Volume up 15%
- ModShift+m,               Toggle mute
- Mod+F4,                   Open pulsemixer

Screenshot
- Mod+Print,                Screenshot of the full screen
- ModShift+Print,           Screenshot of a selected region

## Courtesies
- [Luke Smith](https://lukesmith.xyz/) and his [LARBS](https://larbs.xyz/)
- [Stein Gunnar Bakkeby](https://github.com/bakkeby/) and his [DWM patches](https://github.com/bakkeby/patches/wiki)

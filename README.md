## pm’s Opinionated Minimal Nest Installer (pomni)
Pomni is a minimal, opinionated post-install setup script intended for use on artix-runit.
What it does:
- Creates a new user (or reconfigures an existing non-system one), sets the password, adds them to wheel, and sets zsh as the login shell.
- Configures zsh with a custom prompt, history, completion, autosuggestions, fast-syntax-highlighting and a fastfetch greeting.
- Adds the XLibre repository and signing key, then installs XLibre as the X server.
- Installs PipeWire and WirePlumber with PulseAudio compatibility, launched via a user-session config (no systemd required).
- Builds and installs pre-patched dwm, dmenu, st and dwmblocks from source, with statusbar blocks for volume, clock, network and battery.
- Installs LibreWolf with a custom FirefoxCSS theme, Dark Reader and Dollchan extensions, and Betterfox-based hardening prefs.
- Installs utilities like lf (with image previews via ueberzugpp), nsxiv, mpv, Thunar, dunst, maim, xcompmgr, unclutter and more.
- Installs the Tamzen bitmap font, applies a dark GTK3 theme, and sets a wallpaper.
- Appends a hosts-based ad/tracker blocklist to /etc/hosts.

## Install

As root;
```
# curl -LO https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/pomni.sh
# chmod +x pomni.sh
# sh pomni.sh
```

## Keybinds

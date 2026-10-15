## pm’s Opinionated Minimal Nest Installer (pomni)
Pomni is a minimal, opinionated post-install setup script intended for use on artix-base-runit.
What it does:
- Creates a new user (or reconfigures an existing one), sets the password, adds them to wheel, and sets zsh as the login shell
- Configures zsh with a custom prompt, history, completion, autosuggestions, fast-syntax-highlighting and a fastfetch greeting
- Adds the XLibre [repository](https://github.com/xlibre-artix/xlibre-artix) and signing key, then installs [XLibre](https://github.com/X11Libre/xserver) as the X server
- Installs and configures PipeWire and WirePlumber with PulseAudio compatibility
- Builds and installs pre-patched [dwm](https://github.com/pm-lack/dwm-6.8), [dmenu](https://github.com/pm-lack/dmenu), [st](https://github.com/pm-lack/st) and [dwmblocks](https://github.com/pm-lack/dwmblocks) from source, with statusbar blocks for volume, clock, network and battery
- Installs LibreWolf with a custom [FirefoxCSS](https://github.com/Bali10050/FirefoxCSS) theme, Dark Reader and Dollchan extensions, and [Betterfox-based hardening prefs](https://github.com/pm-lack/pm-betterfox.js)
- Installs utilities like lf (with image previews via ueberzugpp), nsxiv, mpv, Thunar, dunst, maim, xcompmgr, unclutter and more
- Installs the [Tamzen](https://github.com/sunaku/tamzen-font) bitmap font, applies a dark GTK3 theme, and sets a wallpaper
- Appends a hosts-based ad/tracker [blocklist](https://github.com/pm-lack/hosts) to /etc/hosts
- All this WITHOUT the AUR! 🎉

## Install

As root;
```
# curl -LO https://raw.githubusercontent.com/pm-lack/pomni/refs/heads/main/pomni.sh
# chmod +x pomni.sh
# sh pomni.sh
```

## Keybinds

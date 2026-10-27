#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install base GUI applications.
#             Edit the APPS list below — comment out any line to skip that app.
#             Packages are sourced from the official Ubuntu archive only — no
#             PPAs, snaps or third-party repos. Apps that aren't in the archive
#             are deliberately not listed here.
#             Post-install fixups (e.g. config tweaks) are handled automatically.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# ── Apps to install ───────────────────────────────────────────────────────────
# Comment out any line to skip that app.
APPS=(
    fish                   # login shell (chsh + fish_add_path ~/.local/bin auto-configured)
    vlc                    # media player (DVD/Blu-ray libs come with vlc; libdvdcss via libdvd-pkg auto-installed)
    kdenlive               # video editor
    krename                # batch file renamer
    flameshot              # screenshot tool with annotation
    rofi                   # app launcher (bound to Mod+d in dwm's config.h)
    cifs-utils             # SMB/CIFS share mounting (fstab + manual)
    network-manager-gnome  # nm-connection-editor — GUI for NetworkManager (Ubuntu's default; standalone window, no systray needed)
    python3-yaml           # dep: blood-pressure-tracker
    python3-matplotlib     # dep: blood-pressure-tracker
)
# ─────────────────────────────────────────────────────────────────────────────

if [ "$DEBUG" = true ]; then
    echo
    echo "------------------------------------------------------------"
    echo "Running $(basename $0)"
    echo "------------------------------------------------------------"
    echo
    read -n 1 -s -r -p "Debug mode is on. Press any key to continue..."
    echo
fi

##################################################################################################################################

echo
tput setaf 2
echo "########################################################################"
echo "################### Installing base apps"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Authenticate sudo once up front; keepalive prevents expiry during long installs
##################################################################################################################################

sudo -v
while true; do timeout 30 sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!
trap "kill $SUDO_KEEPALIVE 2>/dev/null" EXIT

# multiverse: libdvd-pkg (vlc post-install)
ensure_apt_components universe multiverse
apt_update

##################################################################################################################################
# Helpers
##################################################################################################################################

# Called after each successful install; add per-app fixups here.
post_install() {
    local pkg="$1"
    case "$pkg" in
        vlc)
            # Ubuntu's vlc already depends on libdvdread/libdvdnav/libbluray.
            # The one missing piece is libdvdcss (encrypted DVDs), which Ubuntu
            # can't ship directly — libdvd-pkg (multiverse) downloads the source
            # from VideoLAN and builds it locally. That's Ubuntu's own sanctioned
            # mechanism, but note it does fetch from outside the archive.
            if pkg_installed libdvdcss2; then
                echo "  → libdvdcss2 already installed — skipping."
            else
                tput setaf 6
                echo "  → installing libdvd-pkg and building libdvdcss2 ..."
                tput sgr0
                if pkg_install libdvd-pkg; then
                    sudo env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure libdvd-pkg \
                        || echo "    WARNING: libdvdcss2 build failed — rerun: sudo dpkg-reconfigure libdvd-pkg" >&2
                else
                    echo "    WARNING: libdvd-pkg failed (is multiverse enabled?)." >&2
                fi
            fi
            ;;
        fish)
            # Set fish as the login shell
            if [ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/fish" ]; then
                tput setaf 6
                echo "  → setting fish as login shell (chsh) ..."
                tput sgr0
                chsh -s /usr/bin/fish
            else
                echo "  → fish already the login shell — skipping chsh."
            fi
            # Ensure ~/.local/bin is in fish PATH
            FISH_CONF="$HOME/.config/fish/config.fish"
            mkdir -p "$(dirname "$FISH_CONF")"
            if grep -qF "fish_add_path ~/.local/bin" "$FISH_CONF" 2>/dev/null; then
                echo "  → fish_add_path already in config.fish — skipping."
            else
                tput setaf 6
                echo "  → adding fish_add_path ~/.local/bin to $FISH_CONF ..."
                tput sgr0
                cat >> "$FISH_CONF" <<'FISHCONF'
if status is-interactive
    fish_add_path ~/.local/bin
end
FISHCONF
            fi
            ;;
        network-manager-gnome)
            # nm-connection-editor only works if NetworkManager is what's actually
            # managing the network. Ubuntu Desktop: yes. Ubuntu Server: no —
            # netplan drives systemd-networkd there. Don't switch it over
            # automatically (easy way to lose the connection mid-script); just say so.
            if systemctl is-active --quiet NetworkManager; then
                echo "  → NetworkManager is active — launch with: nm-connection-editor"
            else
                tput setaf 3
                echo "  → NOTE: NetworkManager isn't running here (likely netplan + systemd-networkd)."
                echo "    nm-connection-editor won't manage anything until netplan's renderer is"
                echo "    switched to NetworkManager. Check first: networkctl list; ls /etc/netplan/"
                tput sgr0
            fi
            ;;
        flameshot)
            # On X11 + dwm (no xdg-desktop-portal Screenshot backend), flameshot's
            # portal-based capture times out after 30s and fails. Force the legacy
            # X11 capture path instead. See flameshot-org/flameshot#4737.
            FLAMESHOT_CONF="$HOME/.config/flameshot/flameshot.ini"
            mkdir -p "$(dirname "$FLAMESHOT_CONF")"
            if grep -q '^useX11LegacyScreenshot=true' "$FLAMESHOT_CONF" 2>/dev/null; then
                echo "  → flameshot.ini already has useX11LegacyScreenshot=true — skipping."
            else
                if [ ! -f "$FLAMESHOT_CONF" ]; then
                    printf '[General]\nuseX11LegacyScreenshot=true\n' > "$FLAMESHOT_CONF"
                elif grep -q '^useX11LegacyScreenshot=' "$FLAMESHOT_CONF"; then
                    sed -i 's/^useX11LegacyScreenshot=.*/useX11LegacyScreenshot=true/' "$FLAMESHOT_CONF"
                elif grep -q '^\[General\]' "$FLAMESHOT_CONF"; then
                    sed -i '/^\[General\]/a useX11LegacyScreenshot=true' "$FLAMESHOT_CONF"
                else
                    printf '[General]\nuseX11LegacyScreenshot=true\n' >> "$FLAMESHOT_CONF"
                fi
                tput setaf 6
                echo "  → set useX11LegacyScreenshot=true in $FLAMESHOT_CONF"
                tput sgr0
            fi
            ;;
    esac
}

##################################################################################################################################
# Install loop
##################################################################################################################################

FAILED=()

for app in "${APPS[@]}"; do
    echo
    tput setaf 3
    echo "── $app ──────────────────────────────────────────"
    tput sgr0

    if pkg_installed "$app"; then
        echo "$app already installed — skipping install, but re-applying post-install fixups."
        post_install "$app"
        continue
    fi

    echo "Installing $app ..."
    pkg_install "$app" || true  # don't abort the loop — check dpkg as truth
    if pkg_installed "$app"; then
        tput setaf 2
        echo "$app installed."
        tput sgr0
        post_install "$app"
    else
        tput setaf 1
        echo "ERROR: $app installation failed." >&2
        tput sgr0
        FAILED+=("$app")
    fi
done

##################################################################################################################################
# Deploy alacritty config
##################################################################################################################################

ALACRITTY_CONF="$HOME/.config/alacritty/alacritty.toml"
if grep -qF '#0a0a0a' "$ALACRITTY_CONF" 2>/dev/null; then
    echo "alacritty config already in place — skipping."
else
    mkdir -p "$(dirname "$ALACRITTY_CONF")"
    tput setaf 6
    echo "Writing alacritty config ..."
    tput sgr0
    cat > "$ALACRITTY_CONF" <<'ALACRITTYCONF'
[font]
size = 14.0

[font.normal]
family = "monospace"
style = "Regular"

[font.bold]
family = "monospace"
style = "Bold"

[font.italic]
family = "monospace"
style = "Italic"

[window]
padding.x = 8
padding.y = 8
decorations = "full"

[scrolling]
history = 10000

[cursor]
style.shape = "Block"
unfocused_hollow = true

[colors.primary]
background = "#0a0a0a"
foreground = "#d0d2d0"

[colors.normal]
black   = "#1a1a1a"
red     = "#e06c6c"
green   = "#39d353"
yellow  = "#f5c050"
blue    = "#3b9eff"
magenta = "#c87ed8"
cyan    = "#5ec4bd"
white   = "#d0d2d0"

[colors.bright]
black   = "#888888"
red     = "#ff7878"
green   = "#57ff6e"
yellow  = "#ffd855"
blue    = "#5bc8ff"
magenta = "#dc9af5"
cyan    = "#7ee8dd"
white   = "#ffffff"
ALACRITTYCONF
    tput setaf 2
    echo "  → wrote $ALACRITTY_CONF"
    tput sgr0
fi

##################################################################################################################################
# Install blood-pressure-tracker (Python CLI from GitHub source)
##################################################################################################################################

BP_WRAPPER="$HOME/.local/bin/bp-tracker"
if [ -f "$BP_WRAPPER" ]; then
    echo "bp-tracker already installed — skipping."
else
    tput setaf 6
    echo "Installing blood-pressure-tracker ..."
    tput sgr0
    BP_SRC="$HOME/.local/src/bp-tracker"
    rm -rf "$BP_SRC"
    git clone https://github.com/zythros/blood-pressure-tracker "$BP_SRC"
    export PATH="$HOME/.local/bin:$PATH"
    bash "$BP_SRC/install.sh"
    tput setaf 2
    echo "  → bp-tracker installed."
    tput sgr0
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo

if [ ${#FAILED[@]} -gt 0 ]; then
    tput setaf 1
    echo "The following apps failed to install:"
    for f in "${FAILED[@]}"; do
        echo "  - $f"
    done
    tput sgr0
else
    tput setaf 2
    echo "All apps installed successfully."
    tput sgr0
fi

echo
tput sgr0

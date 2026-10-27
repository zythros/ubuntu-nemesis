#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Set up dwm as a desktop environment option.
#             Clones github.com/zythros/dwm, builds from source, installs,
#             writes an xsessions entry (LightDM or GDM), and writes ~/.dwm/keybindings.txt.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

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
echo "################### Setting up dwm"
echo "########################################################################"
tput sgr0
echo

ensure_apt_components universe
apt_update

##################################################################################################################################
# 1. Install build dependencies
##################################################################################################################################

echo "Installing build dependencies ..."
pkg_install build-essential git libx11-dev libxft-dev libxinerama-dev

tput setaf 2
echo "Build dependencies installed."
tput sgr0

##################################################################################################################################
# 2. Install runtime dependencies
#    suckless-tools is Ubuntu's dmenu package (820 replaces it with the zythros fork).
#    xserver-xorg moved from main to universe in 26.04 (GNOME is Wayland-only
#    there) — install it explicitly so dwm still has an X server to run on.
##################################################################################################################################

echo
echo "Installing runtime dependencies (xorg, alacritty, dmenu) ..."
pkg_install xserver-xorg alacritty suckless-tools dbus-user-session

tput setaf 2
echo "Runtime dependencies installed."
tput sgr0

##################################################################################################################################
# 3. Remove Ubuntu's packaged dwm (replaced by fork)
#    It owns /usr/share/xsessions/dwm.desktop, which step 7 writes —
#    leaving it installed would let a later apt upgrade clobber our entry.
##################################################################################################################################

if pkg_installed dwm; then
    tput setaf 3
    echo
    echo "Removing apt dwm (will be replaced by zythros fork) ..."
    tput sgr0
    "${APT_GET[@]}" remove -y dwm
    tput setaf 2
    echo "apt dwm removed."
    tput sgr0
fi

##################################################################################################################################
# 4. Clone or update fork
##################################################################################################################################

echo
DWM_SRC="$HOME/.local/src/dwm"

if [ -d "$DWM_SRC/.git" ]; then
    echo "dwm source found at $DWM_SRC — resetting config.h and pulling latest ..."
    git -C "$DWM_SRC" checkout config.h
    git -C "$DWM_SRC" pull
else
    echo "Cloning github.com/zythros/dwm to $DWM_SRC ..."
    mkdir -p "$(dirname "$DWM_SRC")"
    git clone https://github.com/zythros/dwm.git "$DWM_SRC"
fi

if [ ! -d "$DWM_SRC/.git" ]; then
    tput setaf 1
    echo "ERROR: git clone failed — check internet connection"
    tput sgr0
    exit 1
fi

tput setaf 2
echo "Source ready."
tput sgr0

##################################################################################################################################
# 5. Build and install
##################################################################################################################################

echo
echo "Building dwm ..."
make -C "$DWM_SRC" clean
make -C "$DWM_SRC"

echo "Installing dwm ..."
sudo make -C "$DWM_SRC" install

tput setaf 2
echo "dwm installed."
tput sgr0

##################################################################################################################################
# 6. Display manager check
#    artix-nemesis assumed LightDM was already there. Ubuntu Desktop ships GDM
#    (which still runs X11 xsessions via gdm-x-session); Ubuntu Server ships
#    none. Install LightDM only when there's no display manager at all —
#    never swap out an existing one behind the user's back.
##################################################################################################################################

echo
if [ -e /etc/systemd/system/display-manager.service ]; then
    DM=$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)
    echo "Display manager already configured: $DM — leaving it alone."
else
    tput setaf 3
    echo "No display manager configured — installing LightDM ..."
    tput sgr0
    pkg_install lightdm lightdm-gtk-greeter
    tput setaf 2
    echo "LightDM installed."
    tput sgr0
fi

##################################################################################################################################
# 7. Create xsessions entry
#    No dbus-launch wrapper here (artix-nemesis needs one): on systemd,
#    pam_systemd + dbus-user-session give every graphical login a session bus.
##################################################################################################################################

echo
SESSION_FILE="/usr/share/xsessions/dwm.desktop"

if [ -f "$SESSION_FILE" ] && grep -qF 'Exec=dwm' "$SESSION_FILE"; then
    echo "$SESSION_FILE already exists — skipping."
else
    echo "Writing $SESSION_FILE ..."
    sudo mkdir -p "$(dirname "$SESSION_FILE")"
    sudo tee "$SESSION_FILE" > /dev/null <<'EOF'
[Desktop Entry]
Name=dwm
Comment=Dynamic Window Manager
Exec=dwm
Type=Application
EOF
    tput setaf 2
    echo "Session entry created."
    tput sgr0
fi

##################################################################################################################################
# 8. Write ~/.dwm/keybindings.txt
##################################################################################################################################

echo
KEYBINDINGS_FILE="$HOME/.dwm/keybindings.txt"
mkdir -p "$HOME/.dwm"

echo "Writing $KEYBINDINGS_FILE ..."
cat > "$KEYBINDINGS_FILE" <<'EOF'
dwm keybindings  (Mod = Super / Windows key)
=============================================

Launching
  Mod + Return          alacritty (terminal)
  Mod + Shift + Return  thunar (file manager)
  Mod + d               rofi (run launcher)
  Mod + Shift + d       dmenu (run launcher)
  Mod + m               mullvad-browser
  Mod + s               flameshot (screenshot)

Windows
  Mod + j               focus next window
  Mod + k               focus previous window
  Mod + Shift + c       close focused window
  Mod + Shift + Space   toggle floating

Layout
  Mod + t               tile layout
  Mod + f               floating layout
  Mod + h               shrink master area
  Mod + l               expand master area
  Mod + i               increase master count

Tags (workspaces)
  Mod + Left            previous tag (wrap)
  Mod + Right           next tag (wrap)
  Mod + 1-9             view tag
  Mod + Shift + 1-9     move window to tag
  Mod + Ctrl + 1-9      toggle tag view
  Mod + 0               view all tags
  Mod + Shift + 0       move window to all tags
  Mod + Tab             toggle last tag

Bar
  Mod + b               toggle bar

Multi-monitor
  Mod + ,               focus previous monitor
  Mod + .               focus next monitor
  Mod + Shift + ,       move window to previous monitor
  Mod + Shift + .       move window to next monitor

Wallpaper
  Mod + w               next wallpaper
  Mod + Shift + w       previous wallpaper

System
  Mod + Space           show this file
  Mod + Shift + q       quit dwm
EOF

tput setaf 2
echo "Keybindings file written."
tput sgr0

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "dwm is now available as a session at the login screen (LightDM / GDM session picker)."
echo "Keybindings: $KEYBINDINGS_FILE"
echo "Source:      $DWM_SRC"
echo "To rebuild:  make -C $DWM_SRC clean && make -C $DWM_SRC && sudo make -C $DWM_SRC install"
echo
tput sgr0

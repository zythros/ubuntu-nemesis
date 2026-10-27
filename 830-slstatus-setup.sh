#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Build slstatus from zythros fork; autostart via ~/.xprofile
#
#   - Clone to ~/.local/src/slstatus (not ~/.config/arco-chadwm/slstatus)
#   - Autostart via ~/.xprofile (LightDM and GDM both source it for X sessions)
#   - Volume component stripped from config.h at build time (not needed)
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
echo "################### Setting up slstatus (zythros fork)"
echo "########################################################################"
tput sgr0
echo

apt_update

##################################################################################################################################
# 1. Build dependencies
##################################################################################################################################

echo "Checking build dependencies ..."
pkg_install build-essential git libx11-dev

tput setaf 2
echo "Build dependencies ready."
tput sgr0

##################################################################################################################################
# 2. (No packaged slstatus to remove — Ubuntu doesn't ship one, unlike Arch/Artix)
##################################################################################################################################

##################################################################################################################################
# 3. Clone or update zythros/slstatus
##################################################################################################################################

SLSTATUS_SRC="$HOME/.local/src/slstatus"

echo
if [ -d "$SLSTATUS_SRC/.git" ]; then
    tput setaf 3
    echo "Updating slstatus source ..."
    tput sgr0
    if ! git -C "$SLSTATUS_SRC" pull; then
        tput setaf 1
        echo "ERROR: git pull failed in $SLSTATUS_SRC — not building with stale/uncertain source." >&2
        echo "       Usually local changes to tracked files blocking the merge. Check:" >&2
        echo "         git -C $SLSTATUS_SRC status" >&2
        echo "       If it's just local build artifacts (safe to discard), fix with:" >&2
        echo "         git -C $SLSTATUS_SRC reset --hard origin/master && git -C $SLSTATUS_SRC pull" >&2
        tput sgr0
        exit 1
    fi
elif [ -d "$SLSTATUS_SRC" ]; then
    tput setaf 3
    echo "Backing up existing $SLSTATUS_SRC and cloning ..."
    tput sgr0
    mv "$SLSTATUS_SRC" "${SLSTATUS_SRC}.backup.$(date +%s)"
    git clone https://github.com/zythros/slstatus.git "$SLSTATUS_SRC"
else
    tput setaf 3
    echo "Cloning github.com/zythros/slstatus to $SLSTATUS_SRC ..."
    tput sgr0
    mkdir -p "$(dirname "$SLSTATUS_SRC")"
    git clone https://github.com/zythros/slstatus.git "$SLSTATUS_SRC"
fi

if [ ! -d "$SLSTATUS_SRC/.git" ]; then
    tput setaf 1
    echo "ERROR: git clone failed — check internet connection"
    tput sgr0
    exit 1
fi

tput setaf 2
echo "Source ready."
tput sgr0

##################################################################################################################################
# 4. Strip volume, CPU and RAM components from config.h
#    The fork's config.h includes volume (pamixer), CPU and RAM entries; remove them so
#    the bar shows only the datetime.
##################################################################################################################################

echo
echo "Patching config.h (removing volume, cpu, ram components) ..."
sed -i '/pamixer/d; /cpu_perc/d; /ram_perc/d' "$SLSTATUS_SRC/config.h"
tput setaf 2
echo "config.h patched."
tput sgr0

##################################################################################################################################
# 5. Build and install
##################################################################################################################################

echo
echo "Building slstatus ..."
make -C "$SLSTATUS_SRC" clean
make -C "$SLSTATUS_SRC"

echo "Installing slstatus ..."
sudo make -C "$SLSTATUS_SRC" install

if ! command -v slstatus &>/dev/null; then
    tput setaf 1
    echo "ERROR: slstatus not found after install"
    tput sgr0
    exit 1
fi

tput setaf 2
echo "slstatus installed."
tput sgr0

##################################################################################################################################
# 6. Autostart via ~/.xprofile
##################################################################################################################################

XPROFILE="$HOME/.xprofile"

echo
if grep -qF 'slstatus &' "$XPROFILE" 2>/dev/null; then
    tput setaf 2
    echo "~/.xprofile already starts slstatus — skipping."
    tput sgr0
else
    tput setaf 3
    echo "Adding slstatus autostart to ~/.xprofile ..."
    tput sgr0
    cat >> "$XPROFILE" <<'XPROFILE_ENTRY'

# slstatus — writes datetime to DWM status bar
slstatus &
XPROFILE_ENTRY
    tput setaf 2
    echo "~/.xprofile updated."
    tput sgr0
fi

##################################################################################################################################
# 7. Best-effort live restart (only if already running in this session)
##################################################################################################################################

if [ -n "${DISPLAY:-}" ] && pgrep -x slstatus &>/dev/null; then
    tput setaf 3
    echo
    echo "Restarting running slstatus ..."
    tput sgr0
    pkill -x slstatus || true
    slstatus &
    tput setaf 2
    echo "slstatus restarted."
    tput sgr0
fi

##################################################################################################################################
# Summary
##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "slstatus (zythros fork) installed:"
echo "  Source:  $SLSTATUS_SRC"
echo "  Binary:  $(which slstatus)"
echo
echo "Status bar components:"
echo "  Datetime — datetime  (bg #222222 black, fg #eeeeee white)"
echo "  Update interval: 1000ms"
echo
echo "Autostart: ~/.xprofile → slstatus & (takes effect at next login)"
echo "Requires status2d patch in dwm fork for colored segments."
echo
tput sgr0

#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Build dmenu from zythros fork; wire j4-dmenu-desktop into dwm
#
#   - Clone to ~/.local/src/dmenu (not ~/.config/arco-chadwm/dmenu)
#   - No sxhkdrc — patches dwm config.h dmenucmd[] to call a wrapper script,
#     then rebuilds dwm (same pattern as 802's wallpaper keybind patch)
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
echo "################### Setting up dmenu (zythros fork)"
echo "########################################################################"
tput sgr0
echo

ensure_apt_components universe
apt_update

##################################################################################################################################
# 1. Build dependencies
##################################################################################################################################

echo "Checking build dependencies ..."
pkg_install build-essential git libx11-dev libxft-dev libxinerama-dev

tput setaf 2
echo "Build dependencies ready."
tput sgr0

##################################################################################################################################
# 2. Install j4-dmenu-desktop
##################################################################################################################################

if ! command -v j4-dmenu-desktop &>/dev/null; then
    tput setaf 3
    echo
    echo "Installing j4-dmenu-desktop ..."
    tput sgr0
    pkg_install j4-dmenu-desktop
fi

tput setaf 2
echo "j4-dmenu-desktop ready."
tput sgr0

##################################################################################################################################
# 3. Remove apt-installed dmenu (replaced by fork)
#    Ubuntu ships dmenu inside suckless-tools (installed by 802). Nothing
#    else here depends on it — j4-dmenu-desktop doesn't.
##################################################################################################################################

if pkg_installed suckless-tools; then
    tput setaf 3
    echo
    echo "Removing apt suckless-tools/dmenu (will be replaced by zythros fork) ..."
    tput sgr0
    "${APT_GET[@]}" remove -y suckless-tools
    tput setaf 2
    echo "apt dmenu removed."
    tput sgr0
fi

##################################################################################################################################
# 4. Clone or update zythros/dmenu
##################################################################################################################################

DMENU_SRC="$HOME/.local/src/dmenu"

echo
if [ -d "$DMENU_SRC/.git" ]; then
    tput setaf 3
    echo "Updating dmenu source ..."
    tput sgr0
    git -C "$DMENU_SRC" pull
elif [ -d "$DMENU_SRC" ]; then
    tput setaf 3
    echo "Backing up existing $DMENU_SRC and cloning ..."
    tput sgr0
    mv "$DMENU_SRC" "${DMENU_SRC}.backup.$(date +%s)"
    git clone https://github.com/zythros/dmenu.git "$DMENU_SRC"
else
    tput setaf 3
    echo "Cloning github.com/zythros/dmenu to $DMENU_SRC ..."
    tput sgr0
    mkdir -p "$(dirname "$DMENU_SRC")"
    git clone https://github.com/zythros/dmenu.git "$DMENU_SRC"
fi

if [ ! -d "$DMENU_SRC/.git" ]; then
    tput setaf 1
    echo "ERROR: git clone failed — check internet connection"
    tput sgr0
    exit 1
fi

tput setaf 2
echo "Source ready."
tput sgr0

##################################################################################################################################
# 5. Build and install dmenu fork
##################################################################################################################################

echo
echo "Building dmenu ..."
make -C "$DMENU_SRC" clean
make -C "$DMENU_SRC"

echo "Installing dmenu ..."
sudo make -C "$DMENU_SRC" install

tput setaf 2
echo "dmenu installed."
tput sgr0

##################################################################################################################################
# 6. Write dmenu-desktop wrapper script
#    dwm spawns binaries via execvp — a wrapper is the cleanest way to pass
#    the j4-dmenu-desktop --dmenu="..." flag without embedding shell escaping
#    inside a C string array in config.h.
#    dmenu is called by absolute path: -c (center) only exists in the fork, so
#    a stray stock dmenu earlier in PATH would make every launch fail.
##################################################################################################################################

WRAPPER="$HOME/.local/bin/dmenu-desktop"
mkdir -p "$HOME/.local/bin"

echo
echo "Writing $WRAPPER ..."
cat > "$WRAPPER" <<'EOF'
#!/bin/bash
exec j4-dmenu-desktop --dmenu="/usr/local/bin/dmenu -i -c -l 8 -fn 'monospace:size=12' -nb '#0a0a0a' -nf '#cdd6f4' -sb '#99f6e4' -sf '#0a0a0a'"
EOF
chmod +x "$WRAPPER"

tput setaf 2
echo "Wrapper written."
tput sgr0

##################################################################################################################################
# 7. Patch dwm config.h — replace dmenucmd[] to call dmenu-desktop wrapper
##################################################################################################################################

DWM_SRC="$HOME/.local/src/dwm"

if [ ! -f "$DWM_SRC/config.h" ]; then
    tput setaf 1
    echo "ERROR: $DWM_SRC/config.h not found — run 802-dwm-setup.sh first"
    tput sgr0
    exit 1
fi

echo
echo "Patching dwm config.h ..."

# Use the absolute path so dwm's execvp finds the wrapper regardless of
# what PATH the display manager passes to the X session (fish PATH is not inherited).
python3 - "$DWM_SRC/config.h" "$WRAPPER" <<'PYPATCH'
import sys, re
path, wrapper = sys.argv[1], sys.argv[2]
text = open(path).read()

if wrapper in text:
    print("dmenucmd already patched — skipping.")
    sys.exit(0)

new_line = f'static const char *dmenucmd[] = {{ "{wrapper}", NULL }};'
new_text = re.sub(r'static const char \*dmenucmd\[\][^;]*;', new_line, text, count=1)

if new_text == text:
    print("ERROR: dmenucmd line not found in config.h")
    sys.exit(1)

open(path, 'w').write(new_text)
print(f"dmenucmd patched → {wrapper}")
PYPATCH

if [ $? -ne 0 ]; then
    tput setaf 1
    echo "ERROR: config.h patch failed"
    tput sgr0
    exit 1
fi

tput setaf 2
echo "config.h patched."
tput sgr0

##################################################################################################################################
# 8. Rebuild and reinstall dwm
##################################################################################################################################

echo
echo "Rebuilding dwm ..."
make -C "$DWM_SRC" clean
make -C "$DWM_SRC"

echo "Installing dwm ..."
sudo make -C "$DWM_SRC" install

tput setaf 2
echo "dwm rebuilt and installed."
tput sgr0

##################################################################################################################################
# Summary
##################################################################################################################################

DMENU_VERSION=$(dmenu -v 2>&1 | head -1)

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "dmenu (zythros fork) installed:"
echo "  Source:  $DMENU_SRC"
echo "  Binary:  $(which dmenu)"
echo "  Version: $DMENU_VERSION"
echo
echo "j4-dmenu-desktop installed:"
echo "  Reads .desktop files — shows apps by display name"
echo
echo "Launcher wrapper: $WRAPPER"
echo "  j4-dmenu-desktop with centered grid style (-c -l 8) and dark theme"
echo
echo "dwm rebuilt: Mod+p / Mod+d → dmenu-desktop (j4 + zythros fork)"
echo
echo "Patches in zythros/dmenu fork:"
echo "  -c    center on screen"
echo "  -l N  grid/list layout"
echo
tput sgr0

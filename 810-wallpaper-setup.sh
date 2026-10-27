#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Set up wallpaper cycling system (can be run standalone)
#
#   - wallpaper.sh embedded (no installed_dir / local checkout dep)
#   - autostart via ~/.xprofile (sourced by both LightDM and GDM on Ubuntu)
#   - no sxhkd keybind wiring (not used with this dwm setup)
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
echo "################### Setting up wallpaper system"
echo "########################################################################"
tput sgr0
echo

ensure_apt_components universe

##################################################################################################################################
# 1. Install feh
##################################################################################################################################

if ! command -v feh &>/dev/null; then
    tput setaf 3
    echo "Installing feh ..."
    tput sgr0
    apt_update
    pkg_install feh
fi

tput setaf 2
echo "feh ready."
tput sgr0

##################################################################################################################################
# 2. Install wallpaper.sh to ~/.local/bin/
##################################################################################################################################

DEST_DIR="$HOME/.local/bin"
mkdir -p "$DEST_DIR"

echo
echo "Installing wallpaper.sh to $DEST_DIR ..."

cat > "$DEST_DIR/wallpaper.sh" <<'WALLPAPER_SCRIPT'
#!/bin/bash
#
# Wallpaper cycler for dwm
# Usage: wallpaper.sh [next|prev|restore]
#
# Cycles through wallpapers in order, persists state across reboots.
#

WALLPAPER_DIR="$HOME/.local/share/wallpapers"
STATE_FILE="$HOME/.local/share/wallpaper-state"

get_wallpapers() {
    find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" \) | sort
}

get_index() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo 0
    fi
}

save_index() {
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$1" > "$STATE_FILE"
}

set_wallpaper() {
    local file="$1"
    if [ -f "$file" ]; then
        feh --bg-fill "$file"
    fi
}

main() {
    local action="${1:-next}"

    mapfile -t wallpapers < <(get_wallpapers)
    local count=${#wallpapers[@]}

    if [ "$count" -eq 0 ]; then
        echo "No wallpapers found in $WALLPAPER_DIR"
        exit 1
    fi

    local index=$(get_index)

    case "$action" in
        next)
            index=$(( (index + 1) % count ))
            ;;
        prev)
            index=$(( (index - 1 + count) % count ))
            ;;
        restore)
            ;;
        *)
            echo "Usage: $0 [next|prev|restore]"
            exit 1
            ;;
    esac

    save_index "$index"
    set_wallpaper "${wallpapers[$index]}"
}

main "$@"
WALLPAPER_SCRIPT

chmod +x "$DEST_DIR/wallpaper.sh"

tput setaf 2
echo "wallpaper.sh installed."
tput sgr0

##################################################################################################################################
# 3. Clone or update wallpaper repository
##################################################################################################################################

WALLPAPER_DIR="$HOME/.local/share/wallpapers"
WALLPAPER_REPO="https://github.com/zythros/wallpaper.git"

echo
if [ -d "$WALLPAPER_DIR/.git" ]; then
    tput setaf 3
    echo "Updating wallpaper repository ..."
    tput sgr0
    git -C "$WALLPAPER_DIR" pull
elif [ -d "$WALLPAPER_DIR" ] && [ "$(ls -A "$WALLPAPER_DIR" 2>/dev/null)" ]; then
    tput setaf 3
    echo "Backing up existing wallpapers and cloning repository ..."
    tput sgr0
    mv "$WALLPAPER_DIR" "${WALLPAPER_DIR}.backup.$(date +%s)"
    git clone "$WALLPAPER_REPO" "$WALLPAPER_DIR"
else
    tput setaf 3
    echo "Cloning wallpaper repository ..."
    tput sgr0
    mkdir -p "$(dirname "$WALLPAPER_DIR")"
    git clone "$WALLPAPER_REPO" "$WALLPAPER_DIR"
fi

tput setaf 2
echo "Wallpapers at $WALLPAPER_DIR"
tput sgr0

##################################################################################################################################
# 4. Configure autostart via ~/.xprofile
#    Ubuntu's LightDM (lightdm-session) and GDM (/etc/gdm3/Xsession) both
#    source ~/.xprofile before launching an X session.
##################################################################################################################################

XPROFILE="$HOME/.xprofile"
WALLPAPER_LINE='~/.local/bin/wallpaper.sh restore &'

# Ensure ~/.local/bin is in PATH for the X session. The display manager sources
# ~/.xprofile regardless of login shell, so this covers fish, bash, sh, etc.
# Ubuntu's ~/.profile only adds ~/.local/bin if the directory existed at login
# time, and fish's own PATH (fish_add_path) is never seen by the X session —
# without this, dwm can't find dmenu-desktop or wallpaper.sh via execvp.
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

echo
if grep -qF 'export PATH="$HOME/.local/bin' "$XPROFILE" 2>/dev/null; then
    tput setaf 2
    echo "~/.xprofile already exports ~/.local/bin PATH — skipping."
    tput sgr0
else
    echo "Adding PATH export to $XPROFILE ..."
    # Prepend so PATH is set before wallpaper.sh is called
    if [ -f "$XPROFILE" ]; then
        tmp=$(mktemp)
        echo "$PATH_LINE" > "$tmp"
        cat "$XPROFILE" >> "$tmp"
        mv "$tmp" "$XPROFILE"
    else
        echo "$PATH_LINE" > "$XPROFILE"
    fi
    tput setaf 2
    echo "~/.xprofile PATH updated."
    tput sgr0
fi

if grep -qF "wallpaper.sh restore" "$XPROFILE" 2>/dev/null; then
    tput setaf 2
    echo "~/.xprofile already contains wallpaper.sh restore — skipping."
    tput sgr0
else
    echo "Adding wallpaper.sh restore to $XPROFILE ..."
    echo "$WALLPAPER_LINE" >> "$XPROFILE"
    tput setaf 2
    echo "~/.xprofile updated."
    tput sgr0
fi

##################################################################################################################################
# Summary
##################################################################################################################################

WALLPAPER_COUNT=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" \) 2>/dev/null | wc -l)

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "Wallpaper system installed:"
echo "  Script:     ~/.local/bin/wallpaper.sh"
echo "  Wallpapers: $WALLPAPER_DIR ($WALLPAPER_COUNT images)"
echo "  Autostart:  ~/.xprofile (wallpaper.sh restore, runs at graphical login)"
echo "  PATH:       ~/.xprofile exports ~/.local/bin (works for any login shell)"
echo
if [ "$WALLPAPER_COUNT" -eq 0 ]; then
    tput setaf 3
    echo "WARNING: No wallpapers found in $WALLPAPER_DIR"
    tput sgr0
    echo
fi
echo "Usage:"
echo "  wallpaper.sh next     - Next wallpaper"
echo "  wallpaper.sh prev     - Previous wallpaper"
echo "  wallpaper.sh restore  - Restore last wallpaper (run at login)"
echo
echo "Keybinds (wired in by 802-dwm-setup.sh):"
echo "  Mod+w           next wallpaper"
echo "  Mod+Shift+w     previous wallpaper"
echo
tput sgr0

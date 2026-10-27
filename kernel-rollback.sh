#!/bin/bash
#set -e
##################################################################################################################################
# Author    : zythros
# Purpose   : Boot an older, still-installed kernel.
#             Ubuntu has no pacman-style package cache to reinstall old kernels from —
#             instead apt keeps the previous kernel(s) installed alongside the newest one.
#             Lists installed kernels, lets you pick one with fzf, then points GRUB at it
#             (next boot only, or every boot until reset), protects it from
#             `apt autoremove`, and rebuilds DKMS modules for it.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

RUNNING=$(uname -r)
GRUB_CFG=/boot/grub/grub.cfg

echo
tput setaf 2
echo "########################################################################"
echo "################### Kernel Rollback"
echo "########################################################################"
tput sgr0
echo
echo "Running kernel : $RUNNING"
echo

if ! command -v fzf &>/dev/null; then
    echo "Installing fzf..."
    sudo apt-get install -y fzf || { echo "Could not install fzf" >&2; exit 1; }
fi

if ! sudo test -f "$GRUB_CFG"; then
    echo "$GRUB_CFG not found — this script only handles GRUB." >&2
    exit 1
fi

##################################################################################################################################
# Discover installed kernels
##################################################################################################################################

mapfile -t KVERS < <(
    dpkg-query -W -f='${Package} ${Status}\n' 'linux-image-[0-9]*' 2>/dev/null \
        | awk '/install ok installed/{sub(/^linux-image-/, "", $1); print $1}' \
        | sort -urV
)

if [ ${#KVERS[@]} -eq 0 ]; then
    echo "No installed linux-image-* packages found" >&2
    exit 1
fi

DISPLAY_LINES=()
declare -A LINE_TO_KVER

for kver in "${KVERS[@]}"; do
    has_headers="no "
    dpkg-query -W -f='${Status}' "linux-headers-$kver" 2>/dev/null | grep -q 'install ok installed' && has_headers="yes"

    running_tag=""
    [ "$kver" = "$RUNNING" ] && running_tag="  ← running"

    line="$(printf "%-30s  headers: %s%s" "$kver" "$has_headers" "$running_tag")"
    DISPLAY_LINES+=("$line")
    LINE_TO_KVER["$line"]="$kver"
done

##################################################################################################################################
# fzf selection
##################################################################################################################################

SELECTED=$(printf '%s\n' "${DISPLAY_LINES[@]}" | fzf \
    --prompt="kernel-rollback > " \
    --header="ENTER to select  |  ESC to cancel" \
    --header-first \
    --reverse \
    --no-sort) || exit 0

[ -z "$SELECTED" ] && { echo "Nothing selected."; exit 0; }

KVER="${LINE_TO_KVER[$SELECTED]}"

echo
echo "Selected: $KVER"

##################################################################################################################################
# Find the GRUB menu entry for that kernel
# Ubuntu puts every kernel under the "Advanced options" submenu; grub-reboot/
# grub-set-default address it as "<submenu id>><entry id>".
##################################################################################################################################

SUBMENU_ID=$(sudo grep -oP "^submenu .*\\\$menuentry_id_option '\Kgnulinux-advanced-[^']+" "$GRUB_CFG" | head -1)
ENTRY_ID=$(sudo grep -oP "^\s+menuentry .*\\\$menuentry_id_option '\Kgnulinux-\Q$KVER\E-advanced-[^']+" "$GRUB_CFG" | head -1)

if [ -z "$SUBMENU_ID" ] || [ -z "$ENTRY_ID" ]; then
    tput setaf 1
    echo "Could not find a GRUB entry for $KVER in $GRUB_CFG." >&2
    echo "Try: sudo update-grub  — then rerun. Or pick it by hand from GRUB's 'Advanced options' menu." >&2
    tput sgr0
    exit 1
fi
GRUB_TARGET="$SUBMENU_ID>$ENTRY_ID"

echo
echo "GRUB entry: $GRUB_TARGET"
echo
echo "  1) Next boot only (grub-reboot) — falls back to the newest kernel after that"
echo "  2) Every boot until reset (grub-set-default) — undo with: sudo grub-set-default 0"
echo
read -r -p "Choose [1/2, anything else aborts]: " mode
case "$mode" in
    1) GRUB_CMD=grub-reboot ;;
    2) GRUB_CMD=grub-set-default ;;
    *) echo "Aborted."; exit 0 ;;
esac

##################################################################################################################################
# Make sure GRUB honours a saved default — grub-reboot/grub-set-default are
# silently ignored unless GRUB_DEFAULT=saved (Ubuntu ships GRUB_DEFAULT=0).
##################################################################################################################################

if ! grep -q '^GRUB_DEFAULT=saved' /etc/default/grub; then
    echo
    echo "/etc/default/grub has $(grep '^GRUB_DEFAULT=' /etc/default/grub || echo 'no GRUB_DEFAULT')."
    read -r -p "Set GRUB_DEFAULT=saved and run update-grub? (required) [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
    if grep -q '^GRUB_DEFAULT=' /etc/default/grub; then
        sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
    else
        echo 'GRUB_DEFAULT=saved' | sudo tee -a /etc/default/grub > /dev/null
    fi
    sudo update-grub
fi

##################################################################################################################################
# Apply
##################################################################################################################################

echo
sudo "$GRUB_CMD" "$GRUB_TARGET"
tput setaf 2
echo "$GRUB_CMD → $GRUB_TARGET"
tput sgr0

# apt autoremove only keeps the newest + running kernel. Mark the chosen one
# manual so it can't be cleaned up from under you while you're relying on it.
# Undo later with: sudo apt-mark auto linux-image-$KVER
mapfile -t KPKGS < <(dpkg-query -W -f='${Package} ${Status}\n' "linux-*-$KVER" 2>/dev/null | awk '/install ok installed/{print $1}')
if [ ${#KPKGS[@]} -gt 0 ]; then
    sudo apt-mark manual "${KPKGS[@]}" > /dev/null
    echo "Protected from autoremove: ${KPKGS[*]}"
fi

##################################################################################################################################
# Rebuild DKMS modules for the target kernel
##################################################################################################################################

if command -v dkms &>/dev/null; then
    echo
    tput setaf 3
    echo "Rebuilding DKMS modules for $KVER ..."
    tput sgr0
    sudo dkms autoinstall -k "$KVER" || {
        tput setaf 1
        echo "WARNING: dkms autoinstall reported errors — check 'dkms status' after reboot"
        tput sgr0
    }
fi

##################################################################################################################################

echo
tput setaf 2
echo "Done. Reboot to boot into $KVER."
tput sgr0
echo

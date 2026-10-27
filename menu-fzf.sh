#!/bin/bash
##################################################################################################################################
# Author    : zythros
# Purpose   : fzf-based menu to select and run ubuntu-nemesis setup scripts
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

if ! command -v fzf &>/dev/null; then
    echo "Installing fzf..."
    ensure_apt_components universe
    pkg_install fzf || { echo "Could not install fzf — aborting" >&2; exit 1; }
fi

# Pairs: script filename, description (in desired run order)
ENTRIES=(
    "802-dwm-setup.sh"          "Build and install dwm window manager"
    "803-apps-setup.sh"         "Install preferred apps"
    "810-wallpaper-setup.sh"    "Set up wallpaper cycling system"
    "820-dmenu-setup.sh"        "Build dmenu; wire j4-dmenu-desktop into dwm"
    "830-slstatus-setup.sh"     "Build slstatus; write CPU/RAM/datetime to DWM bar"
    "837-rgb-setup.sh"          "Install OpenRGB; set all RGB hardware to #ff8000 at boot"
    "840-snapper-setup.sh"      "Configure Snapper for BTRFS snapshots"
    "870-vm-clipboard-setup.sh" "SPICE clipboard sharing (VM guests only)"
    "880-nvidia-bm-setup.sh"    "NVIDIA drivers — bare metal (dual GPU)"
    "881-nvidia-vm-setup.sh"    "NVIDIA drivers — VM guest (3090 passthrough)"
    "890-vfio-passthrough.sh"   "Configure VFIO passthrough for RTX 3090"
    "895-virt-manager-setup.sh" "Install virt-manager / QEMU-KVM"
    "896-distrobox-setup.sh"    "Install podman + distrobox"
)

##################################################################################################################################
# Build menu lines and prompt with fzf
##################################################################################################################################

MAX_LEN=0
for (( i=0; i<${#ENTRIES[@]}; i+=2 )); do
    (( ${#ENTRIES[i]} > MAX_LEN )) && MAX_LEN=${#ENTRIES[i]}
done

MENU_LINES=()
for (( i=0; i<${#ENTRIES[@]}; i+=2 )); do
    MENU_LINES+=("$(printf "%-${MAX_LEN}s  —  %s" "${ENTRIES[i]}" "${ENTRIES[i+1]}")")
done

SELECTED=$(printf '%s\n' "${MENU_LINES[@]}" | fzf \
    --multi \
    --prompt="ubuntu-nemesis > " \
    --header="TAB to select/deselect  |  ENTER to confirm  |  ESC to cancel" \
    --header-first \
    --bind "tab:toggle+down" \
    --reverse \
    --no-sort) || exit 0

[ -z "$SELECTED" ] && { echo "Nothing selected."; exit 0; }

# Extract script filenames from selected lines (everything before the first space)
QUEUE=()
while IFS= read -r line; do
    script="${line%%  *}"
    QUEUE+=("$script")
done <<< "$SELECTED"

##################################################################################################################################
# Confirm
##################################################################################################################################

echo
echo "The following scripts will run in order:"
for s in "${QUEUE[@]}"; do
    echo "  $s"
done
echo
read -r -p "Proceed? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

##################################################################################################################################
# Run selected scripts in order
##################################################################################################################################

PASS=()
FAIL=()

for script in "${QUEUE[@]}"; do
    path="$SCRIPT_DIR/$script"

    if [ ! -f "$path" ]; then
        echo "WARNING: $script not found in $SCRIPT_DIR — skipping"
        FAIL+=("$script (not found)")
        continue
    fi

    echo
    tput setaf 6
    echo "========================================================================"
    echo "  Running: $script"
    echo "========================================================================"
    tput sgr0
    echo

    if bash "$path"; then
        PASS+=("$script")
    else
        tput setaf 1
        echo "ERROR: $script exited non-zero"
        tput sgr0
        FAIL+=("$script")

        read -r -p "Continue with remaining scripts? [y/N] " cont
        [[ "$cont" =~ ^[Yy]$ ]] || break
    fi
done

##################################################################################################################################
# Summary
##################################################################################################################################

echo
tput setaf 6
echo "========================================================================"
echo "  Summary"
echo "========================================================================"
tput sgr0
echo

if [ ${#PASS[@]} -gt 0 ]; then
    tput setaf 2
    echo "Passed (${#PASS[@]}):"
    for s in "${PASS[@]}"; do echo "  $s"; done
    tput sgr0
fi

if [ ${#FAIL[@]} -gt 0 ]; then
    tput setaf 1
    echo "Failed (${#FAIL[@]}):"
    for s in "${FAIL[@]}"; do echo "  $s"; done
    tput sgr0
fi

echo

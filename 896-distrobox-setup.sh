#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install podman + distrobox (rootless containers)
#             Both are in Ubuntu universe.
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

echo
tput setaf 2
echo "########################################################################"
echo "################### Setting up podman + distrobox"
echo "########################################################################"
tput sgr0
echo

ensure_apt_components universe
apt_update

##################################################################################################################################
# 1. Install packages
##################################################################################################################################

echo "Installing packages..."

FAILED=()
for pkg in podman distrobox; do
    if pkg_installed "$pkg"; then
        echo "  $pkg already installed — skipping."
    else
        pkg_install "$pkg" || true  # don't abort here — check dpkg as truth
        if pkg_installed "$pkg"; then
            echo "  $pkg installed."
        else
            tput setaf 1
            echo "  ERROR: $pkg installation failed." >&2
            tput sgr0
            FAILED+=("$pkg")
        fi
    fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
    tput setaf 1
    echo "Could not install: ${FAILED[*]} — aborting." >&2
    tput sgr0
    exit 1
fi

##################################################################################################################################
# 2. subuid/subgid ranges for rootless podman
##################################################################################################################################

# Rootless podman maps container UIDs/GIDs onto a range of host IDs listed
# in /etc/subuid and /etc/subgid. Without an entry for $USER, rootless
# containers fail ("cannot find mappings for user"). Ubuntu's adduser
# normally creates these already for desktop users. Allocate 65536 IDs
# starting past the highest range already in use, so we never overlap
# another user's allocation.

echo
echo "Checking subuid/subgid ranges for $USER..."

SUBIDS_CHANGED=false
for kind in uid gid; do
    file="/etc/sub$kind"
    if grep -q "^$USER:" "$file" 2>/dev/null; then
        echo "  $file already has an entry for $USER — skipping."
        continue
    fi
    start=$(awk -F: 'BEGIN { max = 100000 } { end = $2 + $3; if (end > max) max = end } END { print max }' "$file" 2>/dev/null)
    end=$((start + 65535))
    sudo usermod "--add-sub${kind}s" "$start-$end" "$USER"
    echo "  Added $USER:$start:65536 to $file"
    SUBIDS_CHANGED=true
done

# Existing podman storage was built without the new mapping — refresh it
if [ "$SUBIDS_CHANGED" = true ]; then
    podman system migrate 2>/dev/null || true
fi

# (No shared-root service needed — artix-nemesis adds one because OpenRC leaves
# "/" as a private mount. systemd remounts "/" rshared at boot by itself.)

##################################################################################################################################
# 3. Summary
##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "Installed:"
echo "  - podman (rootless container engine)"
echo "  - distrobox (run other distros' containers as if native)"
echo
echo "Try it:  distrobox create -i archlinux:latest -n testbox && distrobox enter testbox"
echo
tput sgr0

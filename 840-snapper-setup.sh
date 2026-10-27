#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install and configure Snapper for BTRFS snapshots (can be run standalone)
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
echo "################### Setting up Snapper (BTRFS snapshots)"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Check if root filesystem is BTRFS
##################################################################################################################################

ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

if [ "$ROOT_FSTYPE" != "btrfs" ]; then
    tput setaf 3
    echo "Root filesystem is $ROOT_FSTYPE, not BTRFS"
    echo "Snapper requires BTRFS. Skipping installation."
    tput sgr0
    echo
    exit 0
fi

tput setaf 2
echo "BTRFS detected on root filesystem"
tput sgr0
echo

##################################################################################################################################
# Track warnings for final summary
##################################################################################################################################

WARNINGS=()

##################################################################################################################################
# Install snapper
#
# Ubuntu equivalents of the Arch/Artix package set:
#   snap-pac        → not needed: Ubuntu's snapper package ships its own apt hook
#                     (/etc/apt/apt.conf.d/80snapper) that takes pre/post snapshots
#                     around every apt/dpkg transaction.
#   snapper-openrc  → not needed: snapper ships snapper-timeline/-cleanup systemd timers.
#   grub-btrfs      → not in the Ubuntu archive (see below).
##################################################################################################################################

ensure_apt_components universe
apt_update

tput setaf 3
echo "Installing snapper packages..."
tput sgr0

if ! pkg_install snapper btrfs-progs inotify-tools; then
    tput setaf 1
    echo "ERROR: Failed to install snapper packages"
    echo "Check your internet connection and apt sources (snapper is in universe)."
    tput sgr0
    exit 1
fi

if [ ! -f /etc/apt/apt.conf.d/80snapper ]; then
    tput setaf 3
    echo "WARNING: /etc/apt/apt.conf.d/80snapper not found — apt won't take automatic pre/post snapshots."
    tput sgr0
    WARNINGS+=("80snapper apt hook missing — no automatic snapshots around apt transactions")
fi

##################################################################################################################################
# Check if snapper root config already exists
##################################################################################################################################

if sudo snapper -c root list &>/dev/null; then
    tput setaf 2
    echo "Snapper 'root' config already exists"
    tput sgr0
else
    ##############################################################################################################################
    # Create snapper config for root
    ##############################################################################################################################

    tput setaf 3
    echo "Creating snapper configuration for root..."
    tput sgr0

    # Snapper creates /.snapshots directory/subvolume

    # Check if /.snapshots exists as a subvolume mount
    if findmnt /.snapshots &>/dev/null; then
        tput setaf 2
        echo "/.snapshots is already mounted (likely @snapshots subvolume)"
        tput sgr0
    elif [ -d "/.snapshots" ]; then
        # Directory exists but not mounted - might be from failed setup
        tput setaf 3
        echo "Removing existing /.snapshots directory..."
        tput sgr0
        sudo rm -rf /.snapshots
    fi

    # Create the snapper config
    sudo snapper -c root create-config /

    if [ $? -eq 0 ]; then
        tput setaf 2
        echo "Snapper 'root' config created successfully"
        tput sgr0
    else
        tput setaf 1
        echo "ERROR: Failed to create snapper config"
        echo "You may need to set up /.snapshots subvolume manually"
        tput sgr0
        exit 1
    fi
fi

##################################################################################################################################
# Configure snapper settings
##################################################################################################################################

SNAPPER_CONFIG="/etc/snapper/configs/root"

if sudo test -f "$SNAPPER_CONFIG"; then
    tput setaf 3
    echo "Configuring snapper settings..."
    tput sgr0

    # Allow user to use snapper (add to ALLOW_USERS)
    CURRENT_USER=$(whoami)
    if ! sudo grep -q "ALLOW_USERS=\".*$CURRENT_USER" "$SNAPPER_CONFIG"; then
        sudo sed -i "s/ALLOW_USERS=\"\"/ALLOW_USERS=\"$CURRENT_USER\"/" "$SNAPPER_CONFIG"
        tput setaf 2
        echo "Added $CURRENT_USER to ALLOW_USERS"
        tput sgr0
    fi

    # Set reasonable snapshot limits (prevent disk filling up)
    # Timeline snapshots: keep fewer old ones
    sudo sed -i 's/TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' "$SNAPPER_CONFIG"
    sudo sed -i 's/TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' "$SNAPPER_CONFIG"
    sudo sed -i 's/TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="0"/' "$SNAPPER_CONFIG"
    sudo sed -i 's/TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' "$SNAPPER_CONFIG"
    sudo sed -i 's/TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' "$SNAPPER_CONFIG"

    # Number cleanup: keep last 5-10 snapshots from the apt hook
    sudo sed -i 's/NUMBER_LIMIT=.*/NUMBER_LIMIT="10"/' "$SNAPPER_CONFIG"
    sudo sed -i 's/NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="5"/' "$SNAPPER_CONFIG"

    tput setaf 2
    echo "Configured snapshot retention limits"
    tput sgr0
fi

##################################################################################################################################
# Enable systemd timers for automatic snapshots
# snapper-timeline.timer (hourly snapshots) and snapper-cleanup.timer (prune old ones)
##################################################################################################################################

tput setaf 3
echo "Enabling snapper systemd timers..."
tput sgr0

if sudo systemctl enable --now snapper-timeline.timer; then
    tput setaf 2
    echo "snapper-timeline.timer enabled and started"
    tput sgr0
else
    WARNINGS+=("snapper-timeline.timer: Failed to enable (hourly snapshots won't run automatically)")
fi

if sudo systemctl enable --now snapper-cleanup.timer; then
    tput setaf 2
    echo "snapper-cleanup.timer enabled and started"
    tput sgr0
else
    WARNINGS+=("snapper-cleanup.timer: Failed to enable (old snapshots won't be cleaned automatically)")
fi

##################################################################################################################################
# grub-btrfs (snapshots in the GRUB boot menu) — not in the Ubuntu archive, not installed automatically
##################################################################################################################################

if command -v grub-btrfsd &>/dev/null; then
    tput setaf 3
    echo "grub-btrfs found (installed manually) — enabling grub-btrfsd..."
    tput sgr0
    if sudo systemctl enable --now grub-btrfsd.service; then
        tput setaf 2
        echo "grub-btrfsd enabled and started (snapshots will appear in GRUB menu)"
        tput sgr0
        sudo update-grub || WARNINGS+=("update-grub: Failed to regenerate (run manually: sudo update-grub)")
    else
        WARNINGS+=("grub-btrfsd: Failed to enable (snapshots won't auto-update in GRUB menu)")
    fi
else
    tput setaf 3
    echo "grub-btrfs is not in the Ubuntu archive and is not installed automatically (third-party, by design)."
    echo "Snapshots + 'snapper undochange' still work without it; you just can't boot a snapshot from GRUB."
    echo "Install manually later if you choose to: https://github.com/Antynea/grub-btrfs (make install)"
    tput sgr0
    WARNINGS+=("grub-btrfs: not installed (not in Ubuntu archive, skipped by design) — no snapshot entries in GRUB")
fi

##################################################################################################################################
# snapper-rollback (full system rollback) — not in the Ubuntu archive, not installed automatically
##################################################################################################################################

if ! command -v snapper-rollback &>/dev/null; then
    tput setaf 3
    echo "snapper-rollback is not in the Ubuntu archive and is not installed automatically (third-party, by design)."
    echo "Install manually later if you choose to: https://github.com/jrabinow/snapper-rollback"
    tput sgr0
    WARNINGS+=("snapper-rollback: not installed (not in Ubuntu archive, skipped by design) — install manually if you want full rollback support")
fi

##################################################################################################################################
# Configure snapper-rollback for this system's layout
##################################################################################################################################

if command -v snapper-rollback &>/dev/null; then
    tput setaf 3
    echo "Configuring snapper-rollback..."
    tput sgr0

    # Create btrfsroot mount point
    sudo mkdir -p /btrfsroot

    # Detect root subvolume name and device (Ubuntu's installer uses "@")
    ROOT_SUBVOL=$(findmnt -n -o SOURCE / | sed 's/.*\[\/\([^]]*\)\].*/\1/')
    ROOT_DEV=$(findmnt -n -o SOURCE / | sed 's/\[.*//')

    # Write config
    sudo tee /etc/snapper-rollback.conf > /dev/null << EOF
[root]
subvol_main = $ROOT_SUBVOL
subvol_snapshots = $ROOT_SUBVOL/.snapshots
mountpoint = /btrfsroot
dev = $ROOT_DEV
EOF

    tput setaf 2
    echo "snapper-rollback configured for subvolume: $ROOT_SUBVOL"
    tput sgr0
fi

##################################################################################################################################
# Create initial snapshot
##################################################################################################################################

tput setaf 3
echo "Creating initial snapshot..."
tput sgr0

sudo snapper -c root create --description "Initial snapshot after snapper setup"

##################################################################################################################################
# Summary
##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "Snapper BTRFS snapshot system installed:"
echo
echo "Packages installed:"
echo "  - snapper          : Snapshot management tool (+ apt pre/post hook: /etc/apt/apt.conf.d/80snapper)"
echo "  - grub-btrfs       : NOT installed (not in Ubuntu archive — see warnings below)"
echo "  - snapper-rollback : NOT installed (not in Ubuntu archive — see warnings below)"
echo
echo "Configuration:"
echo "  - Config file: /etc/snapper/configs/root"
echo "  - Snapshots:   /.snapshots/"
echo
echo "Retention limits:"
echo "  - Hourly:  5"
echo "  - Daily:   7"
echo "  - Weekly:  0 (disabled)"
echo "  - Monthly: 0 (disabled)"
echo "  - Yearly:  0 (disabled)"
echo "  - Number (apt hook): 10"
echo
echo "systemd timers enabled:"
echo "  - snapper-timeline.timer : Hourly snapshots"
echo "  - snapper-cleanup.timer  : Automatic cleanup"
echo
echo "Usage:"
echo "  snapper -c root list              : List all snapshots"
echo "  snapper -c root create -d \"desc\"  : Create manual snapshot"
echo "  snapper -c root delete <num>      : Delete snapshot"
echo "  snapper -c root status 1..0       : Compare snapshot 1 to current"
echo "  snapper -c root undochange 2..3   : Revert changes between snapshots"
echo
tput sgr0

##################################################################################################################################
# Show warnings if any
##################################################################################################################################

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo
    tput setaf 3
    echo "########################################################################"
    echo "############################ WARNINGS ##################################"
    echo "########################################################################"
    echo
    echo "The following issues occurred during setup:"
    echo
    for warning in "${WARNINGS[@]}"; do
        echo "  ! $warning"
    done
    echo
    echo "Snapper is installed but some features may not work as expected."
    echo "Review the warnings above and fix manually if needed."
    echo "########################################################################"
    tput sgr0
fi

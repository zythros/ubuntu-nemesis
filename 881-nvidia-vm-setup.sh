#!/bin/bash
set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install NVIDIA drivers inside a VM with a passed-through RTX 3090 (GA102).
#             Only one GPU is visible to the guest, so no Xorg pinning or dual-GPU
#             workarounds are needed — just driver install + nouveau blacklist.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# Driver branch to install, e.g. "580". Empty = take whatever ubuntu-drivers
# recommends for this hardware. The -open kernel module flavour is always used
# (same as artix-nemesis's nvidia-open-dkms).
NVIDIA_BRANCH=""

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
echo "################### Setting up NVIDIA drivers (VM guest)"
echo "########################################################################"
tput sgr0
echo

# NVIDIA drivers live in Ubuntu's 'restricted' component (official archive,
# not a PPA) — the Ubuntu counterpart of artix-nemesis adding Arch [extra].
ensure_apt_components restricted
apt_update
pkg_install ubuntu-drivers-common pciutils

##################################################################################################################################
# Install the NVIDIA open driver via ubuntu-drivers.
# ubuntu-drivers pulls Ubuntu's prebuilt, Canonical-signed kernel modules
# (linux-modules-nvidia-<branch>-open-<flavour>) when they exist for the running
# kernel, and falls back to DKMS otherwise. Prebuilt+signed means it survives
# kernel upgrades and works with Secure Boot without enrolling a MOK key.
##################################################################################################################################

if dpkg-query -W -f='${Package} ${Status}\n' 'nvidia-driver-*-open' 2>/dev/null | grep -q 'install ok installed'; then
    echo "NVIDIA open driver already installed: $(dpkg-query -W -f='${Package} ${Status}\n' 'nvidia-driver-*-open' | awk '/install ok installed/{print $1}')"
else
    if [ -z "$NVIDIA_BRANCH" ]; then
        # e.g. "driver   : nvidia-driver-580-open - distro non-free recommended"
        NVIDIA_BRANCH=$(ubuntu-drivers devices 2>/dev/null | grep -E 'nvidia-driver-[0-9]+.*recommended' \
            | grep -oE 'nvidia-driver-[0-9]+' | head -1 | grep -oE '[0-9]+$' || true)
    fi
    if [ -z "$NVIDIA_BRANCH" ]; then
        tput setaf 1
        echo "ERROR: ubuntu-drivers found no recommended NVIDIA driver. Check: ubuntu-drivers devices"
        echo "       Or set NVIDIA_BRANCH at the top of this script."
        tput sgr0
        exit 1
    fi
    tput setaf 3
    echo "Installing NVIDIA driver: nvidia:${NVIDIA_BRANCH}-open"
    tput sgr0
    if ! sudo ubuntu-drivers install "nvidia:${NVIDIA_BRANCH}-open"; then
        tput setaf 1
        echo "ERROR: ubuntu-drivers failed to install nvidia:${NVIDIA_BRANCH}-open. Aborting."
        tput sgr0
        exit 1
    fi
    tput setaf 2
    echo "NVIDIA driver installed."
    tput sgr0
fi

# Verify an nvidia module exists for the running kernel — prebuilt or DKMS.
# modinfo covers both, unlike `dkms status` (which never sees prebuilt modules).
KVER=$(uname -r)
if ! modinfo -k "$KVER" nvidia &>/dev/null; then
    tput setaf 3
    echo "nvidia module not found for kernel $KVER — installing headers and running dkms autoinstall..."
    tput sgr0
    pkg_install "linux-headers-$KVER"
    sudo dkms autoinstall -k "$KVER" || true
    if ! modinfo -k "$KVER" nvidia &>/dev/null; then
        tput setaf 1
        echo "ERROR: nvidia module still not found for kernel $KVER."
        echo "       Run: dkms status; ubuntu-drivers devices"
        tput sgr0
        exit 1
    fi
fi
tput setaf 2
echo "nvidia kernel module verified for kernel $KVER."
tput sgr0

# Blacklist nouveau so it does not claim the GPUs before the nvidia driver.
# (Ubuntu's nvidia-kernel-common already does this — kept explicit so the
# result doesn't hinge on driver-package internals.)
NOUVEAU_BLACKLIST="/etc/modprobe.d/blacklist-nouveau.conf"
if [ ! -f "$NOUVEAU_BLACKLIST" ]; then
    echo "blacklist nouveau" | sudo tee "$NOUVEAU_BLACKLIST" > /dev/null
    tput setaf 2
    echo "Written: $NOUVEAU_BLACKLIST"
    tput sgr0
else
    echo "nouveau already blacklisted: $NOUVEAU_BLACKLIST"
fi

# Rebuild initramfs so the new driver and blacklist take effect on next boot
tput setaf 3
echo "Rebuilding initramfs (update-initramfs -u -k all) ..."
tput sgr0
sudo update-initramfs -u -k all
tput setaf 2
echo "initramfs rebuilt."
tput sgr0

##################################################################################################################################
# Enable nvidia-drm.modeset=1 kernel parameter
# (Ubuntu's driver packages also set this via /etc/modprobe.d/nvidia-graphics-drivers-kms.conf;
# the kernel param makes it apply before any modprobe.d config is read.)
##################################################################################################################################

MODESET_PARAM="nvidia-drm.modeset=1"

if [ -f "/etc/default/grub" ]; then
    tput setaf 3
    echo "Detected GRUB — adding $MODESET_PARAM to /etc/default/grub..."
    tput sgr0

    if ! grep -q "$MODESET_PARAM" /etc/default/grub; then
        # Handle both single-quoted and double-quoted GRUB_CMDLINE_LINUX_DEFAULT
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$MODESET_PARAM /" /etc/default/grub
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT='/GRUB_CMDLINE_LINUX_DEFAULT='$MODESET_PARAM /" /etc/default/grub
        sudo update-grub
        tput setaf 2
        echo "GRUB updated and config regenerated."
        tput sgr0
    else
        echo "$MODESET_PARAM already present in /etc/default/grub"
    fi

else
    tput setaf 1
    echo "Could not detect GRUB. Add '$MODESET_PARAM' to your kernel parameters manually."
    tput sgr0
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "Configured:"
echo "  - NVIDIA open driver installed via ubuntu-drivers (restricted component)"
echo "  - $NOUVEAU_BLACKLIST"
echo "      Blacklists nouveau so nvidia takes ownership at boot"
echo "  - initramfs rebuilt via update-initramfs -u -k all"
echo "  - kernel param: $MODESET_PARAM"
echo
echo "Reboot for changes to take effect."
echo
tput sgr0

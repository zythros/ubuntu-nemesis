#!/bin/bash
set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Configure Xorg and kernel for dual NVIDIA GPUs
#             Fixes modesetting/glamor crash that prevents the display manager from starting
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# PCI model string for the display GPU (the one Xorg should use).
# Change this if your display GPU is not a GA106.
DISPLAY_GPU_MODEL="GA106"

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
echo "################### Setting up NVIDIA Xorg configuration"
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
        echo "       Or set NVIDIA_BRANCH at the top of this script. xorg.conf will NOT be written."
        tput sgr0
        exit 1
    fi
    tput setaf 3
    echo "Installing NVIDIA driver: nvidia:${NVIDIA_BRANCH}-open"
    tput sgr0
    if ! sudo ubuntu-drivers install "nvidia:${NVIDIA_BRANCH}-open"; then
        tput setaf 1
        echo "ERROR: ubuntu-drivers failed to install nvidia:${NVIDIA_BRANCH}-open. Aborting — xorg.conf will NOT be written."
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

echo

# Create Xorg config to force nvidia driver on the display GPU.
# BusID pins Xorg to the display GPU so the passthrough GPU is ignored.
# Without this, Xorg may assign the second GPU to modesetting, which crashes via glamor_init.
XORG_CONF="/etc/X11/xorg.conf.d/10-nvidia.conf"
sudo mkdir -p "$(dirname "$XORG_CONF")"

# Detect display GPU PCI address and convert to Xorg BusID format (decimal)
PCI_ADDR=$(lspci | grep "$DISPLAY_GPU_MODEL" | grep -i "VGA" | awk '{print $1}')
if [ -z "$PCI_ADDR" ]; then
    tput setaf 1
    echo "ERROR: Could not detect display GPU ($DISPLAY_GPU_MODEL) PCI address. Aborting xorg conf write."
    tput sgr0
    exit 1
fi
BUS=$(printf "%d" "0x$(echo "$PCI_ADDR" | cut -d: -f1)")
DEV=$(printf "%d" "0x$(echo "$PCI_ADDR" | cut -d: -f2 | cut -d. -f1)")
FN=$(echo "$PCI_ADDR" | cut -d. -f2)
BUS_ID="PCI:${BUS}:${DEV}:${FN}"
echo "Detected display GPU ($DISPLAY_GPU_MODEL) at $PCI_ADDR -> Xorg BusID: $BUS_ID"

echo "Writing $XORG_CONF ..."
sudo tee "$XORG_CONF" > /dev/null << EOF
Section "Device"
    Identifier  "Nvidia Card"
    Driver      "nvidia"
    BusID       "$BUS_ID"
    Option      "NoLogo" "true"
EndSection
EOF
tput setaf 2
echo "Written: $XORG_CONF"
tput sgr0

# Named 99-nvidia-flags.conf so it sorts last alphabetically and wins
# if any earlier config also has a ServerFlags section.
FLAGS_CONF="/etc/X11/xorg.conf.d/99-nvidia-flags.conf"
echo "Writing $FLAGS_CONF ..."
sudo tee "$FLAGS_CONF" > /dev/null << EOF
Section "ServerFlags"
    Option "AutoAddGPU" "false"
EndSection
EOF
tput setaf 2
echo "Written: $FLAGS_CONF"
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
echo "  - $XORG_CONF"
echo "      Forces nvidia driver on display GPU ($DISPLAY_GPU_MODEL), BusID: $BUS_ID"
echo "  - $FLAGS_CONF"
echo "      AutoAddGPU false — prevents secondary GPU from being grabbed by modesetting"
echo "  - kernel param: $MODESET_PARAM"
echo
echo "Fixes: Xorg modesetting/glamor crash with dual NVIDIA GPUs"
echo "       that prevented LightDM/GDM from reaching the login screen."
echo
tput sgr0

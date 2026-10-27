#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Configure VFIO passthrough for the secondary GPU — isolates it from the nvidia driver
#             so it can be assigned exclusively to a VM via virt-manager / QEMU.
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
echo "################### Setting up VFIO passthrough (RTX 3090)"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Detect the passthrough GPU (GA102) PCI address and IDs
##################################################################################################################################

GPU_ADDR=$(lspci | grep "GA102" | grep -i "VGA" | awk '{print $1}')
if [ -z "$GPU_ADDR" ]; then
    tput setaf 1
    echo "ERROR: Could not detect RTX 3090 (GA102) PCI address. Aborting."
    tput sgr0
    exit 1
fi
echo "Detected RTX 3090 (GA102) at: $GPU_ADDR"

# Companion audio device is at the same bus:device, function 1
AUDIO_ADDR="${GPU_ADDR%.*}.1"

GPU_ID=$(lspci -nn | grep "^$GPU_ADDR " | grep -oP '\[10de:[0-9a-f]+\]' | tail -1 | tr -d '[]')
AUDIO_ID=$(lspci -nn | grep "^$AUDIO_ADDR " | grep -oP '\[10de:[0-9a-f]+\]' | tail -1 | tr -d '[]')

if [ -z "$GPU_ID" ]; then
    tput setaf 1
    echo "ERROR: Could not extract PCI ID for $GPU_ADDR. Aborting."
    tput sgr0
    exit 1
fi

echo "RTX 3090 GPU  PCI ID: $GPU_ID"
if [ -n "$AUDIO_ID" ]; then
    echo "RTX 3090 Audio PCI ID: $AUDIO_ID"
    VFIO_IDS="$GPU_ID,$AUDIO_ID"
else
    tput setaf 3
    echo "WARNING: No audio device found at $AUDIO_ADDR — only binding GPU."
    tput sgr0
    VFIO_IDS="$GPU_ID"
fi

##################################################################################################################################
# Write /etc/modprobe.d/vfio.conf — tells vfio-pci which device IDs to claim
##################################################################################################################################

VFIO_MODPROBE="/etc/modprobe.d/vfio.conf"
echo
echo "Writing $VFIO_MODPROBE ..."
sudo tee "$VFIO_MODPROBE" > /dev/null << EOF
# VFIO passthrough — bind secondary GPU to vfio-pci instead of nvidia
options vfio-pci ids=$VFIO_IDS
# Belt and braces: if nvidia/nouveau get loaded before vfio-pci (e.g. from
# the initramfs), make modprobe pull in vfio-pci first so it wins the device.
softdep nvidia pre: vfio-pci
softdep nouveau pre: vfio-pci
EOF
tput setaf 2
echo "Written: $VFIO_MODPROBE"
tput sgr0

##################################################################################################################################
# Update /etc/initramfs-tools/modules — load vfio modules early (before nvidia claims the device)
# Ubuntu's counterpart to mkinitcpio's MODULES=() array: one module per line.
##################################################################################################################################

INITRAMFS_MODULES="/etc/initramfs-tools/modules"
echo
echo "Updating $INITRAMFS_MODULES ..."

VFIO_MODULES="vfio vfio_iommu_type1 vfio_pci"

for mod in $VFIO_MODULES; do
    if grep -qx "$mod" "$INITRAMFS_MODULES"; then
        echo "$mod already present — skipping."
    else
        echo "$mod" | sudo tee -a "$INITRAMFS_MODULES" > /dev/null
        tput setaf 2
        echo "Added $mod to $INITRAMFS_MODULES"
        tput sgr0
    fi
done

##################################################################################################################################
# Enable IOMMU kernel parameter in GRUB
##################################################################################################################################

# Detect CPU vendor for the correct IOMMU flag
CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')
if echo "$CPU_VENDOR" | grep -q "AMD"; then
    IOMMU_PARAM="amd_iommu=on"
else
    IOMMU_PARAM="intel_iommu=on"
fi
PT_PARAM="iommu=pt"

echo
if [ -f "/etc/default/grub" ]; then
    tput setaf 3
    echo "Detected GRUB — adding $IOMMU_PARAM $PT_PARAM to /etc/default/grub..."
    tput sgr0

    GRUB_CHANGED=0
    if ! grep -q "$IOMMU_PARAM" /etc/default/grub; then
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$IOMMU_PARAM /" /etc/default/grub
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT='/GRUB_CMDLINE_LINUX_DEFAULT='$IOMMU_PARAM /" /etc/default/grub
        GRUB_CHANGED=1
    else
        echo "$IOMMU_PARAM already present in /etc/default/grub"
    fi
    if ! grep -q "$PT_PARAM" /etc/default/grub; then
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$PT_PARAM /" /etc/default/grub
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT='/GRUB_CMDLINE_LINUX_DEFAULT='$PT_PARAM /" /etc/default/grub
        GRUB_CHANGED=1
    else
        echo "$PT_PARAM already present in /etc/default/grub"
    fi

    if [ $GRUB_CHANGED -eq 1 ]; then
        sudo update-grub
        tput setaf 2
        echo "GRUB updated and config regenerated."
        tput sgr0
    fi

else
    tput setaf 1
    echo "Could not detect GRUB. Add '$IOMMU_PARAM $PT_PARAM' to your kernel parameters manually."
    tput sgr0
fi

##################################################################################################################################
# Rebuild initramfs
##################################################################################################################################

echo
tput setaf 3
echo "Rebuilding initramfs (update-initramfs -u -k all) ..."
tput sgr0
sudo update-initramfs -u -k all
tput setaf 2
echo "Initramfs rebuilt."
tput sgr0

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "Configured:"
echo "  - $VFIO_MODPROBE (vfio-pci IDs: $VFIO_IDS)"
echo "  - $INITRAMFS_MODULES (vfio modules loaded early: $VFIO_MODULES)"
echo "  - Kernel params: $IOMMU_PARAM $PT_PARAM"
echo "  - Initramfs rebuilt"
echo
echo "REBOOT required to activate VFIO passthrough."
echo
echo "After reboot, verify:"
echo "  lspci -k | grep -A2 '$GPU_ADDR'   # should show 'Kernel driver in use: vfio-pci'"
echo "  dmesg | grep -i iommu             # should show IOMMU enabled"
echo
tput sgr0

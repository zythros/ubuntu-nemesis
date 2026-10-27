#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Set up host-VM clipboard sharing (copy/paste) via SPICE
#             Installs spice-vdagent and qemu-guest-agent for QEMU/KVM VMs
#             Skips automatically on bare metal
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
# Check if running inside a VM
##################################################################################################################################

# systemd-detect-virt ships with systemd itself — no extra package needed
# (artix-nemesis had to pull in virt-what as a substitute). --vm ignores
# containers, so this doesn't misfire inside a distrobox.
VIRT_TYPE=$(systemd-detect-virt --vm 2>/dev/null)

if [ -z "$VIRT_TYPE" ] || [ "$VIRT_TYPE" = "none" ]; then
    tput setaf 3
    echo "Not running inside a VM - skipping clipboard setup"
    tput sgr0
    exit 0
fi

echo
tput setaf 2
echo "########################################################################"
echo "################### Setting up VM clipboard sharing"
echo "########################################################################"
tput sgr0
echo
echo "Detected virtualization: $VIRT_TYPE"

##################################################################################################################################
# 1. Install packages
##################################################################################################################################

echo
echo "Installing VM guest packages..."

ensure_apt_components universe
apt_update
pkg_install spice-vdagent qemu-guest-agent xclip

##################################################################################################################################
# 2. Enable services (systemd)
##################################################################################################################################

echo
echo "Enabling services..."

# spice-vdagentd — system daemon for SPICE agent connection (socket-activated on Ubuntu)
sudo systemctl enable --now spice-vdagentd.socket 2>/dev/null

# qemu-guest-agent — host-guest communication channel. Ubuntu's unit is static
# (started by udev when the virtio port appears), so there's nothing to enable.
sudo systemctl start qemu-guest-agent.service 2>/dev/null

##################################################################################################################################
# 3. Ensure spice-vdagent starts in X session
##################################################################################################################################

echo
echo "Configuring spice-vdagent autostart..."

# --- XDG autostart (fallback for DEs that read it) ---
if [ ! -f /etc/xdg/autostart/spice-vdagent.desktop ]; then
    echo "  Creating XDG autostart entry..."
    sudo tee /etc/xdg/autostart/spice-vdagent.desktop > /dev/null << 'DESKTOP'
[Desktop Entry]
Name=Spice vdagent
Comment=Agent for Spice guests
Exec=/usr/bin/spice-vdagent
Terminal=false
Type=Application
NoDisplay=true
DESKTOP
    echo "  Created /etc/xdg/autostart/spice-vdagent.desktop"
else
    echo "  XDG autostart entry already present"
fi

# --- ~/.xprofile injection (dwm doesn't read XDG autostart) ---
XPROFILE="$HOME/.xprofile"
if grep -q "spice-vdagent" "$XPROFILE" 2>/dev/null; then
    echo "  ~/.xprofile already has spice-vdagent"
else
    echo "  Adding spice-vdagent to ~/.xprofile..."
    cat >> "$XPROFILE" << 'XPROFILE_ENTRY'

# VM clipboard sharing — only runs when inside a VM
command -v spice-vdagent &>/dev/null && spice-vdagent &
XPROFILE_ENTRY
    echo "  Added to $XPROFILE"
fi

# Start now if in a graphical session
if [ -n "$DISPLAY" ]; then
    if ! pgrep -x spice-vdagent &>/dev/null; then
        echo "  Starting spice-vdagent..."
        spice-vdagent &
    else
        echo "  spice-vdagent already running"
    fi
fi

##################################################################################################################################
# 4. Summary
##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "VM clipboard sharing:"
echo "  - spice-vdagent (clipboard sync, auto-resize)"
echo "  - qemu-guest-agent (host-guest communication)"
echo "  - xclip (clipboard utilities)"
echo
echo "Services enabled (systemd):"
echo "  - spice-vdagentd.socket (system daemon, socket-activated)"
echo "  - qemu-guest-agent (host communication)"
echo
echo "Copy/paste between host and VM should work after next login."
echo "If not working now, log out and back in (or reboot)."
echo
tput sgr0

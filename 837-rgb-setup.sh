#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install OpenRGB and set all RGB hardware (fans, RAM, GPU, keyboard) to a static color at boot.
#             Uses a systemd oneshot unit (openrgb-boot.service) to apply the color on every boot.
#             OpenRGB is only in the Ubuntu archive from 26.04 on — on 24.04 this script stops
#             with manual instructions instead of pulling a third-party .deb.
#             i2c-dev is loaded in the boot script so OpenRGB can reach RAM RGB controllers over SMBus.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

RGB_COLOR="ff8000"

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
echo "################### RGB setup"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Authenticate sudo once; keepalive prevents expiry during install
##################################################################################################################################

sudo -v
while true; do timeout 30 sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!

trap "kill $SUDO_KEEPALIVE 2>/dev/null" EXIT

ensure_apt_components universe
apt_update

##################################################################################################################################
# Step 1: Install OpenRGB
##################################################################################################################################

echo
tput setaf 3
echo "── Installing OpenRGB ───────────────────────────────────────────────────"
tput sgr0

pkg_install openrgb && { tput setaf 2; echo "  openrgb installed."; tput sgr0; } || {
    tput setaf 1
    echo "ERROR: failed to install openrgb." >&2
    echo "       openrgb is only in the Ubuntu archive from 26.04 (resolute) on." >&2
    echo "       On 24.04, the upstream .deb from openrgb.org is the option — not" >&2
    echo "       auto-installed by design (third-party package). After installing it" >&2
    echo "       manually, rerun this script to write the boot unit." >&2
    tput sgr0
    exit 1
}

# Reload udev rules so the openrgb USB rules (60-openrgb.rules) take effect immediately
sudo udevadm control --reload-rules
sudo udevadm trigger 2>/dev/null || true

##################################################################################################################################
# Step 1b: List detected devices — device *indices* below (--device 2) are
# assigned by OpenRGB's enumeration order, not a stable hardware ID. That
# order depends on USB/I2C enumeration timing and isn't guaranteed to match
# what a previous install saw, even on identical physical hardware. Printed
# here so it's visible in this run's output — confirm device 2 is actually
# the motherboard (ASUS Aura) below before trusting the boot script.
##################################################################################################################################

echo
tput setaf 3
echo "── Detected devices (confirm index 2 below is the motherboard!) ─────────"
tput sgr0
sudo modprobe i2c-dev 2>/dev/null || true
sleep 2
sudo openrgb --list-devices || echo "  (--list-devices failed — devices may still be enumerating; check manually after boot)"

##################################################################################################################################
# Step 2: Write a systemd unit to apply the color at every boot
##################################################################################################################################

echo
tput setaf 3
echo "── Writing openrgb-boot.service ────────────────────────────────────────"
tput sgr0

sudo tee /usr/local/bin/openrgb-boot.sh > /dev/null <<EOF
#!/bin/sh
# i2c-dev is required for OpenRGB to reach RAM RGB controllers over SMBus
modprobe i2c-dev
# Allow USB devices (keyboard, fan hub) time to enumerate before OpenRGB scans
sleep 5
# Resize ASUS Aura Addressable zones on device 2 (motherboard) to 100 LEDs each.
# Zones 1-3 map to Aura Addressable 1-3 headers; fans and PSU light strip are
# connected via the Fractal case ARGB hub. LED count intentionally overshoots --
# single static color makes the exact count irrelevant.
# NOTE: "--device 2" is an enumeration-order index, not a stable hardware ID —
# re-verify with 'openrgb --list-devices' if RGB misbehaves after a reinstall.
openrgb --device 2 --zone 1 --size 100
openrgb --device 2 --zone 2 --size 100
openrgb --device 2 --zone 3 --size 100
openrgb --mode static --color ${RGB_COLOR}
EOF

sudo chmod 755 /usr/local/bin/openrgb-boot.sh

sudo tee /etc/systemd/system/openrgb-boot.service > /dev/null <<'UNITEOF'
[Unit]
Description=Set RGB hardware to static color at boot
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/openrgb-boot.sh

[Install]
WantedBy=multi-user.target
UNITEOF

sudo systemctl daemon-reload
sudo systemctl enable openrgb-boot.service
tput setaf 2; echo "  openrgb-boot.service written and enabled (color: #${RGB_COLOR})."; tput sgr0

##################################################################################################################################
# Step 3: Apply color now
##################################################################################################################################

echo
tput setaf 3
echo "── Applying color now ────────────────────────────────────────────────────"
tput sgr0

sudo modprobe i2c-dev 2>/dev/null || true

if sudo openrgb --mode static --color "$RGB_COLOR"; then
    tput setaf 2; echo "  RGB set to #${RGB_COLOR}."; tput sgr0
else
    tput setaf 3
    echo "  WARNING: openrgb exited non-zero — some devices may not be detected yet."
    echo "  Check detected hardware:  openrgb --list-devices"
    echo "  The boot script will retry on next boot."
    tput sgr0
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
tput setaf 2
echo "RGB hardware will be set to #${RGB_COLOR} on every boot via openrgb-boot.service."
echo "To change the color, edit RGB_COLOR in this script and rerun, or edit /usr/local/bin/openrgb-boot.sh directly."
echo "To check detected devices:  openrgb --list-devices"
tput sgr0
echo

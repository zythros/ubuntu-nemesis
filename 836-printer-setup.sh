#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install CUPS + Epson ET-3950 driver (ESCPR2) + Avahi for network
#             printer discovery.  After running, add the printer via the CUPS
#             web UI at http://localhost:631.
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
echo "################### Setting up Epson ET-3950 printer + scanner"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Authenticate sudo once; keepalive prevents expiry during installs
##################################################################################################################################

sudo -v
while true; do timeout 30 sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!

trap "kill $SUDO_KEEPALIVE 2>/dev/null" EXIT

ensure_apt_components universe
apt_update

##################################################################################################################################
# 1. CUPS
##################################################################################################################################

echo
tput setaf 3
echo "── CUPS ──────────────────────────────────────────────────────"
tput sgr0

for pkg in cups; do
    if pkg_installed "$pkg"; then
        echo "$pkg already installed — skipping."
    else
        echo "Installing $pkg ..."
        pkg_install "$pkg" || true
        if pkg_installed "$pkg"; then
            tput setaf 2; echo "$pkg installed."; tput sgr0
        else
            tput setaf 1; echo "ERROR: $pkg installation failed." >&2; tput sgr0
        fi
    fi
done

##################################################################################################################################
# 2. Avahi — mDNS / network printer auto-discovery
##################################################################################################################################

echo
tput setaf 3
echo "── Avahi (mDNS / network printer discovery) ──────────────────"
tput sgr0

for pkg in avahi-daemon libnss-mdns; do
    if pkg_installed "$pkg"; then
        echo "$pkg already installed — skipping."
    else
        echo "Installing $pkg ..."
        pkg_install "$pkg" || true
        if pkg_installed "$pkg"; then
            tput setaf 2; echo "$pkg installed."; tput sgr0
        else
            tput setaf 1; echo "ERROR: $pkg installation failed." >&2; tput sgr0
        fi
    fi
done

# Patch /etc/nsswitch.conf so .local hostnames resolve via mDNS
# (libnss-mdns's postinst normally does this already on Ubuntu — kept as a check)
if grep -q 'mdns_minimal' /etc/nsswitch.conf; then
    echo "nsswitch.conf already has mdns_minimal — skipping."
else
    echo "Patching /etc/nsswitch.conf for mDNS ..."
    sudo sed -i '/^hosts:/ s/dns/mdns_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf
    tput setaf 2; echo "nsswitch.conf patched."; tput sgr0
fi

##################################################################################################################################
# 3. Print job manager GUI
##################################################################################################################################

echo
tput setaf 3
echo "── system-config-printer ─────────────────────────────────────"
tput sgr0

if pkg_installed system-config-printer; then
    echo "system-config-printer already installed — skipping."
else
    echo "Installing system-config-printer ..."
    pkg_install system-config-printer || true
    if pkg_installed system-config-printer; then
        tput setaf 2; echo "system-config-printer installed."; tput sgr0
    else
        tput setaf 1; echo "ERROR: system-config-printer installation failed." >&2; tput sgr0
    fi
fi

##################################################################################################################################
# 4. SANE + Simple Scan (scanner support)
##################################################################################################################################

echo
tput setaf 3
echo "── SANE + scanner frontends (skanlite, gscan2pdf) ───────────"
tput sgr0

for pkg in sane-utils skanlite gscan2pdf; do
    if pkg_installed "$pkg"; then
        echo "$pkg already installed — skipping."
    else
        echo "Installing $pkg ..."
        pkg_install "$pkg" || true
        if pkg_installed "$pkg"; then
            tput setaf 2; echo "$pkg installed."; tput sgr0
        else
            tput setaf 1; echo "ERROR: $pkg installation failed." >&2; tput sgr0
        fi
    fi
done

# Add printer IP to epsonds backend so SANE can find the network scanner
EPSONDS_CONF="/etc/sane.d/epsonds.conf"
PRINTER_IP="10.0.100.103"
if grep -qF "net $PRINTER_IP" "$EPSONDS_CONF" 2>/dev/null; then
    echo "epsonds.conf already has $PRINTER_IP — skipping."
else
    echo "Adding $PRINTER_IP to $EPSONDS_CONF ..."
    echo "net $PRINTER_IP" | sudo tee -a "$EPSONDS_CONF" > /dev/null
    tput setaf 2; echo "epsonds.conf updated."; tput sgr0
fi

##################################################################################################################################
# 5. Epson ESCPR2 driver  (ET-3950 requires ESCPR2, not the older ESCPR)
##################################################################################################################################

echo
tput setaf 3
echo "── Epson ESCPR2 driver ────────────────────────────────────────"
tput sgr0

DRIVER_PKG="epson-inkjet-printer-escpr2"
if pkg_installed "$DRIVER_PKG"; then
    echo "$DRIVER_PKG already installed — skipping."
else
    # Not in the Ubuntu archive (only the older printer-driver-escpr is).
    # Epson publishes a .deb, but it's a third-party download — not fetched
    # automatically by design, same policy as AUR in artix-nemesis.
    tput setaf 3
    echo "NOTE: $DRIVER_PKG isn't in the Ubuntu archive."
    echo "      Skipping — third-party packages aren't auto-installed by design. Options:"
    echo "        - Download Epson's official .deb (\"ESC/P-R Driver 2\", x86_64) from Epson's"
    echo "          Linux driver download site, then: sudo apt install ./epson-inkjet-printer-escpr2_*.deb"
    echo "        - Or try driverless IPP (works with most AirPrint-capable Epsons — untested here):"
    echo "          sudo lpadmin -p Epson-ET-3950 -E -v ipp://10.0.100.103/ipp/print -m everywhere"
    echo "      Without one of those, step 8 below won't find a PPD and the printer add will fail."
    tput sgr0
fi

##################################################################################################################################
# 6. Enable and start services (systemd)
##################################################################################################################################

echo
tput setaf 3
echo "── Enabling services ─────────────────────────────────────────"
tput sgr0

# Ubuntu enables both on install already — this is a no-op unless someone
# disabled them, but keeps the script's end state explicit.
for svc in cups avahi-daemon; do
    echo "Enabling + starting $svc ..."
    if sudo systemctl enable --now "$svc.service"; then
        tput setaf 2; echo "  $svc enabled and running."; tput sgr0
    else
        tput setaf 1; echo "  $svc failed — check: systemctl status $svc" >&2; tput sgr0
    fi
done

##################################################################################################################################
# 7. Add current user to lpadmin group
#    Ubuntu's CUPS uses lpadmin (not Arch's lp) as the printer-admin group.
##################################################################################################################################

echo
tput setaf 3
echo "── User group ────────────────────────────────────────────────"
tput sgr0

if id -nG "$USER" | grep -qw lpadmin; then
    echo "$USER is already in the lpadmin group."
else
    echo "Adding $USER to lpadmin group ..."
    sudo usermod -aG lpadmin "$USER"
    tput setaf 2; echo "$USER added to lpadmin group."; tput sgr0
    tput setaf 3; echo "NOTE: group change takes effect on next login."; tput sgr0
fi

##################################################################################################################################
# 8. Add the ET-3950 to CUPS
##################################################################################################################################

PRINTER_NAME="Epson-ET-3950"
PRINTER_URI="socket://10.0.100.103:9100"

echo
tput setaf 3
echo "── Adding printer to CUPS ────────────────────────────────────"
tput sgr0

if lpstat -p "$PRINTER_NAME" &>/dev/null; then
    echo "Printer '$PRINTER_NAME' already configured in CUPS — skipping."
else
    echo "Looking for ET-3950 PPD ..."
    PPD=$(lpinfo -m 2>/dev/null | grep -i 'ET.3950' | head -1 | awk '{print $1}')
    if [ -z "$PPD" ]; then
        tput setaf 1
        echo "ERROR: No PPD found for ET-3950. Is epson-inkjet-printer-escpr2 installed?" >&2
        tput sgr0
    else
        tput setaf 2; echo "Found PPD: $PPD"; tput sgr0
        echo "Adding '$PRINTER_NAME' at $PRINTER_URI ..."
        sudo lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_URI" -m "$PPD" -D "Epson ET-3950"
        sudo lpadmin -d "$PRINTER_NAME"
        tput setaf 2
        echo "Printer '$PRINTER_NAME' added and set as default."
        tput sgr0
    fi
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "Printer management: http://localhost:631"
echo
tput sgr0

#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install MPD (Music Player Daemon) + ncmpcpp TUI client; run MPD
#             as a systemd --user service (so it reaches the user's PipeWire
#             socket natively — no system-service-patched-to-run-as-user dance
#             like artix-nemesis's OpenRC version needs).
#
#             MPD's TCP listener (0.0.0.0:6600) requires a password — anonymous
#             connections get no permissions at all. Without this, anyone on the
#             LAN could control playback, read the library, and (with
#             auto_update on) trigger rescans. The local unix socket stays
#             password-free, which is what ncmpcpp uses.
#
#             rmpc (artix-nemesis's client) isn't in the Ubuntu archive —
#             ncmpcpp is the official-archive equivalent.
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
echo "################### Setting up MPD + ncmpcpp"
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
# 1. MPD + ncmpcpp
##################################################################################################################################

echo
tput setaf 3
echo "── MPD + ncmpcpp ─────────────────────────────────────────────"
tput sgr0

for pkg in mpd ncmpcpp; do
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
# 2. Disable Ubuntu's system-wide MPD instance
#    The mpd package enables a *system* mpd.service + mpd.socket on install,
#    running as the 'mpd' user. It would grab port 6600 before the user
#    service below and can't reach the desktop user's PipeWire session anyway.
##################################################################################################################################

echo
tput setaf 3
echo "── Disabling system-wide mpd ─────────────────────────────────"
tput sgr0

sudo systemctl disable --now mpd.service mpd.socket 2>/dev/null || true
tput setaf 2; echo "System mpd.service/mpd.socket disabled (user service used instead)."; tput sgr0

##################################################################################################################################
# 3. ~/.config/mpd/mpd.conf — write a complete, ready-to-use user-level config
##################################################################################################################################

echo
tput setaf 3
echo "── mpd.conf ──────────────────────────────────────────────────"
tput sgr0

MPD_DATA_DIR="$HOME/.local/share/mpd"
MPD_CONF_DIR="$HOME/.config/mpd"
MPD_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mpd/socket"
mkdir -p "$MPD_DATA_DIR/playlists" "$MPD_CONF_DIR"

# Reuse an existing password across re-runs — this file is rewritten
# unconditionally below, so without this a re-run would silently generate
# a fresh password and lock out any remote client already configured with
# the old one.
MPD_PASSWORD=""
if [ -f "$MPD_CONF_DIR/mpd.conf" ]; then
    MPD_PASSWORD=$(grep -E '^password[[:space:]]+"' "$MPD_CONF_DIR/mpd.conf" 2>/dev/null \
        | head -1 | sed -E 's/^password[[:space:]]+"([^@]+)@.*/\1/')
fi
if [ -n "$MPD_PASSWORD" ]; then
    echo "  → reusing existing MPD password from $MPD_CONF_DIR/mpd.conf"
else
    MPD_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)
    echo "  → generated a new MPD password"
fi

cat > "$MPD_CONF_DIR/mpd.conf" << EOF
# MPD configuration — managed by 861-mpd-setup.sh
# Full reference: https://mpd.readthedocs.io/en/stable/user.html#configuration

# Set this to your music library path, then restart MPD:
#music_directory "~/Music"

playlist_directory  "$MPD_DATA_DIR/playlists"
db_file             "$MPD_DATA_DIR/tag_cache"
state_file          "$MPD_DATA_DIR/state"
sticker_file        "$MPD_DATA_DIR/sticker.sql"

log_file            "$MPD_DATA_DIR/log"
log_level           "notice"

# TCP for remote clients (password-gated below); Unix socket for local
# clients (ncmpcpp uses this one).
bind_to_address     "any"
bind_to_address     "$MPD_SOCKET"
port                "6600"

# Anonymous connections get nothing. The local unix socket is trusted
# outright (local_permissions) — reaching it already requires local OS
# access to \$XDG_RUNTIME_DIR, a different trust boundary than an open
# TCP port. Everything else, including TCP connections from localhost,
# needs the password.
default_permissions ""
local_permissions    "read,add,control,player,admin"
password             "$MPD_PASSWORD@read,add,control,player,admin"

# Automatically update the database when music files change (Linux inotify).
auto_update         "yes"

input {
    plugin "curl"
}

audio_output {
    type   "pulse"
    name   "PipeWire"
}
EOF

mkdir -p "$(dirname "$MPD_SOCKET")"

# mpd.conf holds the password in plaintext — restrict it to the owner.
chmod 600 "$MPD_CONF_DIR/mpd.conf"

tput setaf 2; echo "Wrote $MPD_CONF_DIR/mpd.conf."; tput sgr0

##################################################################################################################################
# 4. ncmpcpp — point it at the local unix socket (no password needed there)
##################################################################################################################################

echo
tput setaf 3
echo "── ncmpcpp config ────────────────────────────────────────────"
tput sgr0

NCMPCPP_CONF="$HOME/.config/ncmpcpp/config"
mkdir -p "$(dirname "$NCMPCPP_CONF")"
if grep -qF "mpd_host = \"$MPD_SOCKET\"" "$NCMPCPP_CONF" 2>/dev/null; then
    echo "ncmpcpp already points at $MPD_SOCKET — skipping."
elif grep -qE '^[[:space:]]*mpd_host[[:space:]]*=' "$NCMPCPP_CONF" 2>/dev/null; then
    sed -i -E "s|^[[:space:]]*mpd_host[[:space:]]*=.*|mpd_host = \"$MPD_SOCKET\"|" "$NCMPCPP_CONF"
    tput setaf 2; echo "Updated mpd_host in $NCMPCPP_CONF."; tput sgr0
else
    cat >> "$NCMPCPP_CONF" << EOF
# Managed by 861-mpd-setup.sh — local unix socket, no password required
mpd_host = "$MPD_SOCKET"
mpd_music_dir = "~/Music"
EOF
    tput setaf 2; echo "Wrote $NCMPCPP_CONF."; tput sgr0
fi

##################################################################################################################################
# 5. Enable and start MPD as a systemd --user service
##################################################################################################################################

echo
tput setaf 3
echo "── Enabling MPD user service ─────────────────────────────────"
tput sgr0

# Lingering lets the user service start at boot without an active login
# session (matches the "always running" behavior of artix-nemesis's system service).
if loginctl show-user "$USER" -p Linger 2>/dev/null | grep -q 'Linger=yes'; then
    echo "Lingering already enabled for $USER."
else
    sudo loginctl enable-linger "$USER"
    tput setaf 2; echo "Lingering enabled for $USER (user services now start at boot)."; tput sgr0
fi

systemctl --user daemon-reload
if systemctl --user enable --now mpd.service && systemctl --user restart mpd.service; then
    tput setaf 2; echo "mpd.service (user) enabled and running."; tput sgr0
else
    echo "mpd.service failed to start — check: systemctl --user status mpd.service"
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "MPD config:    $MPD_CONF_DIR/mpd.conf  ← uncomment and set music_directory"
echo "MPD data:      $MPD_DATA_DIR/"
echo "Connect:       ncmpcpp  (local socket $MPD_SOCKET — no password needed)"
echo "ncmpcpp config: $NCMPCPP_CONF"
echo "Service:       systemctl --user {status,restart,stop} mpd.service"
echo
tput setaf 3
echo "MPD password (needed by any TCP client — e.g. a phone app on port 6600):"
echo "  $MPD_PASSWORD"
echo "Same value on every re-run of this script; stored in mpd.conf (chmod 600)."
tput sgr0
echo
tput sgr0

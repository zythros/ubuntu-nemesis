#!/bin/bash
# Shared helpers for ubuntu-nemesis setup scripts.
# Source this at the top of any script that calls apt:
#   source "$(dirname "$(readlink -f "$0")")/lib.sh"
#
# This is the Ubuntu port of zythros/artix-nemesis. artix-nemesis runs every
# pacman transaction through a hand-rolled "nohook" config because pacman
# hooks hang on Artix/OpenRC (no system D-Bus while running as root). Ubuntu
# is systemd-based — dbus is always up, dpkg triggers/maintainer scripts just
# run — so none of that machinery exists here.
#
# Package policy (carried over from artix-nemesis's no-AUR rule): official
# Ubuntu archive only — main/restricted/universe/multiverse. No PPAs, no
# third-party apt repos, no snaps/flatpaks pulled in by these scripts.
# Anything not in the archive is skipped with manual instructions instead.

# Wait up to 5 min for the dpkg lock instead of failing — unattended-upgrades
# routinely holds it for a while right after a fresh install boots.
APT_GET=(sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300)

##################################################################################################################################
# apt_update
#
# Refresh package lists. Call once near the top of any script that installs.
##################################################################################################################################

apt_update() {
    "${APT_GET[@]}" update
}

##################################################################################################################################
# pkg_installed <pkg>
#
# True if the package is fully installed (not just known/removed-with-config).
# The Ubuntu equivalent of `pacman -Q <pkg>`.
##################################################################################################################################

pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

##################################################################################################################################
# pkg_install <pkg>...
#
# Install package(s) from the configured Ubuntu archive components. Returns
# non-zero if any package isn't available or the install fails; callers should
# treat that as "not in the Ubuntu archive" rather than a hard error.
##################################################################################################################################

pkg_install() {
    "${APT_GET[@]}" install -y "$@"
}

##################################################################################################################################
# ensure_apt_components <component>...
#
# Make sure the given official archive components (universe, multiverse,
# restricted) are enabled. Stock Ubuntu Desktop/Server installs already enable
# all four; minimal/cloud images sometimes don't. Official Ubuntu archive only —
# this never adds a PPA or third-party source.
##################################################################################################################################

ensure_apt_components() {
    local comp missing=()
    for comp in "$@"; do
        # deb822 (24.04+): "Components: main restricted universe multiverse"
        # legacy one-line:  "deb http://archive.ubuntu.com/ubuntu noble main universe"
        if ! grep -rhsE "^(Components:.*|deb .*ubuntu.*)[[:space:]]$comp([[:space:]]|$)" \
                /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | grep -q .; then
            missing+=("$comp")
        fi
    done
    [ ${#missing[@]} -eq 0 ] && return 0

    echo "Enabling Ubuntu archive component(s): ${missing[*]} ..."
    if ! command -v add-apt-repository &>/dev/null; then
        "${APT_GET[@]}" install -y software-properties-common
    fi
    for comp in "${missing[@]}"; do
        sudo add-apt-repository -y -n "$comp"
    done
    apt_update
}

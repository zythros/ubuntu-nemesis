# Porting notes: artix-nemesis (Artix/OpenRC) → ubuntu-nemesis (Ubuntu/systemd)

What changed going from `zythros/artix-nemesis` (as of `c78210a`) to this repo,
and why. Written at port time, 2026-10-26. Where a systemd-side fix already
existed in `zythros/arch-systemd-nemesis`, it was reused rather than
re-derived — noted below.

**Targets:** Ubuntu 24.04 LTS (noble) and 26.04 LTS (resolute). Every package
name used here was checked against both releases' official archive indexes
(`Packages.xz` + `Contents-amd64.gz`) at port time. Nothing has been run on a
real Ubuntu machine yet — first live run is the real test.

## Package manager: pacman → apt

- **`lib.sh`'s nohook machinery is gone.** artix-nemesis routes every pacman
  call through a temp config with an empty `HookDir` (and moves
  `/usr/share/libalpm/hooks` aside) because hooks hang on OpenRC with no
  D-Bus. Ubuntu is systemd; dpkg maintainer scripts and triggers just run.
  `lib.sh` now has `apt_update`, `pkg_installed` (the `pacman -Q` equivalent,
  via `dpkg-query`), `pkg_install`, and `ensure_apt_components`.
- **Lock handling:** artix's 120s `timeout` + `db.lck` deletion is replaced by
  `apt-get -o DPkg::Lock::Timeout=300` — waits for unattended-upgrades instead
  of deleting a lock out from under it.
- **No-AUR policy → official-archive-only policy.** `801-chaotic-aur-setup.sh`
  and `chaotic-aur-removal.sh` are dropped (nothing to port to). The Ubuntu
  analogue of "enable an extra official repo" is enabling archive components
  (`universe`, `multiverse`, `restricted`), done per-script on demand. No PPAs.
- **Desktop-database / icon-cache refresh** at the end of 803 removed —
  dpkg triggers do it.

## Init system: OpenRC → systemd (mostly from arch-systemd-nemesis)

- **802: no `dbus-launch` wrapper** in `dwm.desktop` — `pam_systemd` +
  `dbus-user-session` give every graphical login a session bus.
- **896: no `shared-root` service** — systemd mounts `/` rshared at boot.
  The distrobox#1983 note (stop/rm hang) is dropped too: it's specific to
  non-systemd hosts.
- **837:** `/etc/local.d/rgb.start` → `openrgb-boot.service` (oneshot) +
  `/usr/local/bin/openrgb-boot.sh`. Also carries over arch-systemd's
  `openrgb --list-devices` preflight (`--device 2` is enumeration order, not a
  stable ID). The `timeout 10` on `udevadm trigger` (eudev hang) is dropped.
- **840:** `snapper-openrc` services → `snapper-timeline.timer` /
  `snapper-cleanup.timer`.
- **870:** `virt-what` → `systemd-detect-virt --vm`. `spice-vdagentd` is
  socket-activated on Ubuntu; `qemu-guest-agent.service` is static
  (udev-started), so it's only started, not enabled.
- **895:** `rc-update`/`rc-service` → `systemctl enable --now`
  (`libvirtd.service`, `virtlogd.socket`).

## Ubuntu-specific changes

- **802 display manager.** artix assumed LightDM. Ubuntu Desktop ships GDM,
  which still launches X11 xsessions (via `gdm-x-session`, present in both
  24.04 and 26.04), and `~/.xprofile` is sourced by both GDM and LightDM. 802
  installs LightDM only if there's *no* display manager — it never replaces one.
- **802 xorg:** `xserver-xorg` moved from main to **universe in 26.04** (GNOME
  is Wayland-only there), so 802 installs it explicitly.
- **802 removes Ubuntu's `dwm` package** if present — it owns
  `/usr/share/xsessions/dwm.desktop`, which 802 writes.
- **820:** Ubuntu's dmenu lives in `suckless-tools` (removed, like artix
  removes pacman's dmenu; `j4-dmenu-desktop` doesn't depend on it). The
  `dmenu-desktop` wrapper now calls `/usr/local/bin/dmenu` by absolute path,
  since `-c` only exists in the fork.
- **830:** Ubuntu has no `slstatus` package, so the "remove packaged
  slstatus" step is a no-op comment.
- **803 networking:** `connman-gtk` → `network-manager-gnome`
  (`nm-connection-editor`). ConnMan was only there because it's Artix's
  default; NetworkManager is Ubuntu Desktop's. On Ubuntu Server
  (netplan + networkd) the post-install just warns rather than switching
  renderers mid-script.
- **803 vlc:** artix installs `libdvdcss libdvdread libdvdnav libbluray`.
  On Ubuntu, `vlc-plugin-base` already depends on dvdread/dvdnav/bluray;
  `libdvdcss` comes from `libdvd-pkg` (multiverse), which **downloads source
  from VideoLAN and builds it locally** — Ubuntu's sanctioned route, but the
  one place these scripts fetch something from outside the archive.
- **803:** `python-yaml`/`python-matplotlib` → `python3-yaml`/`python3-matplotlib`.
- **837:** `openrgb` is in the archive **only from 26.04**. On 24.04 the
  script stops with instructions (upstream `.deb` is third-party).
- **840:** `snap-pac` → snapper's own apt hook (`/etc/apt/apt.conf.d/80snapper`).
  `grub-btrfs` and `snapper-rollback` aren't in the Ubuntu archive → skipped
  with GitHub links; if installed manually, 840 detects and wires them up.
  Since grub-btrfs is optional now, the hard "GRUB required" exit is dropped.
- **880 / 881:** `nvidia-open-dkms` + Arch `[extra]` → `ubuntu-drivers install
  nvidia:<branch>-open` from `restricted`. Branch defaults to whatever
  `ubuntu-drivers devices` recommends (override with `NVIDIA_BRANCH`).
  ubuntu-drivers prefers Canonical's prebuilt, signed
  `linux-modules-nvidia-*` packages, which avoids DKMS rebuilds and Secure Boot
  MOK enrollment. Module check switched from `dkms status` (blind to prebuilt
  modules) to `modinfo -k`. `mkinitcpio -P` → `update-initramfs -u -k all`;
  `grub-mkconfig` → `update-grub`. systemd-boot branches dropped (Ubuntu
  uses GRUB).
- **890:** mkinitcpio `MODULES=()` → `/etc/initramfs-tools/modules`
  (`vfio vfio_iommu_type1 vfio_pci`), plus `softdep nvidia/nouveau pre: vfio-pci`
  in `vfio.conf` so vfio-pci wins even if nvidia loads first.
- **895:** package set mapped to Ubuntu names (`qemu-system-x86`,
  `libvirt-daemon-system`, `libvirt-clients`, `dnsmasq-base`, `ovmf`,
  `swtpm-tools`, `libguestfs-tools`). `bridge-utils` dropped (never used — same
  finding as arch-systemd). Default network XML path and OVMF path
  (`/usr/share/OVMF/OVMF_CODE_4M.fd`) updated. The hardcoded
  `IOMMU group 36: 3f:00.0` hint is now re-detected live (from arch-systemd).
- **kernel-rollback.sh:** fully rewritten. Ubuntu has no pacman cache of old
  kernel packages, but keeps previous kernels installed. The script now picks
  an installed kernel with fzf, sets `GRUB_DEFAULT=saved` if needed (asks
  first), then `grub-reboot` (next boot only) or `grub-set-default`
  (persistent), marks that kernel's packages `apt-mark manual` so autoremove
  can't delete it, and rebuilds DKMS for it.

## Small fixes

- `menu-fzf.sh`: the 837 entry said `#fbba2b`; the script sets `ff8000`.
  Label fixed to match the script.
- `840`: dropped artix's unused `installed_dir=...` line and the
  "pacman not found" check.

## Not ported

- `801-chaotic-aur-setup.sh`, `chaotic-aur-removal.sh` — no Ubuntu equivalent.
- `897-webull-setup.sh` — gitignored/local-only in artix-nemesis; same here.
- `NOTES.md` — gitignored session log in artix-nemesis; same here.
- `836-printer-setup.sh`, `861-mpd-setup.sh` — ported, then removed (not needed).

## Carried-over loose ends from artix-nemesis

- `802`'s keybindings cheat sheet still lists `Mod+m` → mullvad-browser (the
  `zythros/dwm` config.h binding), though no script installs it.

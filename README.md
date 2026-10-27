# ubuntu-nemesis

Numbered post-install setup scripts for **Ubuntu (24.04 / 26.04 LTS) + systemd + dwm**,
ported from [`zythros/artix-nemesis`](https://github.com/zythros/artix-nemesis)
(Artix Linux + OpenRC + dwm + LightDM). Same run-standalone-or-via-fzf-menu
structure.

Companion repos: [`zythros/dwm`](https://github.com/zythros/dwm) (personal
dwm fork), [`zythros/dmenu`](https://github.com/zythros/dmenu),
[`zythros/slstatus`](https://github.com/zythros/slstatus).

See [`PORTING-NOTES.md`](PORTING-NOTES.md) for exactly what changed from
artix-nemesis and why.

## Usage

```
git clone https://github.com/zythros/ubuntu-nemesis
cd ubuntu-nemesis
./menu-fzf.sh
```

Or run any numbered script standalone: `./803-apps-setup.sh`.

**Read every script before running it.** These are tailored to one person's
hardware and preferences (GPU models, printer IP, disk paths, package
choices) — treat them as a reference to adapt, not a turnkey installer.

## Package policy

Official Ubuntu archive only (main / restricted / universe / multiverse —
enabled on demand by `lib.sh`'s `ensure_apt_components`). No PPAs, no
third-party apt repos, no snaps or flatpaks. Things that aren't in the archive
(Epson ESCPR2 driver, grub-btrfs, snapper-rollback, OpenRGB on 24.04) are
skipped with manual instructions — the Ubuntu equivalent of artix-nemesis's
"no AUR" rule.

## Layout

- `802`–`896` — numbered setup scripts, runnable standalone or picked via
  `menu-fzf.sh` (order matters for a few: `802` before `820`/`830`).
- `lib.sh` — shared apt helpers, sourced by every numbered script.
- `menu-fzf.sh` — fzf multi-select menu that runs chosen scripts in order.
- `kernel-rollback.sh` — standalone utility, not wired into the menu.

## License

No license file — personal-use scripts shared for reference. Ask before
reusing verbatim in something you're distributing.

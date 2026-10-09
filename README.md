# debian-deploy
Sets up Debian 13 Trixie + Hyprland + Noctalia.
-> Also a foolish attempt to keep configs in sync between my devices.

# Usage
1. Install Debian Trixie with a sudo user and working internet. No desktop needed.
2. Reboot and log in to your sudo user.
3. Clone this repo into `~/.local/deploy` (or somewhere you intend to keep it).
4. Configure `vars.sh` (GPU driver mostly).
5. Run `./deploy.sh --dry-run` to see what it will install.
6. Run `./deploy.sh` as your user.
7. Reboot, log in on a TTY and run `start-hyprland`.

Installs Alacritty, Thunar, Firefox ESR, Zsh and the usual audio/network/Bluetooth
stuff too. Hyprland comes from Trixie backports; Noctalia has its own APT repo.

## Graphics
Set `GPU_DRIVER` in `vars.sh` to `intel`, `amd`, `nvidia`, `nouveau` or `vm`.
You can also set it for one run: `GPU_DRIVER=vm ./deploy.sh`.

- `nvidia` uses Debian's proprietary driver and stock Trixie kernel. The script
  rejects kernels 6.16 and newer. Check [Debian's NVIDIA guide](https://wiki.debian.org/NvidiaGraphicsDrivers)
  for GPU support and Secure Boot setup before using it.
- For QEMU/KVM, use `vm` with Virtio graphics and 3D acceleration enabled on the
  host. If that isn't available, try `VM_SOFTWARE_RENDERING=true` (slower).
- `VM_GUEST=auto` picks the QEMU or VMware guest tools. Set it to `qemu`, `vmware`
  or `none` if needed. For GPU passthrough, use the actual GPU profile.

Supports amd64 and arm64. The Intel profile is amd64 only.

# Maintenance
Dotfiles are linked from this repo's `dotfiles` directory into `~/.config`.
Keep the repo where you cloned it. Existing configs are backed up under
`~/.local/state/debian-deploy/backups/` when replaced.

## Pushing Changes
1. Make changes.
2. Git push (ideally not into my repo lol).

## Pulling Changes
1. Git pull.
2. Enjoy.

*Note: `vars.sh` is tracked too, so keep an eye on your local changes when pulling.*
*-> You only need to re-deploy for package or setup changes.*

## Configs
Packages and services are listed in `vars.sh`.
Hyprland settings are in `dotfiles/hypr/hyprland.lua` (including my German/Bone
keyboard layout and monitor settings, so you'll probably want to change those).
Hardware settings are generated in `~/.config/debian-deploy/graphics.lua` on deploy.

## Keybinds
- Super+Return: Alacritty
- Super+D: Launcher
- Super+E: Thunar
- Super+L: Lock
- Super+Shift+S: Screenshot to clipboard

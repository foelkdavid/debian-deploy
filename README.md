# debian-deploy

Set up Debian 13 Trixie with Hyprland, Noctalia v5, Alacritty, Thunar, Firefox ESR,
PipeWire audio, NetworkManager, Bluetooth, and this repository's dotfiles.
Supported architectures: amd64 and arm64; the Intel profile is for amd64.

## Usage

1. Install Debian Trixie with a normal user that can run `sudo` and working
   network access. A minimal installation without a desktop task is sufficient.
2. Place this repository at a permanent location in your home directory.
3. Edit `vars.sh`, particularly `GPU_DRIVER`.
4. Review `./deploy.sh --dry-run`, then run `./deploy.sh` as your normal user.
5. Reboot, log in on a TTY, and run `start-hyprland`.

The script uses sudo for system changes, simulates the package transaction before
installation, stops on errors, enables services for the next boot, and changes
your login shell to Zsh. It configures NetworkManager to manage the installer's
ifupdown interfaces and disables the legacy `networking.service` for the next
boot. Your current connections are not explicitly restarted.

## Graphics

Set one option in `vars.sh`, or override it for a run:

```bash
GPU_DRIVER=vm ./deploy.sh
```

| `GPU_DRIVER` | Setup |
| --- | --- |
| `intel` | Intel graphics firmware, Mesa Vulkan/VA-API, Intel media and older i965 drivers |
| `amd` | AMD graphics firmware and Mesa Vulkan/VA-API |
| `nvidia` | Debian's proprietary driver, DKMS, stock kernel and headers, EGL Wayland, VA-API and DRM modesetting |
| `nouveau` | Mesa and firmware for the kernel's open NVIDIA driver |
| `vm` | Mesa virtual graphics, scale 1, software cursors, reduced effects and optional guest tools |

Intel, AMD, Nouveau and VM profiles use Debian's existing kernel drivers. The
NVIDIA profile uses the stock Trixie kernel and driver. Debian's current 550
driver supports Maxwell through Ada/Hopper; RTX 50-series/Blackwell is not
supported. This profile rejects kernels 6.16 or newer, which require different
driver handling. With Secure Boot, enroll the DKMS Machine Owner Key so the
NVIDIA module can load. See the [Debian NVIDIA guide](https://wiki.debian.org/NvidiaGraphicsDrivers)
and [Hyprland NVIDIA guide](https://wiki.hypr.land/Nvidia/).

Reruns regenerate graphics settings. Profiles install packages additively;
switching an existing proprietary NVIDIA installation to Nouveau also requires
removing the proprietary driver packages and rebooting.

### Virtual machines

For QEMU/KVM, use Virtio graphics with 3D acceleration/virgl enabled on the host.
The guest kernel and Mesa provide the graphics driver; a guest agent alone does
not enable 3D. See [Hyprland's virtual GPU documentation](https://wiki.hypr.land/configuring/extra/virtual-gpu/).

`VM_GUEST=auto` selects `qemu-guest-agent` on QEMU/KVM or `open-vm-tools` on VMware.
Set it to `qemu`, `vmware`, or `none` to override detection. For the QEMU agent,
enable its virtio serial channel on the host. Desktop clipboard sharing depends
on the hypervisor's Wayland support; these agents do not provide it universally.

If accelerated rendering is unavailable, set `VM_SOFTWARE_RENDERING=true`.
This asks Mesa to render on the CPU and is slower; the VM still needs a display
device with a working DRM/KMS driver. [Mesa documents this setting](https://docs.mesa3d.org/envvars.html).
For GPU passthrough, choose the actual GPU profile instead of `vm`.

## Packages and repositories

The package arrays and `SERVICES` in `vars.sh` define what is installed or enabled.
The explicit list includes Thunar trash, removable-drive, archive and thumbnail
support; Wayland screenshots and clipboard; GTK file chooser portals; and
Noctalia's network, Bluetooth, brightness, battery and power integrations.
PipeWire/WirePlumber start through systemd user units. UPower, UDisks and portals
use D-Bus activation.

The deployment supplements existing `.list` and `.sources` files with missing
Trixie, updates, security and backports components, including `contrib`,
`non-free`, and `non-free-firmware`. Existing source definitions are preserved.
Hyprland and its portal are explicitly selected from `trixie-backports`, with
backports available for their dependencies. Named stable applications retain
their normal APT candidates, including security updates. The script does not
hold versions; ordinary APT upgrades continue to update installed packages.
See [Debian Backports instructions](https://backports.debian.org/Instructions/).

Noctalia is installed from the community APT repository linked in its
[installation documentation](https://docs.noctalia.dev/noctalia/getting-started/installation/),
using its supplied signing-key package and Trixie source. It is not in Debian's
official Trixie Backports archive. Noctalia starts from Hyprland; fresh settings
enable its built-in Polkit agent. Existing settings are preserved: enable
Settings → Security → Polkit Agent if no other graphical agent is running.

## Dotfiles and maintenance

Hyprland, Alacritty, GTK, Neovim and Zsh directories are linked to `~/.config`.
Existing destinations are backed up under
`~/.local/state/debian-deploy/backups/<timestamp>`; reruns retain correct links.
Keep the repository at the same location.

Fonts and Zsh plugins are downloaded into `~/.local/share`, outside the repository,
and reused on reruns. Hardware settings live in
`~/.config/debian-deploy/graphics.lua`. The scripts honor XDG config/data/cache/state
variables. Hyprland retains the German/Bone layout and home desktop settings,
with a fallback for monitors that cannot yet be queried during startup.

Super+Return opens Alacritty; Super+D opens the launcher; Super+E opens Thunar;
Super+L locks; Super+Shift+S takes a screenshot into the clipboard.

For startup problems, inspect `hyprctl configerrors`,
`journalctl --user -b -u pipewire -u pipewire-pulse -u wireplumber`, and
`~/.cache/noctalia/noctalia.log`.

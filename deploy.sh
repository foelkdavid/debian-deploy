#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$REPO_DIR/vars.sh"
trap 'printf "Deployment failed at line %s. Fix the reported error and rerun.\n" "$LINENO" >&2' ERR

die() { printf '%s\n' "$*" >&2; exit 1; }
DRY_RUN=false
case "${1:-}" in
    --dry-run) DRY_RUN=true ;;
    '') ;;
    *) die "Usage: $0 [--dry-run]" ;;
esac
(( $# <= 1 )) || die "Usage: $0 [--dry-run]"

# A dry run is also useful when reviewing the repository on a non-Debian host.
if command -v dpkg >/dev/null 2>&1; then
    ARCH=$(dpkg --print-architecture)
else
    case "$(uname -m)" in
        x86_64) ARCH=amd64 ;;
        aarch64) ARCH=arm64 ;;
        *) ARCH=unknown ;;
    esac
fi
case "$ARCH" in amd64|arm64) ;; *) die "Noctalia's APT repository requires amd64 or arm64." ;; esac
case "$VM_SOFTWARE_RENDERING" in true|false) ;; *) die "VM_SOFTWARE_RENDERING must be true or false." ;; esac
case "$VM_GUEST" in auto|qemu|vmware|none) ;; *) die "VM_GUEST must be auto, qemu, vmware or none." ;; esac

GPU_PACKAGES=()
GUEST_SERVICES=()
case "$GPU_DRIVER" in
    intel)
        [[ "$ARCH" == amd64 ]] || die "The Intel graphics profile requires amd64."
        GPU_PACKAGES=("${INTEL_PACKAGES[@]}") ;;
    amd) GPU_PACKAGES=("${AMD_PACKAGES[@]}") ;;
    nvidia)
        GPU_PACKAGES=("${NVIDIA_PACKAGES[@]}" "linux-image-$ARCH" "linux-headers-$ARCH") ;;
    nouveau) GPU_PACKAGES=("${NOUVEAU_PACKAGES[@]}") ;;
    vm)
        GPU_PACKAGES=("${VM_PACKAGES[@]}")
        if [[ "$VM_GUEST" == auto ]]; then
            VIRTUALIZATION=$(systemd-detect-virt --vm 2>/dev/null || true)
            case "$VIRTUALIZATION" in
                kvm|qemu) VM_GUEST=qemu ;;
                vmware) VM_GUEST=vmware ;;
                *) VM_GUEST=none ;;
            esac
        fi
        case "$VM_GUEST" in
            qemu) GPU_PACKAGES+=("${QEMU_PACKAGES[@]}") ;; # Static unit, started by its virtio device.
            vmware)
                GPU_PACKAGES+=("${VMWARE_PACKAGES[@]}")
                GUEST_SERVICES+=(open-vm-tools.service) ;;
        esac ;;
    *) die "GPU_DRIVER must be intel, amd, nvidia, nouveau or vm." ;;
esac

CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/debian-deploy
if "$DRY_RUN"; then
    printf 'Target: Debian 13 Trixie (%s), graphics: %s\n' "$ARCH" "$GPU_DRIVER"
    printf 'Stable packages: %s\n' "${PACKAGES[*]} ${GPU_PACKAGES[*]}"
    printf 'Trixie backports: %s\n' "${BACKPORTS_PACKAGES[*]}"
    printf 'Noctalia repository: %s\n' "${NOCTALIA_PACKAGES[*]}"
    printf 'System services: %s\n' "${SERVICES[*]} ${GUEST_SERVICES[*]}"
    printf 'Link dotfiles into %s; install fonts and Zsh plugins; set shell to %s.\n' "$CONFIG_DIR" "$USERSHELL"
    printf 'VM guest: %s; software rendering: %s\n' "$VM_GUEST" "$VM_SOFTWARE_RENDERING"
    exit 0
fi

[[ "$EUID" != 0 ]] || die "Run ./deploy.sh as your normal sudo-capable login user, without sudo in front."
source /etc/os-release
[[ "${ID:-}" == debian && "${VERSION_CODENAME:-}" == trixie ]] || die "This installer targets Debian 13 Trixie only."
[[ -d /run/systemd/system ]] || die "Run this on a booted Debian system with systemd."
if [[ "$GPU_DRIVER" == nvidia ]]; then
    kernel_version=$(uname -r)
    dpkg --compare-versions "${kernel_version%%-*}" lt 6.16 || die "The NVIDIA profile uses Debian's driver with the stock Trixie kernel. Boot a stock Trixie kernel before deploying; newer backports kernels need a different driver."
fi
command -v sudo >/dev/null || die "Install sudo and give your login user sudo access first."
sudo -v

WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "$WORK_DIR"' EXIT
BACKUP_DIR="$STATE_DIR/backups/$(date +%Y%m%d-%H%M%S)-$$"

link_config() {
    local source_path=$1 destination=$2
    mkdir -p -- "$(dirname -- "$destination")"
    if [[ -L "$destination" && "$(readlink -f -- "$destination" || true)" == "$source_path" ]]; then
        return
    fi
    if [[ -e "$destination" || -L "$destination" ]]; then
        mkdir -p -- "$BACKUP_DIR"
        mv -- "$destination" "$BACKUP_DIR/$(basename -- "$destination")"
    fi
    ln -s -- "$source_path" "$destination"
}

printf 'Preparing Debian repositories...\n'
sudo apt-get update
sudo apt-get install -y --no-install-recommends ca-certificates curl python3
# Fill in missing official archive components without replacing existing sources.
python3 "$REPO_DIR/scripts/debian-sources.py" /etc/apt > "$WORK_DIR/debian-deploy.sources"
sudo install -m 644 "$WORK_DIR/debian-deploy.sources" /etc/apt/sources.list.d/debian-deploy.sources

printf 'Preparing the Noctalia repository...\n'
curl --fail --location --retry 3 --output "$WORK_DIR/nickh-archive-keyring.deb" \
    https://pkg.noctalia.dev/deb/nickh-archive-keyring.deb
curl --fail --location --retry 3 --output "$WORK_DIR/noctalia-trixie.sources" \
    https://pkg.noctalia.dev/deb/noctalia-trixie.sources
[[ -s "$WORK_DIR/noctalia-trixie.sources" ]] || die "The Noctalia repository definition is empty."
sudo dpkg -i "$WORK_DIR/nickh-archive-keyring.deb"
sudo install -m 644 "$WORK_DIR/noctalia-trixie.sources" /etc/apt/sources.list.d/noctalia-trixie.sources
sudo apt-get update

# Keep named applications on their normal APT candidates (including security
# updates), while allowing Hyprland's dependencies to resolve from backports.
INSTALL_PACKAGES=()
for package in "${PACKAGES[@]}" "${GPU_PACKAGES[@]}" "${NOCTALIA_PACKAGES[@]}"; do
    candidate=$(LC_ALL=C apt-cache policy "$package" | awk '$1 == "Candidate:" { print $2; exit }')
    [[ -n "$candidate" && "$candidate" != '(none)' ]] || die "No APT candidate for $package. Check the configured repositories."
    INSTALL_PACKAGES+=("$package=$candidate")
done
BACKPORTS_REQUESTS=()
for package in "${BACKPORTS_PACKAGES[@]}"; do BACKPORTS_REQUESTS+=("$package/trixie-backports"); done
INSTALL_PACKAGES+=("${BACKPORTS_REQUESTS[@]}")
# Simulate the exact transaction before changing desktop packages or configs.
sudo apt-get --simulate -t trixie-backports install --no-install-recommends "${INSTALL_PACKAGES[@]}"
printf 'Installing the desktop and graphics packages...\n'
sudo apt-get install -y --no-install-recommends -t trixie-backports "${INSTALL_PACKAGES[@]}"

HYPRLAND_VERSION=$(dpkg-query -W -f='${Version}' hyprland)
dpkg --compare-versions "$HYPRLAND_VERSION" ge 0.55 || die "The Lua configuration requires Hyprland 0.55 or newer; installed: $HYPRLAND_VERSION"
for executable in Hyprland start-hyprland noctalia Thunar firefox-esr alacritty zsh nvim grim slurp wl-copy gio; do
    command -v "$executable" >/dev/null || die "The required program $executable is missing after package installation."
done

printf 'Configuring graphics...\n'
mkdir -p -- "$CONFIG_DIR/debian-deploy"
printf '%s\n' '-- Generated by deploy.sh; select hardware in vars.sh.' > "$WORK_DIR/graphics.lua"
if [[ "$GPU_DRIVER" == nvidia ]]; then
    cat >> "$WORK_DIR/graphics.lua" <<'EOF'
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
EOF
    printf '%s\n' 'options nvidia_drm modeset=1 fbdev=1' > "$WORK_DIR/nvidia.conf"
    sudo install -m 644 "$WORK_DIR/nvidia.conf" /etc/modprobe.d/debian-deploy-nvidia.conf
    sudo update-initramfs -u -k all
elif [[ -e /etc/modprobe.d/debian-deploy-nvidia.conf ]]; then
    sudo rm /etc/modprobe.d/debian-deploy-nvidia.conf
    sudo update-initramfs -u -k all
fi
if [[ "$GPU_DRIVER" == vm ]]; then
    if [[ "$VM_SOFTWARE_RENDERING" == true ]]; then
        printf '%s\n' 'hl.env("LIBGL_ALWAYS_SOFTWARE", "true")' >> "$WORK_DIR/graphics.lua"
    fi
    printf '%s\n' 'return { vm = true, monitor_scale = 1 }' >> "$WORK_DIR/graphics.lua"
else
    printf '%s\n' 'return {}' >> "$WORK_DIR/graphics.lua"
fi
install -m 644 "$WORK_DIR/graphics.lua" "$CONFIG_DIR/debian-deploy/graphics.lua"

printf 'Linking dotfiles and installing user resources...\n'
for config in alacritty zsh gtk-3.0 nvim hypr; do
    link_config "$REPO_DIR/dotfiles/$config" "$CONFIG_DIR/$config"
done
link_config "$REPO_DIR/dotfiles/zsh/zshrc" "$HOME/.zshrc"
bash "$REPO_DIR/dotfiles/zsh/getplugins.sh"
bash "$REPO_DIR/dotfiles/fonts/getfonts.sh"
xdg-user-dirs-update

# Seed the graphical authentication agent for a new Noctalia installation.
mkdir -p -- "$CONFIG_DIR/noctalia"
if [[ ! -e "$CONFIG_DIR/noctalia/config.toml" ]]; then
    printf '%s\n' '[shell]' 'polkit_agent = true' > "$CONFIG_DIR/noctalia/config.toml"
fi

# Hyprland's portal handles screen sharing; GTK supplies the file chooser.
mkdir -p -- "$CONFIG_DIR/xdg-desktop-portal"
cat > "$WORK_DIR/hyprland-portals.conf" <<'EOF'
[preferred]
default=hyprland;gtk
org.freedesktop.impl.portal.FileChooser=gtk
EOF
PORTAL_CONFIG="$CONFIG_DIR/xdg-desktop-portal/hyprland-portals.conf"
if ! cmp -s "$WORK_DIR/hyprland-portals.conf" "$PORTAL_CONFIG"; then
    if [[ -e "$PORTAL_CONFIG" || -L "$PORTAL_CONFIG" ]]; then
        mkdir -p -- "$BACKUP_DIR"
        mv -- "$PORTAL_CONFIG" "$BACKUP_DIR/hyprland-portals.conf"
    fi
    install -m 644 "$WORK_DIR/hyprland-portals.conf" "$PORTAL_CONFIG"
fi
Hyprland --verify-config --config "$CONFIG_DIR/hypr/hyprland.lua"

printf 'Enabling services for the next boot...\n'
# Let NetworkManager import/manage the Debian installer's ifupdown interfaces.
# Disable the legacy boot service to avoid two network managers on those links.
cat > "$WORK_DIR/networkmanager.conf" <<'EOF'
[ifupdown]
managed=true
EOF
sudo install -D -m 644 "$WORK_DIR/networkmanager.conf" /etc/NetworkManager/conf.d/10-debian-deploy.conf
if [[ -e /usr/lib/systemd/system/networking.service || -e /lib/systemd/system/networking.service ]]; then
    sudo systemctl disable networking.service
fi
sudo systemctl enable "${SERVICES[@]}" "${GUEST_SERVICES[@]}"
systemctl --user --no-reload enable pipewire.socket pipewire-pulse.socket wireplumber.service

if [[ "$(getent passwd "$(id -un)" | cut -d: -f7)" != "$USERSHELL" ]]; then
    sudo chsh -s "$USERSHELL" "$(id -un)"
fi
printf '\nSetup complete. Reboot, log in on a TTY, then run start-hyprland.\n'
[[ ! -d "$BACKUP_DIR" ]] || printf 'Previous dotfiles were saved in %s\n' "$BACKUP_DIR"

#!/usr/bin/env bash
# Arch + Sway rice. Run as your normal user; sudo is only used by pacman.
set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
target_home="$HOME"
dry_run=false
skip_packages=false
build_wallpaper=false
assume_yes=false
alternate_target=false

usage() {
    cat <<'HELP'
Usage: bash install.sh [OPTIONS]
  -y, --yes                Skip the installer confirmation (pacman still prompts)
  --no-packages            Deploy configs without installing packages
  --build-wallpaper-tools  Build pinned wpaperd + wpaperctl for wallpaper rotation
  --dry-run                Show the plan without writing files or running commands
  --target-home DIR        Deploy to a test home; requires --no-packages
  -h, --help               Show help
HELP
}
while (($#)); do
    case "$1" in
        -y|--yes) assume_yes=true ;;
        --no-packages) skip_packages=true ;;
        --build-wallpaper-tools) build_wallpaper=true ;;
        --dry-run) dry_run=true ;;
        --target-home)
            [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { printf 'Missing target directory.\n' >&2; exit 2; }
            target_home="$2"; alternate_target=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
[[ "$target_home" == /* && "$target_home" != / ]] || { printf 'Target home must be an absolute directory other than /.\n' >&2; exit 2; }
if "$alternate_target" && { ! "$skip_packages" || "$build_wallpaper"; }; then
    printf 'Test targets require --no-packages and do not support builds.\n' >&2; exit 2
fi
if ((EUID == 0)) && ! "$dry_run" && ! "$alternate_target"; then
    printf 'Run as a regular user, not with sudo.\n' >&2; exit 1
fi
if ! "$skip_packages" && [[ ! -f /etc/arch-release ]]; then
    printf 'Package installation requires Arch Linux. Use --no-packages for config-only deployment.\n' >&2; exit 1
fi

packages=(sway swaybg swaylock foot rofi waybar swaync wl-clipboard wl-clip-persist
          grim slurp jq libnotify playerctl brightnessctl libpulse pamixer
          thunar btop duf nm-connection-editor inter-font ttf-firacode-nerd
          ttf-jetbrains-mono-nerd xdg-desktop-portal-wlr xdg-desktop-portal-gtk)
if "$build_wallpaper"; then
    packages+=(base-devel git rust pkgconf mesa wayland libxkbcommon)
fi
configs=(sway foot rofi waybar wpaperd)
scripts=(screenshot toggle-waybar wallpaper last-updated)
config_files=(xdg-desktop-portal/sway-portals.conf)
for item in "${configs[@]}"; do
    [[ -d "$repo_dir/.config/$item" ]] || { printf 'Missing config: %s\n' "$item" >&2; exit 1; }
done
for item in "${scripts[@]}"; do
    [[ -f "$repo_dir/scripts/$item" ]] || { printf 'Missing script: %s\n' "$item" >&2; exit 1; }
done
for item in "${config_files[@]}"; do
    [[ -f "$repo_dir/.config/$item" ]] || { printf 'Missing config file: %s\n' "$item" >&2; exit 1; }
done
printf 'Arch + Sway rice\nTarget: %s\n' "$target_home"
printf 'Configs: %s\n' "${configs[*]}"
printf 'Scripts: %s\n' "${scripts[*]}"
printf 'Session config: %s\n' "${config_files[*]}"
if ! "$skip_packages"; then printf 'Packages (pacman -Syu --needed): %s\n' "${packages[*]}"; fi
if "$build_wallpaper"; then printf 'Build wpaperd at revision 483225a9c6ad4f9bbf9104f958eafee9c47d4612.\n'; fi
printf 'Existing configs will be moved into a unique backup under .local/state/sway-rice/backups.\n'
if "$dry_run"; then printf 'Dry run complete; no changes made.\n'; exit 0; fi
if ! "$assume_yes"; then
    read -r -p 'Continue? [y/N] ' answer
    case "$answer" in y|Y|yes|YES) ;; *) printf 'Cancelled.\n'; exit 0 ;; esac
fi
if ! "$skip_packages"; then
    command -v sudo >/dev/null || { printf 'sudo is required for packages.\n' >&2; exit 1; }
    # A full upgrade avoids an unsupported partial upgrade on Arch.
    sudo pacman -Syu --needed "${packages[@]}"
fi

# Build before touching configs, so build failures leave the desktop untouched.
wallpaper_build_dir=''
if "$build_wallpaper"; then
    for command in git cargo cc pkg-config; do
        command -v "$command" >/dev/null || { printf 'Missing build dependency: %s\n' "$command" >&2; exit 1; }
    done
    cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/sway-rice"
    mkdir -p -- "$cache_dir"
    wallpaper_build_dir="$(mktemp -d "$cache_dir/wpaperd.XXXXXX")"
    git -C "$wallpaper_build_dir" init -q
    git -C "$wallpaper_build_dir" remote add origin https://github.com/danyspin97/wpaperd.git
    git -C "$wallpaper_build_dir" fetch --depth 1 origin 483225a9c6ad4f9bbf9104f958eafee9c47d4612
    git -C "$wallpaper_build_dir" checkout --detach FETCH_HEAD
    (cd -- "$wallpaper_build_dir" && cargo build --release --locked -p wpaperd -p wpaperctl)
fi

backup_root="$target_home/.local/state/sway-rice/backups"
mkdir -p -- "$backup_root"
backup_dir="$(mktemp -d "$backup_root/$(date +%Y%m%d-%H%M%S).XXXXXX")"
# Retain the directory hierarchy, including symlinks, in every backup.
backup_existing() {
    local relative="$1" destination="$target_home/$1"
    if [[ -e "$destination" || -L "$destination" ]]; then
        mkdir -p -- "$backup_dir/$(dirname -- "$relative")"
        mv -- "$destination" "$backup_dir/$relative"
        printf 'Backed up %s\n' "$relative"
    fi
}
for item in "${configs[@]}"; do
    backup_existing ".config/$item"
    mkdir -p -- "$target_home/.config"
    cp -R -- "$repo_dir/.config/$item" "$target_home/.config/$item"
done
for item in "${config_files[@]}"; do
    backup_existing ".config/$item"
    mkdir -p -- "$target_home/.config/$(dirname -- "$item")"
    cp -- "$repo_dir/.config/$item" "$target_home/.config/$item"
done
for item in "${scripts[@]}"; do
    backup_existing ".local/bin/sway-rice/$item"
    mkdir -p -- "$target_home/.local/bin/sway-rice"
    install -m 755 -- "$repo_dir/scripts/$item" "$target_home/.local/bin/sway-rice/$item"
done
if "$build_wallpaper"; then
    for item in wpaperd wpaperctl; do
        backup_existing ".local/bin/sway-rice/tools/$item"
        mkdir -p -- "$target_home/.local/bin/sway-rice/tools"
        install -m 755 -- "$wallpaper_build_dir/target/release/$item" "$target_home/.local/bin/sway-rice/tools/$item"
    done
fi
mkdir -p -- "$target_home/Pictures/Wallpapers" "$target_home/Pictures/Screenshots"
printf '\nInstalled. Backup: %s\n' "$backup_dir"
printf 'Add wallpapers to ~/Pictures/Wallpapers, then start a new Sway session.\n'
printf 'Alt+Enter: terminal | Alt+p: launcher | Alt+i: bar | Alt+Shift+l: lock\n'
printf 'No services, login shell, display manager, or running desktop were changed.\n'

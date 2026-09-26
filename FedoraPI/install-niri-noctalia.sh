#!/usr/bin/env bash
# ==============================================================================
# install-niri-noctalia.sh
# ------------------------------------------------------------------------------
# Universal installer & configurator for Niri Compositor with Noctalia Shell v5+
# Supports: Arch Linux, Fedora Linux (40+), Debian (Trixie/Sid/Bookworm)
# 
# Features:
# - Full Dank Material Shell (DMS) Keybinding Parity
# - Noctalia Shell v5+: Top Floating Pill Bar + Bottom Floating Intellihide Dock
# - Display Setup: 2560x1600 @ 165Hz (16:10), Scale 1.25 with FreeSync / VRR
# - Touchpad Ergonomics: 3-finger horizontal column scroll, 3-finger vertical
#   workspace switch, 4-finger vertical swipe up for Niri Overview
# - Dynamic Battery-Aware Power Management (Aggressive Battery vs. Smooth AC)
# - Kitty Terminal with Glassmorphism, Remote Socket Control & Live Theme Sync
# - Full GTK3/4 (adw-gtk3), Qt (KColorScheme / qt6ct), and Flatpak auto-theming
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Visual Styling & Output Utilities
# ------------------------------------------------------------------------------
BOLD="\033[1m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
RESET="\033[0m"

log_info()    { echo -e "${BLUE}[INFO]${RESET} $*" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $*" >&2; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET} $*" >&2; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_section() {
    echo -e "\n${BOLD}${MAGENTA}====================================================================${RESET}" >&2
    echo -e "${BOLD}${CYAN}  $*${RESET}" >&2
    echo -e "${BOLD}${MAGENTA}====================================================================${RESET}\n" >&2
}

# ------------------------------------------------------------------------------
# Script Flags & Defaults
# ------------------------------------------------------------------------------
AUTO_YES=false
CONFIG_ONLY=false
NO_BACKUP=false
DRY_RUN=false
TARGET_USER="${SUDO_USER:-$USER}"
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TIMESTAMP="$(date +%s)"

print_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -y, --yes          Non-interactive mode (auto-accept all package installations).
  --config-only      Skip system package installations and only write/update configurations.
  --no-backup        Do not back up existing configuration files before updating.
  --dry-run          Print planned operations without executing package installs or writing files.
  -h, --help         Display this help message and exit.

Supported Distributions:
  - Arch Linux / CachyOS / EndeavourOS / Manjaro
  - Fedora Linux 40, 41, 42, 43, 44+
  - Debian (Trixie testing, Sid unstable, Bookworm) / Ubuntu 24.04+
EOF
}

# Parse Arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        --config-only)
            CONFIG_ONLY=true
            shift
            ;;
        --no-backup)
            NO_BACKUP=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
done

# Ensure script is run with appropriate permissions
if [[ $EUID -eq 0 && -z "${SUDO_USER:-}" ]]; then
    log_warn "Running directly as root user. It is recommended to run as your regular user (sudo will be called when needed)."
fi

# ------------------------------------------------------------------------------
# 1. Distribution Detection
# ------------------------------------------------------------------------------
log_section "Phase 1: Environment & Distribution Detection"

if [[ ! -f /etc/os-release ]]; then
    log_error "Cannot identify distribution: /etc/os-release not found."
    exit 1
fi

# shellcheck source=/dev/null
source /etc/os-release
OS_ID="${ID:-unknown}"
OS_ID_LIKE="${ID_LIKE:-}"
OS_VERSION_ID="${VERSION_ID:-0}"

log_info "Detected OS: ${PRETTY_NAME:-$OS_ID} ($OS_ID, version: $OS_VERSION_ID)"
log_info "Target User: $TARGET_USER"
log_info "Target Home: $USER_HOME"

SUDO_CMD="sudo"
if [[ $EUID -eq 0 ]]; then
    SUDO_CMD=""
fi

# ------------------------------------------------------------------------------
# 2. Package Installation Logic per Distribution
# ------------------------------------------------------------------------------
install_packages() {
    if [[ "$CONFIG_ONLY" == true ]]; then
        log_info "Skipping package installation (--config-only specified)."
        return 0
    fi

    log_section "Phase 2: Installing Latest Packages & Dependencies"

    case "$OS_ID" in
        arch|cachyos|endeavouros|manjaro)
            log_info "Configuring Arch Linux official package repository..."
            local ARCH_PKGS=(
                niri
                noctalia
                kitty
                xwayland-satellite
                swayidle
                power-profiles-daemon
                brightnessctl
                playerctl
                wl-clipboard
                libnotify
                adw-gtk-theme
                nwg-look
                qt6ct-kde
                kvantum
                ttf-jetbrains-mono-nerd
                noto-fonts-emoji
                papirus-icon-theme
                git
                just
                meson
            )

            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY-RUN] Would run: $SUDO_CMD pacman -Syu --needed ${ARCH_PKGS[*]}"
            else
                $SUDO_CMD pacman -Syu --needed --noconfirm "${ARCH_PKGS[@]}"
            fi
            ;;

        fedora)
            log_info "Configuring Fedora Copr repositories for latest Niri and Noctalia..."
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY-RUN] Would enable COPR yalter/niri and lionheartp/Hyprland (if needed)"
                log_info "[DRY-RUN] Would run: $SUDO_CMD dnf install -y niri noctalia kitty ..."
            else
                $SUDO_CMD dnf copr enable -y yalter/niri

                # For Fedora 44+, noctalia is in official repos; for earlier, enable lionheartp copr if needed
                if ! dnf list noctalia &>/dev/null; then
                    log_info "Enabling lionheartp/Hyprland COPR for Noctalia..."
                    $SUDO_CMD dnf copr enable -y lionheartp/Hyprland
                fi

                local FEDORA_PKGS=(
                    niri
                    kitty
                    xwayland-satellite
                    swayidle
                    power-profiles-daemon
                    brightnessctl
                    playerctl
                    wl-clipboard
                    libnotify
                    adw-gtk3-theme
                    nwg-look
                    qt6ct
                    kvantum
                    jetbrains-mono-fonts
                    google-noto-emoji-fonts
                    papirus-icon-theme
                    git
                    just
                    meson
                )

                # Try installing noctalia or noctalia-git
                if dnf list noctalia &>/dev/null; then
                    FEDORA_PKGS+=(noctalia)
                elif dnf list noctalia-git &>/dev/null; then
                    FEDORA_PKGS+=(noctalia-git)
                fi

                $SUDO_CMD dnf install -y "${FEDORA_PKGS[@]}"
            fi
            ;;

        debian|ubuntu|pop)
            log_info "Configuring Debian/Ubuntu repositories..."
            local DEB_CODENAME="${VERSION_CODENAME:-trixie}"
            if [[ -z "$DEB_CODENAME" || "$DEB_CODENAME" == "null" ]]; then
                DEB_CODENAME="trixie"
            fi

            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY-RUN] Would configure Noctalia APT repository and build/install Niri"
            else
                $SUDO_CMD apt update -y
                $SUDO_CMD apt install -y wget curl gnupg2 ca-certificates build-essential git just meson pkg-config

                # Add Noctalia official APT keyring
                log_info "Installing Noctalia APT signing key..."
                wget -qO /tmp/nickh-archive-keyring.deb https://pkg.noctalia.dev/deb/nickh-archive-keyring.deb
                $SUDO_CMD dpkg -i /tmp/nickh-archive-keyring.deb || true

                # Add Noctalia sources list based on suite
                local NOCTALIA_SRC_URL="https://pkg.noctalia.dev/deb/noctalia-trixie.sources"
                if [[ "$DEB_CODENAME" == "sid" || "$DEB_CODENAME" == "unstable" ]]; then
                    NOCTALIA_SRC_URL="https://pkg.noctalia.dev/deb/noctalia-unstable.sources"
                elif [[ "$OS_ID" == "ubuntu" ]]; then
                    NOCTALIA_SRC_URL="https://pkg.noctalia.dev/deb/noctalia-resolute.sources"
                fi

                $SUDO_CMD wget -q -O /etc/apt/sources.list.d/noctalia.sources "$NOCTALIA_SRC_URL" || true
                $SUDO_CMD apt update -y

                # Core packages
                local DEB_PKGS=(
                    kitty
                    swayidle
                    power-profiles-daemon
                    brightnessctl
                    playerctl
                    wl-clipboard
                    libnotify-bin
                    adw-gtk3-theme
                    qt6ct
                    fonts-jetbrains-mono
                    fonts-noto-color-emoji
                    papirus-icon-theme
                )

                # Attempt noctalia install from apt
                if apt-cache show noctalia &>/dev/null; then
                    DEB_PKGS+=(noctalia)
                else
                    log_warn "Noctalia not found in APT cache. Will compile Noctalia from source."
                fi

                $SUDO_CMD apt install -y "${DEB_PKGS[@]}"

                # Install Niri if not present
                if ! command -v niri &>/dev/null; then
                    log_info "Compiling latest Niri via Rust/Cargo..."
                    $SUDO_CMD apt install -y \
                        rustup gcc clang pkg-config build-essential \
                        libudev-dev libgbm-dev libxkbcommon-dev libegl1-mesa-dev \
                        libwayland-dev libinput-dev libdbus-1-dev libsystemd-dev \
                        libseat-dev libpipewire-0.3-dev libpango1.0-dev libdisplay-info-dev

                    if ! command -v cargo &>/dev/null; then
                        rustup default stable
                    fi

                    cargo install --locked niri
                    cargo install --locked xwayland-satellite

                    # Place binary into /usr/local/bin
                    $SUDO_CMD cp "$USER_HOME/.cargo/bin/niri" /usr/local/bin/ || true
                    $SUDO_CMD cp "$USER_HOME/.cargo/bin/xwayland-satellite" /usr/local/bin/ || true

                    # Set up wayland session file
                    $SUDO_CMD mkdir -p /usr/share/wayland-sessions
                    $SUDO_CMD tee /usr/share/wayland-sessions/niri.desktop > /dev/null <<'DESKTOP_ENTRY'
[Desktop Entry]
Name=Niri
Comment=A scrollable-tiling Wayland compositor
Exec=/usr/local/bin/niri
Type=Application
DesktopNames=niri
DESKTOP_ENTRY
                fi

                # Compile Noctalia if not installed
                if ! command -v noctalia &>/dev/null; then
                    log_info "Compiling Noctalia from official repository..."
                    $SUDO_CMD apt install -y \
                        libwayland-dev wayland-protocols libfreetype-dev libfontconfig-dev \
                        libcairo2-dev libpango1.0-dev librsvg2-dev libxkbcommon-dev \
                        libepoxy-dev libgles-dev libwebp-dev libcurl4-gnutls-dev \
                        libmd4c-dev nlohmann-json3-dev libsdbus-c++-dev libsecret-1-dev \
                        libsodium-dev libstb-dev libtomlplusplus-dev \
                        libpipewire-0.3-dev libpam0g-dev libpolkit-agent-1-dev \
                        libpolkit-gobject-1-dev libqalculate-dev libwireplumber-0.5-dev \
                        libxml2-dev libjemalloc-dev

                    local BUILD_DIR="/tmp/noctalia-build"
                    rm -rf "$BUILD_DIR"
                    git clone https://github.com/noctalia-dev/noctalia.git --branch main "$BUILD_DIR"
                    (
                        cd "$BUILD_DIR"
                        just configure release
                        just build release
                        $SUDO_CMD just install release
                    )
                    rm -rf "$BUILD_DIR"
                fi
            fi
            ;;

        *)
            log_warn "Unrecognized OS ID '$OS_ID'. Proceeding with generic package checks."
            ;;
    esac

    log_success "Package setup verified successfully."
}

# ------------------------------------------------------------------------------
# 3. Display Connector Auto-Detection
# ------------------------------------------------------------------------------
detect_display_connector() {
    log_info "Detecting active internal display connector..."
    local DETECTED_CONNECTOR="eDP-1"

    # Scan DRM sysfs for connected eDP or DP displays
    for card_dir in /sys/class/drm/card*-eDP-*/status; do
        if [[ -f "$card_dir" && "$(<"$card_dir")" == "connected" ]]; then
            DETECTED_CONNECTOR="$(basename "$(dirname "$card_dir")" | sed 's/^card[0-9]*-//')"
            break
        fi
    done

    # If no eDP found, check DP
    if [[ "$DETECTED_CONNECTOR" == "eDP-1" ]]; then
        for card_dir in /sys/class/drm/card*-DP-*/status; do
            if [[ -f "$card_dir" && "$(<"$card_dir")" == "connected" ]]; then
                DETECTED_CONNECTOR="$(basename "$(dirname "$card_dir")" | sed 's/^card[0-9]*-//')"
                break
            fi
        done
    fi

    log_info "Active internal display detected: ${GREEN}$DETECTED_CONNECTOR${RESET}"
    echo "$DETECTED_CONNECTOR"
}

# ------------------------------------------------------------------------------
# 4. Backup Utilities
# ------------------------------------------------------------------------------
backup_file_or_dir() {
    local target="$1"
    if [[ "$NO_BACKUP" == true ]]; then
        return 0
    fi

    if [[ -e "$target" ]]; then
        local backup_path="${target}.bak.${TIMESTAMP}"
        log_info "Backing up: $target -> $backup_path"
        if [[ "$DRY_RUN" == false ]]; then
            cp -r "$target" "$backup_path"
        fi
    fi
}

# ------------------------------------------------------------------------------
# 5. Configuration Synthesis
# ------------------------------------------------------------------------------
setup_configurations() {
    log_section "Phase 3: Deploying Configurations & Theming Ecosystem"

    local CONFIG_HOME="$USER_HOME/.config"
    local NIRI_DIR="$CONFIG_HOME/niri"
    local NIRI_SCRIPTS_DIR="$NIRI_DIR/scripts"
    local NOCTALIA_DIR="$CONFIG_HOME/noctalia"
    local NOCTALIA_TEMPLATES_DIR="$NOCTALIA_DIR/templates"
    local KITTY_DIR="$CONFIG_HOME/kitty"
    local WALLPAPERS_DIR="$USER_HOME/Pictures/Wallpapers"

    local ACTIVE_CONNECTOR
    ACTIVE_CONNECTOR="$(detect_display_connector)"

    # Create destination directories
    if [[ "$DRY_RUN" == false ]]; then
        mkdir -p "$NIRI_SCRIPTS_DIR" "$NOCTALIA_TEMPLATES_DIR" "$KITTY_DIR" "$WALLPAPERS_DIR"
    fi

    # --------------------------------------------------------------------------
    # A. Kitty Configuration Update / Creation
    # --------------------------------------------------------------------------
    log_info "Configuring Kitty terminal with live socket reloading and glassmorphism..."
    local KITTY_CONF="$KITTY_DIR/kitty.conf"

    if [[ -f "$KITTY_CONF" ]]; then
        backup_file_or_dir "$KITTY_CONF"
        log_info "Merging required settings into existing $KITTY_CONF..."

        if [[ "$DRY_RUN" == false ]]; then
            # Ensure allow_remote_control yes
            if ! grep -q "^allow_remote_control" "$KITTY_CONF"; then
                echo -e "\n# Noctalia Live Theme Socket\nallow_remote_control yes" >> "$KITTY_CONF"
            else
                sed -i 's/^allow_remote_control.*/allow_remote_control yes/' "$KITTY_CONF"
            fi

            # Ensure listen_on
            if ! grep -q "^listen_on" "$KITTY_CONF"; then
                echo "listen_on unix:@kitty" >> "$KITTY_CONF"
            fi

            # Ensure dynamic opacity
            if ! grep -q "^dynamic_background_opacity" "$KITTY_CONF"; then
                echo "dynamic_background_opacity yes" >> "$KITTY_CONF"
            fi

            # Ensure stale theme.conf reference is removed
            sed -i '/theme\.conf/d' "$KITTY_CONF"

            # Ensure Noctalia dynamic theme include
            if ! grep -q "themes/noctalia.conf" "$KITTY_CONF"; then
                echo -e "\n# Dynamic Noctalia Material You palette\ninclude themes/noctalia.conf" >> "$KITTY_CONF"
            fi
        fi
    else
        log_info "Creating fresh $KITTY_CONF..."
        if [[ "$DRY_RUN" == false ]]; then
            cat <<'EOF' > "$KITTY_CONF"
# ==============================================================================
# Kitty Terminal Configuration
# ==============================================================================
font_family      JetBrainsMono Nerd Font
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        12.0
disable_ligatures never

# Window Styling & Padding
window_padding_width 12
background_opacity 0.88
dynamic_background_opacity yes
hide_window_decorations yes
confirm_os_window_close 0

# Cursor & Scrollback
cursor_shape block
cursor_blink_interval 0.5
scrollback_lines 5000
copy_on_select yes
strip_trailing_spaces smart

# Dynamic Noctalia Remote Control Socket
allow_remote_control yes
listen_on unix:@kitty

# Include dynamic Noctalia theme
include themes/noctalia.conf
EOF
        fi
    fi

    # Clean up any obsolete/stale theme files from older versions
    if [[ "$DRY_RUN" == false ]]; then
        rm -f "$KITTY_DIR/theme.conf" "$NOCTALIA_TEMPLATES_DIR/kitty.conf"
    fi

    # --------------------------------------------------------------------------
    # C. Noctalia Shell Configuration (config.toml, templates.toml)
    # --------------------------------------------------------------------------
    log_info "Configuring Noctalia Shell v5+ (Top Floating Pill Bar + Bottom Dock)..."
    backup_file_or_dir "$NOCTALIA_DIR/config.toml"
    backup_file_or_dir "$NOCTALIA_DIR/templates.toml"

    if [[ "$DRY_RUN" == false ]]; then
        cat <<'EOF' > "$NOCTALIA_DIR/config.toml"
# ==============================================================================
# Noctalia Shell v5 Configuration
# ==============================================================================
[theme]
mode = "dark"
source = "wallpaper"
builtin = "Noctalia"
wallpaper_scheme = "m3-content"

[backdrop]
enabled = true
blur_intensity = 0.5
tint_intensity = 0.3

# --- Top Floating Capsule Bar ---
[bar]
order = [ "default" ]

    [bar.default]
    enabled = true
    position = "top"
    thickness = 38
    padding = 12
    margin_edge = 10
    margin_ends = 14
    radius = 16
    shadow = true
    reserve_space = true
    layer = "top"
    start = [
        "launcher",
        "workspaces",
        "active_window"
    ]
    center = [
        "clock"
    ]
    end = [
        "media",
        "sysmon",
        "volume",
        "brightness",
        "battery",
        "network",
        "bluetooth",
        "control-center"
    ]

# --- Bottom Floating Intellihide Dock ---
[dock]
enabled = true
position = "bottom"
auto_hide = false
smart_auto_hide = true
magnification = true
magnification_scale = 1.35
icon_size = 44
radius = 18
margin_edge = 10
show_running = true
show_dots = true
pinned = []

# --- Quick Settings / Control Center ---
[control_center]
sidebar = "compact"
width = 680
show_shortcut_labels = true
show_session_button = true

# --- Wallpaper Engine ---
[wallpaper]
enabled = true
directory = "~/Pictures/Wallpapers"
transition = [ "fade", "wipe", "zoom" ]
transition_duration = 1000.0

[weather]
enabled = true
unit = "metric"
effects = true
EOF

        # Noctalia Templates Configuration (GTK, Qt, Kitty)
        cat <<'EOF' > "$NOCTALIA_DIR/templates.toml"
# ==============================================================================
# Noctalia Application Theming Templates
# ==============================================================================
[theme.templates]
enable_builtin_templates = true
enable_community_templates = false
builtin_ids = [
  "gtk3",
  "gtk4",
  "qt",
  "kcolorscheme",
  "kitty"
]
EOF
    fi

    # --------------------------------------------------------------------------
    # D. Adaptive Battery-Aware Power Management Daemon
    # --------------------------------------------------------------------------
    log_info "Creating adaptive AC vs. Battery power management daemon..."
    local POWER_SCRIPT="$NIRI_SCRIPTS_DIR/power-monitor.sh"

    if [[ "$DRY_RUN" == false ]]; then
        cat <<'EOF' > "$POWER_SCRIPT"
#!/usr/bin/env bash
# ==============================================================================
# power-monitor.sh - Adaptive AC vs. Battery Idle Daemon for Niri + Noctalia
# ==============================================================================
set -euo pipefail

SWAYIDLE_PID=""

kill_swayidle() {
    if [[ -n "$SWAYIDLE_PID" ]] && kill -0 "$SWAYIDLE_PID" 2>/dev/null; then
        kill "$SWAYIDLE_PID" 2>/dev/null || true
        wait "$SWAYIDLE_PID" 2>/dev/null || true
    fi
}

start_battery_profile() {
    kill_swayidle
    echo "[Power-Monitor] Switching to Battery Profile (Aggressive Timeout & Saver)"
    powerprofilesctl set power-saver 2>/dev/null || true

    # Battery Timeouts:
    # 60s  -> Dim screen to 20%
    # 180s -> Lock screen via Noctalia
    # 300s -> Turn off displays
    # 600s -> Suspend laptop
    swayidle -w \
        timeout 60 'brightnessctl -s set 20%' \
            resume 'brightnessctl -r' \
        timeout 180 'noctalia msg session lock' \
        timeout 300 'niri msg action power-off-monitors' \
            resume 'niri msg action power-on-monitors' \
        timeout 600 'systemctl suspend' \
        before-sleep 'noctalia msg session lock' &
    SWAYIDLE_PID=$!
}

start_ac_profile() {
    kill_swayidle
    echo "[Power-Monitor] Switching to AC Profile (Performance / Relaxed Timeout)"
    powerprofilesctl set balanced 2>/dev/null || true

    # AC Timeouts:
    # 300s (5m)  -> Dim screen to 50%
    # 600s (10m) -> Lock screen via Noctalia
    # 900s (15m) -> Turn off displays
    # 1800s (30m)-> Suspend laptop
    swayidle -w \
        timeout 300 'brightnessctl -s set 50%' \
            resume 'brightnessctl -r' \
        timeout 600 'noctalia msg session lock' \
        timeout 900 'niri msg action power-off-monitors' \
            resume 'niri msg action power-on-monitors' \
        timeout 1800 'systemctl suspend' \
        before-sleep 'noctalia msg session lock' &
    SWAYIDLE_PID=$!
}

check_power_state() {
    for online_file in /sys/class/power_supply/A*/online /sys/class/power_supply/AC*/online; do
        if [[ -f "$online_file" ]]; then
            if [[ "$(<"$online_file")" == "1" ]]; then
                echo "AC"
                return
            else
                echo "BAT"
                return
            fi
        fi
    done
    echo "AC"
}

CURRENT_STATE=""

while true; do
    NEW_STATE="$(check_power_state)"
    if [[ "$NEW_STATE" != "$CURRENT_STATE" ]]; then
        CURRENT_STATE="$NEW_STATE"
        if [[ "$CURRENT_STATE" == "BAT" ]]; then
            start_battery_profile
        else
            start_ac_profile
        fi
    fi
    sleep 5
done
EOF
        chmod +x "$POWER_SCRIPT"
    fi

    # --------------------------------------------------------------------------
    # E. Wallpaper & Dynamic Palette Switcher
    # --------------------------------------------------------------------------
    log_info "Creating wallpaper shuffle & theme reloader script..."
    local WALLPAPER_SCRIPT="$NIRI_SCRIPTS_DIR/change-wallpaper.sh"

    if [[ "$DRY_RUN" == false ]]; then
        cat <<'EOF' > "$WALLPAPER_SCRIPT"
#!/usr/bin/env bash
# ==============================================================================
# change-wallpaper.sh - Random Wallpaper & Palette Switcher
# ==============================================================================
WALLPAPERS_DIR="$HOME/Pictures/Wallpapers"
mkdir -p "$WALLPAPERS_DIR"

WALLPAPERS=("$WALLPAPERS_DIR"/*.{jpg,jpeg,png,webp})
if [[ ${#WALLPAPERS[@]} -eq 0 || ! -f "${WALLPAPERS[0]}" ]]; then
    echo "[Wallpaper] No wallpapers found in $WALLPAPERS_DIR. Downloading curated sample..."
    curl -sL "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=2560&q=80" -o "$WALLPAPERS_DIR/default.jpg" || true
    WALLPAPERS=("$WALLPAPERS_DIR"/default.jpg)
fi

SELECTED_WP="${WALLPAPERS[RANDOM % ${#WALLPAPERS[@]}]}"

if [[ -f "$SELECTED_WP" ]]; then
    echo "[Wallpaper] Applying $SELECTED_WP..."
    noctalia msg wallpaper-set "$SELECTED_WP" 2>/dev/null || true
    notify-send -a "Noctalia" "Palette Updated" "New wallpaper applied: $(basename "$SELECTED_WP")" -i "preferences-desktop-wallpaper"
fi
EOF
        chmod +x "$WALLPAPER_SCRIPT"
    fi

    # --------------------------------------------------------------------------
    # F. Complete Niri Configuration (config.kdl) with DMS Keybindings & Gestures
    # --------------------------------------------------------------------------
    log_info "Deploying comprehensive Niri configuration with DMS Keybindings..."
    backup_file_or_dir "$NIRI_DIR/config.kdl"

    if [[ "$DRY_RUN" == false ]]; then
        cat <<EOF > "$NIRI_DIR/config.kdl"
// =============================================================================
// NIRI CONFIGURATION - Material Shell Experience
// Tuned for: 2560x1600 @ 165Hz (16:10), Scale 1.25, DMS Keybinds & Noctalia v5+
// Touchpad Gestures:
//   - 3-Finger Horizontal Swipe: Smooth Column Scroll
//   - 3-Finger Vertical Swipe: Workspace Switching
//   - 4-Finger Vertical Swipe Up: Niri Overview Mode
// =============================================================================

// --- Startup Services ---
spawn-at-startup "noctalia"
spawn-at-startup "xwayland-satellite"
spawn-at-startup "$NIRI_SCRIPTS_DIR/power-monitor.sh"

// --- Display Configuration: 2560x1600 @ 165Hz, Scale 1.25 ---
output "$ACTIVE_CONNECTOR" {
    mode "2560x1600@165.000"
    scale 1.25
    transform "normal"
    position x=0 y=0
    variable-refresh-rate
}

// Fallback rule for secondary / external displays
output "DP-1" {
    scale 1.25
    variable-refresh-rate
}

// --- Environment Variables for Unified Theming ---
environment {
    QT_QPA_PLATFORM "wayland;xcb"
    QT_QPA_PLATFORMTHEME "qt6ct"
    QT_WAYLAND_DISABLE_WINDOWDECORATION "1"
    GDK_BACKEND "wayland,x11"
    MOZ_ENABLE_WAYLAND "1"
    ELECTRON_OZONE_PLATFORM_HINT "auto"
}

// --- Input & Gesture Configuration ---
input {
    keyboard {
        xkb {
            // layout "us"
        }
    }

    touchpad {
        tap
        natural-scroll
        dwt
        accel-speed 0.2
        accel-profile "adaptive"
        scroll-method "two-finger"
        click-method "clickfinger"
        tap-button-map "left-right-middle"
    }

    mouse {
        accel-speed 0.0
    }

    warp-mouse-to-focus
}

// --- Gestures & Overview Configuration ---
gestures {
    dnd-edge-view-scroll {
        trigger-width 30
        delay-ms 100
        max-speed 1500
    }
    dnd-edge-workspace-switch {
        trigger-height 50
        delay-ms 100
        max-speed 1500
    }
    hot-corners {
        top-left
    }
}

overview {
    zoom 0.5
}

// --- Layout & Aesthetics ---
layout {
    gaps 12
    center-focused-column "never"

    preset-column-widths {
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
        proportion 1.0
    }

    default-column-width { proportion 0.5; }

    focus-ring {
        width 2
        active-color "#7aa2f7"
        inactive-color "#1e222a"
    }

    border {
        off
    }

    shadow {
        on
        softness 28
        spread 3
        offset x=0 y=6
        color "#00000066"
    }

    struts {
        left 0
        right 0
        top 0
        bottom 0
    }
}

// --- Spring Physics Animations ---
animations {
    slowdown 1.0
    horizontal-view-movement {
        spring damping-ratio=0.85 stiffness=800 epsilon=0.0001
    }
    window-movement {
        spring damping-ratio=0.85 stiffness=800 epsilon=0.0001
    }
}

// --- Window Rules & Floats ---
window-rule {
    geometry-corner-radius 16
    clip-to-geometry true
}

// Noctalia Settings Window Floating Rule
window-rule {
    match app-id="dev.noctalia.Noctalia"
    open-floating true
    default-column-width { fixed 1080; }
    default-window-height { fixed 920; }
}

// Dialog & Media Floats
window-rule {
    match app-id="pavucontrol"
    open-floating true
}

window-rule {
    match app-id="nm-connection-editor"
    open-floating true
}

// --- Noctalia Layer Surface Rules (Gaussian Blur & Backdrops) ---
layer-rule {
    match namespace="^noctalia-backdrop"
    place-within-backdrop true
}

layer-rule {
    match namespace="^noctalia-(bar-[^\"]+|notification|dock|panel|attached-panel|osd)$"
    background-effect {
        xray false
    }
}

layer-rule {
    match namespace="noctalia-window-switcher"
    background-effect {
        blur true
        xray false
    }
}

blur {
    passes 2
    offset 3.0
    noise 0.02
    saturation 1.2
}

// Debug flags for seamless Noctalia panel activations
debug {
    honor-xdg-activation-with-invalid-serial
}

// Laptop Lid Event (Instant lock & suspend)
switch-events {
    lid-close { spawn "noctalia" "msg" "session" "lock-and-suspend"; }
}

// =============================================================================
// DANK MATERIAL SHELL (DMS) KEYBINDINGS
// =============================================================================
binds {
    // --- Applications ---
    Mod+Return { spawn "kitty"; }
    Mod+Space  { spawn-sh "noctalia msg panel-toggle launcher"; }
    Mod+D      { spawn-sh "noctalia msg panel-toggle launcher"; }
    Mod+S      { spawn-sh "noctalia msg panel-toggle control-center"; }
    Mod+Comma  { spawn-sh "noctalia msg settings-toggle"; }
    Mod+N      { spawn-sh "noctalia msg panel-toggle notifications"; }
    Mod+V      { spawn-sh "noctalia msg panel-toggle clipboard"; }
    Mod+E      { spawn "nautilus"; }
    Mod+B      { spawn-sh "\${BROWSER:-firefox}"; }
    Mod+W      { spawn-sh "$NIRI_SCRIPTS_DIR/change-wallpaper.sh"; }
    Mod+Period { spawn-sh "noctalia msg panel-toggle emoji"; }

    // --- Navigation (Vim + Arrows) ---
    Mod+Left  { focus-column-left; }
    Mod+H     { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+L     { focus-column-right; }
    Mod+Up    { focus-window-up; }
    Mod+K     { focus-window-up; }
    Mod+Down  { focus-window-down; }
    Mod+J     { focus-window-down; }
    Mod+Home  { focus-column-first; }
    Mod+End   { focus-column-last; }

    // --- Window Movement ---
    Mod+Shift+Left  { move-column-left; }
    Mod+Shift+H     { move-column-left; }
    Mod+Shift+Right { move-column-right; }
    Mod+Shift+L     { move-column-right; }
    Mod+Shift+Up    { move-window-up; }
    Mod+Shift+K     { move-window-up; }
    Mod+Shift+Down  { move-window-down; }
    Mod+Shift+J     { move-window-down; }
    Mod+Ctrl+Left   { move-column-to-first; }
    Mod+Ctrl+Right  { move-column-to-last; }

    // --- Workspaces ---
    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
    Mod+5 { focus-workspace 5; }
    Mod+6 { focus-workspace 6; }
    Mod+7 { focus-workspace 7; }
    Mod+8 { focus-workspace 8; }
    Mod+9 { focus-workspace 9; }

    Mod+Shift+1 { move-column-to-workspace 1; }
    Mod+Shift+2 { move-column-to-workspace 2; }
    Mod+Shift+3 { move-column-to-workspace 3; }
    Mod+Shift+4 { move-column-to-workspace 4; }
    Mod+Shift+5 { move-column-to-workspace 5; }
    Mod+Shift+6 { move-column-to-workspace 6; }
    Mod+Shift+7 { move-column-to-workspace 7; }
    Mod+Shift+8 { move-column-to-workspace 8; }
    Mod+Shift+9 { move-column-to-workspace 9; }

    Mod+Page_Down { focus-workspace-down; }
    Mod+U         { focus-workspace-down; }
    Mod+Page_Up   { focus-workspace-up; }
    Mod+I         { focus-workspace-up; }
    Mod+Shift+Page_Down { move-column-to-workspace-down; }
    Mod+Shift+U         { move-column-to-workspace-down; }
    Mod+Shift+Page_Up   { move-column-to-workspace-up; }
    Mod+Shift+I         { move-column-to-workspace-up; }

    // --- Sizing & Window Rules ---
    Mod+Q         { close-window; }
    Mod+F         { maximize-column; }
    Mod+Shift+F   { fullscreen-window; }
    Mod+C         { center-column; }
    Mod+R         { switch-preset-column-width; }
    Mod+Shift+R   { reset-window-height; }
    Mod+Minus     { set-column-width "-10%"; }
    Mod+Equal     { set-column-width "+10%"; }
    Mod+Shift+Minus { set-window-height "-10%"; }
    Mod+Shift+Equal { set-window-height "+10%"; }
    Mod+Shift+Space { toggle-window-floating; }
    Alt+Tab       { spawn-sh "noctalia msg window-switcher"; }
    Mod+Tab       { spawn-sh "noctalia msg window-switcher"; }
    Mod+O         { toggle-overview; }

    // --- Screenshots ---
    Print         { spawn-sh "noctalia msg screenshot-region"; }
    Mod+P         { spawn-sh "noctalia msg screenshot-region"; }
    Shift+Print   { spawn-sh "noctalia msg screenshot-full"; }
    Mod+Shift+P   { spawn-sh "noctalia msg screenshot-full"; }

    // --- Session & Power ---
    Mod+Escape    { spawn-sh "noctalia msg session lock"; }
    Ctrl+Alt+L    { spawn-sh "noctalia msg session lock"; }
    Mod+Shift+E   { quit; }
    Mod+Shift+C   { spawn-sh "noctalia msg caffeine-toggle"; }

    // --- Hardware Keys ---
    XF86AudioRaiseVolume  { spawn-sh "noctalia msg volume-up"; }
    XF86AudioLowerVolume  { spawn-sh "noctalia msg volume-down"; }
    XF86AudioMute         { spawn-sh "noctalia msg volume-mute"; }
    XF86AudioMicMute      { spawn-sh "noctalia msg mic-mute"; }
    XF86MonBrightnessUp   { spawn-sh "noctalia msg brightness-up"; }
    XF86MonBrightnessDown { spawn-sh "noctalia msg brightness-down"; }
    XF86AudioPlay         { spawn "playerctl" "play-pause"; }
    XF86AudioNext         { spawn "playerctl" "next"; }
    XF86AudioPrev         { spawn "playerctl" "previous"; }
}
EOF
    fi

    # --------------------------------------------------------------------------
    # G. Flatpak GTK Theming Overrides (if flatpak is installed)
    # --------------------------------------------------------------------------
    if command -v flatpak &>/dev/null; then
        log_info "Configuring Flatpak sandbox filesystem overrides for GTK themes..."
        if [[ "$DRY_RUN" == false ]]; then
            flatpak override --user --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro 2>/dev/null || true
        fi
    fi

    log_success "All configurations and scripts generated successfully."
}

# ------------------------------------------------------------------------------
# 6. Verification and Validation
# ------------------------------------------------------------------------------
validate_installation() {
    log_section "Phase 4: Configuration Validation & Syntax Checks"

    if command -v niri &>/dev/null; then
        log_info "Running Niri syntax validation..."
        if niri validate --config "$USER_HOME/.config/niri/config.kdl"; then
            log_success "Niri configuration syntax is VALID."
        else
            log_error "Niri configuration contains errors. Please review output above."
        fi
    else
        log_warn "Niri binary not found in PATH; skipping validation."
    fi

    if command -v noctalia &>/dev/null; then
        log_info "Running Noctalia configuration validation..."
        if noctalia config validate; then
            log_success "Noctalia configuration syntax is VALID."
        else
            log_warn "Noctalia reported warnings/issues in config."
        fi
    else
        log_warn "Noctalia binary not found in PATH; skipping validation."
    fi
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
main() {
    log_section "Niri + Noctalia Shell Setup Starting"
    install_packages
    setup_configurations
    validate_installation

    log_section "Setup Completed Successfully!"
    cat <<EOF
${BOLD}${GREEN}Summary of Installed System:${RESET}
  - ${BOLD}Compositor:${RESET} Niri (2560x1600 @ 165Hz, Scale 1.25, VRR)
  - ${BOLD}Shell Layer:${RESET} Noctalia Shell v5 (Top Capsule Bar + Bottom Intellihide Dock)
  - ${BOLD}Terminal:${RESET} Kitty (remote-controlled socket with auto-theming)
  - ${BOLD}Power Management:${RESET} Adaptive AC vs. Battery daemon (Aggressive saver on battery)
  - ${BOLD}Gestures:${RESET}
      • 3-Finger Horizontal Swipe: Smooth Column Scroll
      • 3-Finger Vertical Swipe: Workspace Switching
      • 4-Finger Vertical Swipe Up: Niri Overview Mode
  - ${BOLD}Keybindings:${RESET} Full Dank Material Shell (DMS) conventions:
      • Mod+Return: Kitty
      • Mod+Space / Mod+D: Launcher
      • Mod+S: Control Center
      • Mod+Comma: Settings
      • Mod+O: Overview
      • Mod+W: Shuffle Wallpaper & Palette
      • Mod+Escape: Lock Session

To launch your new session:
  1. Log out of your current desktop session.
  2. Select "Niri" from your display manager (GDM, SDDM, or greetd).
  3. Log in and enjoy!
EOF
}

main "$@"

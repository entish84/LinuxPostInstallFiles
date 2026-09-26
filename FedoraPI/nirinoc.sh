#!/usr/bin/env bash
# ==============================================================================
# Setup Niri & Noctalia on Fedora 44 GNOME Workstation
# Package Source: Fedora Official Repositories & Terra Repository (No COPR)
# ==============================================================================

set -euo pipefail

# ANSI color codes
CLR_RESET="\033[0m"
CLR_BOLD="\033[1m"
CLR_BLUE="\033[34m"
CLR_GREEN="\033[32m"
CLR_YELLOW="\033[33m"
CLR_RED="\033[31m"

log_info()    { echo -e "${CLR_BLUE}${CLR_BOLD}[INFO]${CLR_RESET} $1"; }
log_success() { echo -e "${CLR_GREEN}${CLR_BOLD}[OK]${CLR_RESET}   $1"; }
log_warn()    { echo -e "${CLR_YELLOW}${CLR_BOLD}[WARN]${CLR_RESET} $1"; }
log_error()   { echo -e "${CLR_RED}${CLR_BOLD}[ERROR]${CLR_RESET} $1"; }

# ------------------------------------------------------------------------------
# 1. Pre-flight Checks & Cleanup of Legacy Artifacts
# ------------------------------------------------------------------------------
log_info "Verifying environment and purging legacy shims..."

if [[ $EUID -eq 0 ]]; then
    log_error "Do not run this script directly as root. Run as your standard user."
    exit 1
fi

# Request sudo credentials up front & register exit trap for background keepalive
sudo -v
SUDO_LOOP_PID=""
cleanup() {
    if [[ -n "${SUDO_LOOP_PID:-}" ]] && kill -0 "$SUDO_LOOP_PID" 2>/dev/null; then
        kill "$SUDO_LOOP_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_LOOP_PID=$!

# Remove any previously compiled local binaries or fallback shims in /usr/local/bin
sudo rm -f /usr/local/bin/noctalia /usr/local/bin/noctalia-shell 2>/dev/null || true
rm -rf /tmp/noctalia-build-* 2>/dev/null || true

# ------------------------------------------------------------------------------
# 2. Package Installation via DNF 5 (Official Fedora & Terra Repositories)
# ------------------------------------------------------------------------------
log_info "Installing Niri, Noctalia, desktop utilities, and font libraries..."

# Installs native RPM binaries directly from official Fedora and enabled Terra repos
sudo dnf install -y --skip-unavailable \
    niri \
    noctalia \
    xwayland-satellite \
    xorg-x11-server-Xwayland \
    xdg-desktop-portal-gtk \
    ptyxis \
    alacritty \
    nautilus \
    brightnessctl \
    playerctl \
    wireplumber \
    pipewire-utils \
    wl-clipboard \
    pavucontrol \
    mate-polkit \
    libsecret \
    fira-code-fonts \
    rsms-inter-fonts \
    rsms-inter-vf-fonts \
    fontawesome-fonts \
    fontawesome-fonts-all

# Verify binary availability in system PATH
if ! command -v niri &>/dev/null; then
    log_error "Niri binary not found. Verify your Fedora / Terra repository configuration."
    exit 1
fi

if ! command -v noctalia &>/dev/null; then
    log_error "Noctalia binary not found. Verify that the Terra repository is enabled."
    exit 1
fi

log_success "Binaries verified: $(command -v niri) and $(command -v noctalia)"

# ------------------------------------------------------------------------------
# 3. Configure Noctalia Shell (~/.config/noctalia/config.toml)
# ------------------------------------------------------------------------------
log_info "Deploying modern Noctalia desktop configuration..."

NOCTALIA_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia"
mkdir -p "$NOCTALIA_CONF_DIR"

if [[ -f "$NOCTALIA_CONF_DIR/config.toml" ]]; then
    mv "$NOCTALIA_CONF_DIR/config.toml" "$NOCTALIA_CONF_DIR/config.toml.bak.$(date +%s)"
fi

cat <<'EOF' > "$NOCTALIA_CONF_DIR/config.toml"
# Noctalia Desktop Shell Configuration
[theme]
mode = "dark"
source = "builtin"
builtin = "Noctalia"

[shell]
ui_scale = 1.0
font_family = "Inter"
niri_overview_type_to_launch_enabled = true

[bar.default]
position = "top"
thickness = 38
exclusive = true
layer = "top"

[bar.default.left]
widgets = [
  "launcher",
  "workspaces",
  "taskbar"
]

[bar.default.center]
widgets = [
  "clock",
  "media"
]

[bar.default.right]
widgets = [
  "tray",
  "network",
  "battery",
  "brightness",
  "volume",
  "control-center"
]

[control_center]
sidebar = "compact"
width = 720
show_shortcut_labels = true
show_session_button = true

[launcher]
show_icons = true
compact = false
sort_by_usage = true
EOF

log_success "Wrote ~/.config/noctalia/config.toml"

# ------------------------------------------------------------------------------
# 4. Configure Niri Compositor (~/.config/niri/config.kdl)
# ------------------------------------------------------------------------------
log_info "Writing Niri layout rules and DankMaterialShell keyboard bindings..."

NIRI_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
mkdir -p "$NIRI_CONF_DIR"

if [[ -f "$NIRI_CONF_DIR/config.kdl" ]]; then
    mv "$NIRI_CONF_DIR/config.kdl" "$NIRI_CONF_DIR/config.kdl.bak.$(date +%s)"
fi

cat <<'EOF' > "$NIRI_CONF_DIR/config.kdl"
// =============================================================================
// NIRI CONFIGURATION - Fedora GNOME Workstation
// DankMaterialShell layout workflows & Noctalia desktop shell integration
// =============================================================================

// --- Startup Services ---
spawn-at-startup "noctalia"
spawn-at-startup "xwayland-satellite"
spawn-at-startup "/usr/libexec/polkit-mate-authentication-agent-1"

// --- Laptop Input & Gesture Tuning ---
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
        scroll-method "two-finger"
    }

    mouse {
        accel-speed 0.0
    }

    warp-mouse-to-focus
    focus-follows-mouse max-scroll-amount="0%"
}

// --- Layout & Visual Properties ---
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
        inactive-color "#24283b"
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

// --- Animation Physics ---
animations {
    slowdown 1.0
}

// --- Window Rules & Floats ---
window-rule {
    geometry-corner-radius 14
    clip-to-geometry true
}

window-rule {
    match app-id=r#"^dev\.noctalia\.Noctalia$"#
    open-floating true
    default-column-width { fixed 1080; }
}

window-rule {
    match title=r#"^(Open File|Save File)$"#
    open-floating true
}

window-rule {
    match app-id=r#"^(xdg-desktop-portal-gtk|pavucontrol)$"#
    open-floating true
}

// =============================================================================
// KEYBINDINGS (DankMaterialShell-Style Ergonomics)
// =============================================================================
binds {
    // --- Application Launchers ---
    Mod+Return hotkey-overlay-title="Terminal" { spawn "ptyxis"; }
    Mod+Shift+Return hotkey-overlay-title="Terminal (Alacritty)" { spawn "alacritty"; }
    Mod+Space hotkey-overlay-title="App Launcher" { spawn "sh" "-c" "noctalia msg panel-toggle launcher"; }
    Mod+D hotkey-overlay-title="Dashboard / Launcher" { spawn "sh" "-c" "noctalia msg panel-toggle launcher"; }
    Mod+E hotkey-overlay-title="File Manager" { spawn "nautilus"; }
    Mod+S hotkey-overlay-title="Control Center" { spawn "sh" "-c" "noctalia msg panel-toggle control-center"; }
    Mod+N hotkey-overlay-title="Notifications" { spawn "sh" "-c" "noctalia msg panel-toggle control-center notifications"; }
    Mod+V hotkey-overlay-title="Clipboard History" { spawn "sh" "-c" "noctalia msg panel-toggle clipboard"; }
    Mod+Comma hotkey-overlay-title="Noctalia Settings" { spawn "sh" "-c" "noctalia msg settings-toggle"; }
    Alt+Tab hotkey-overlay-title="Window Switcher" { spawn "sh" "-c" "noctalia msg window-switcher"; }

    // --- Window Actions ---
    Mod+Q hotkey-overlay-title="Close Window" { close-window; }
    Mod+F hotkey-overlay-title="Maximize Column" { maximize-column; }
    Mod+Shift+F hotkey-overlay-title="Toggle Fullscreen" { fullscreen-window; }
    Mod+C hotkey-overlay-title="Center Column" { center-column; }

    // --- Focus Navigation (Mod + Arrows or Vim Keys) ---
    Mod+Left  hotkey-overlay-title="Focus Column Left"  { focus-column-left; }
    Mod+Right hotkey-overlay-title="Focus Column Right" { focus-column-right; }
    Mod+Down  hotkey-overlay-title="Focus Window Down"  { focus-window-down; }
    Mod+Up    hotkey-overlay-title="Focus Window Up"    { focus-window-up; }

    Mod+H { focus-column-left; }
    Mod+L { focus-column-right; }
    Mod+J { focus-window-down; }
    Mod+K { focus-window-up; }

    Mod+Home { focus-column-first; }
    Mod+End  { focus-column-last; }

    // --- Window Movement (Mod + Shift + Direction) ---
    Mod+Shift+Left  hotkey-overlay-title="Move Column Left"  { move-column-left; }
    Mod+Shift+Right hotkey-overlay-title="Move Column Right" { move-column-right; }
    Mod+Shift+Down  hotkey-overlay-title="Move Window Down"  { move-window-down; }
    Mod+Shift+Up    hotkey-overlay-title="Move Window Up"    { move-window-up; }

    Mod+Shift+H { move-column-left; }
    Mod+Shift+L { move-column-right; }
    Mod+Shift+J { move-window-down; }
    Mod+Shift+K { move-window-up; }

    Mod+Shift+Home { move-column-to-first; }
    Mod+Shift+End  { move-column-to-last; }

    // --- Multi-Monitor Navigation ---
    Mod+Ctrl+Left  { focus-monitor-left; }
    Mod+Ctrl+Right { focus-monitor-right; }
    Mod+Shift+Ctrl+Left  { move-column-to-monitor-left; }
    Mod+Shift+Ctrl+Right { move-column-to-monitor-right; }

    // --- Column Consumption / Expelling ---
    Mod+BracketLeft  hotkey-overlay-title="Consume Window into Column" { consume-window-into-column; }
    Mod+BracketRight hotkey-overlay-title="Expel Window from Column"   { expel-window-from-column; }

    // --- Column Sizing & Width Presets ---
    Mod+R hotkey-overlay-title="Cycle Column Width Preset" { switch-preset-column-width; }
    Mod+Shift+R hotkey-overlay-title="Reset Window Height"  { reset-window-height; }
    Mod+Minus hotkey-overlay-title="Decrease Column Width"  { set-column-width "-10%"; }
    Mod+Equal hotkey-overlay-title="Increase Column Width"  { set-column-width "+10%"; }

    // --- Overview & Workspaces ---
    Mod+O repeat=false hotkey-overlay-title="Toggle Launcher" { spawn "sh" "-c" "noctalia msg panel-toggle launcher"; }
    Mod+Page_Down       { focus-workspace-down; }
    Mod+Page_Up         { focus-workspace-up; }
    Mod+Shift+Page_Down { move-column-to-workspace-down; }
    Mod+Shift+Page_Up   { move-column-to-workspace-up; }

    // Direct Workspace 1-9 Navigation
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

    // --- Laptop Hardware Keys (WirePlumber, Brightnessctl, Playerctl) ---
    XF86AudioRaiseVolume allow-when-locked=true { spawn "sh" "-c" "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"; }
    XF86AudioLowerVolume allow-when-locked=true { spawn "sh" "-c" "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"; }
    XF86AudioMute        allow-when-locked=true { spawn "sh" "-c" "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; }
    XF86MonBrightnessUp   allow-when-locked=true { spawn "sh" "-c" "brightnessctl set +5%"; }
    XF86MonBrightnessDown allow-when-locked=true { spawn "sh" "-c" "brightnessctl set 5%-"; }

    XF86AudioPlay allow-when-locked=true { spawn "playerctl" "play-pause"; }
    XF86AudioNext allow-when-locked=true { spawn "playerctl" "next"; }
    XF86AudioPrev allow-when-locked=true { spawn "playerctl" "previous"; }

    // --- Screen Capture ---
    Print hotkey-overlay-title="Capture Selection" { screenshot; }
    Mod+Print hotkey-overlay-title="Capture Fullscreen" { screenshot-screen; }

    // --- Session Control ---
    Mod+Escape hotkey-overlay-title="Lock Session" { spawn "sh" "-c" "noctalia msg session lock"; }
    Mod+Alt+L hotkey-overlay-title="Lock Session"  { spawn "sh" "-c" "noctalia msg session lock"; }
    Mod+Shift+E hotkey-overlay-title="Quit Niri" { quit; }
    Mod+Shift+P hotkey-overlay-title="Turn Off Monitors" { power-off-monitors; }
    Mod+Shift+Slash hotkey-overlay-title="Show Keybinds Overlay" { show-hotkey-overlay; }

    // --- Touchpad & Mouse Wheel Scrolling ---
    Mod+WheelScrollDown cooldown-ms=150 { focus-column-right; }
    Mod+WheelScrollUp   cooldown-ms=150 { focus-column-left; }
    Mod+Shift+WheelScrollDown cooldown-ms=150 { move-column-right; }
    Mod+Shift+WheelScrollUp   cooldown-ms=150 { move-column-left; }
}
EOF

log_success "Wrote ~/.config/niri/config.kdl"

# ------------------------------------------------------------------------------
# 5. Configuration Verification & GDM Wayland Session
# ------------------------------------------------------------------------------
log_info "Validating compositor configuration syntax..."

niri validate --config "$NIRI_CONF_DIR/config.kdl"
log_success "Niri KDL syntax validated (0 errors)."

# Deploy FreeDesktop-compliant desktop entry for GDM login selector
if [[ ! -f /usr/share/wayland-sessions/niri.desktop ]]; then
    log_info "Creating /usr/share/wayland-sessions/niri.desktop..."
    sudo tee /usr/share/wayland-sessions/niri.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Niri
Comment=A scrollable-tiling Wayland compositor
Exec=niri-session
Type=Application
DesktopNames=niri;
EOF
fi

log_success "Deployment complete! Log out and choose 'Niri' via the GDM gear icon."

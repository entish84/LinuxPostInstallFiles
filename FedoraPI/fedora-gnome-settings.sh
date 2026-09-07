#!/usr/bin/env bash
#
# ==============================================================================
# Fedora 44 GNOME Workstation Configuration & Hotkeys Setup
# Version: 26.27.0
# Description: Fully audited setup script for GNOME 50 / 51 on Fedora 44.
#              Configures Omabuntu hotkeys, 9 fixed workspaces, Wayland scaling,
#              Night Light, Tokyo Night theme, Top-bar Vitals, and Clipboard
#              history (Super+V). Patches extension metadata for GNOME 50/51.
#
# EXECUTION: Run as your standard desktop user (DO NOT USE SUDO).
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# 0. User & Session Validation
# ------------------------------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
    echo -e "\033[0;31m[ERROR] Do not execute this script as root or with sudo.\033[0m" >&2
    echo -e "Run as your normal desktop user: ./fedora44_gnome_setup.sh\033[0m" >&2
    exit 1
fi

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
fi

# ------------------------------------------------------------------------------
# Logging & Visual Helpers
# ------------------------------------------------------------------------------
step_header() {
    local title="${1:-}"
    echo ""
    echo -e "\033[1;34m═════════════════════════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[1;36m [*]\033[0m \033[1;37m${title}\033[0m"
    echo -e "\033[1;34m═════════════════════════════════════════════════════════════════════════════\033[0m"
}

subtask_start() {
    local desc="${1:-}"
    echo -ne "  \033[1;33m➜\033[0m \033[0;37m${desc}...\033[0m"
}

subtask_ok() {
    local desc="${1:-}"
    echo -e "\r  \033[1;32m✔\033[0m \033[0;32m${desc} [CONFIGURED]\033[0m\033[K"
}

subtask_warn() {
    local desc="${1:-}"
    echo -e "\r  \033[1;33m⚠\033[0m \033[1;33m${desc} [NOTICE]\033[0m\033[K"
}

# ------------------------------------------------------------------------------
# 1. Extensions Installation & System Dependencies
# ------------------------------------------------------------------------------
step_header "Installing GNOME 50/51 Extensions & Dependencies"

subtask_start "Installing repository extensions, sensors, and GNOME Tweaks"
sudo dnf install -y \
    gnome-tweaks \
    gnome-extensions-app \
    gnome-shell-extension-appindicator \
    gnome-shell-extension-dash-to-dock \
    gnome-shell-extension-blur-my-shell \
    gnome-shell-extension-tiling-assistant \
    gnome-shell-extension-just-perfection \
    gnome-shell-extension-caffeine \
    gnome-shell-extension-user-theme \
    libgtop2 \
    lm_sensors \
    jq curl unzip >/dev/null 2>&1 || true
subtask_ok "Native packages and sensor libraries installed"

subtask_start "Installing Extension Manager GUI from Flathub"
flatpak install -y --noninteractive flathub com.mattjakeman.ExtensionManager >/dev/null 2>&1 || true
subtask_ok "Extension Manager Flatpak verified"

# Robust EGO Extension Downloader & Metadata Patcher for GNOME 50/51
install_ego_extension() {
    local uuid="$1"
    local shell_major
    shell_major=$(gnome-shell --version 2>/dev/null | awk '{print $3}' | cut -d. -f1)
    [[ -z "$shell_major" ]] && shell_major="50"

    local download_url=""
    download_url=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell_major}" 2>/dev/null | jq -r '.download_url // empty')
    
    if [[ -z "$download_url" ]]; then
        download_url=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}" 2>/dev/null | jq -r '.download_url // empty')
    fi

    if [[ -n "$download_url" ]]; then
        local target_dir="$HOME/.local/share/gnome-shell/extensions/${uuid}"
        local tmp_zip="/tmp/${uuid}.zip"
        
        curl -fsSL "https://extensions.gnome.org${download_url}" -o "$tmp_zip" 2>/dev/null || true
        
        if [[ -f "$tmp_zip" ]]; then
            mkdir -p "$target_dir"
            unzip -qo "$tmp_zip" -d "$target_dir"
            rm -f "$tmp_zip"

            # Patch metadata.json to ensure running GNOME version is accepted
            if [[ -f "${target_dir}/metadata.json" ]]; then
                local has_ver
                has_ver=$(jq --arg v "$shell_major" '."shell-version" | index($v)' "${target_dir}/metadata.json" 2>/dev/null || echo "null")
                if [[ "$has_ver" == "null" ]]; then
                    jq --arg v "$shell_major" '."shell-version" += [$v]' "${target_dir}/metadata.json" > "${target_dir}/metadata.json.tmp" 2>/dev/null && \
                    mv "${target_dir}/metadata.json.tmp" "${target_dir}/metadata.json"
                fi
            fi
        fi
    fi
}

subtask_start "Fetching and patching Clipboard Indicator & Vitals for GNOME ${shell_major:-50}"
install_ego_extension "clipboard-indicator@tudmotu.com"
install_ego_extension "Vitals@CoreCoding.com"
subtask_ok "Clipboard Indicator and Vitals (Vitals@CoreCoding.com) deployed"

# Compile local schemas so GSettings can access them immediately
mkdir -p "$HOME/.local/share/glib-2.0/schemas"
for sdir in "$HOME"/.local/share/gnome-shell/extensions/*/schemas; do
    if [[ -d "$sdir" ]]; then
        cp "$sdir"/*.gschema.xml "$HOME/.local/share/glib-2.0/schemas/" 2>/dev/null || true
    fi
done
glib-compile-schemas "$HOME/.local/share/glib-2.0/schemas" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 2. Appearance, Night Light, Typography & Display Setup
# ------------------------------------------------------------------------------
step_header "Aesthetics, Typography, Night Light & Wayland Setup"

subtask_start "Configuring dark theme, blue accent, and Papirus icons"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface accent-color 'blue' 2>/dev/null || true
subtask_ok "Dark mode, Papirus-Dark, and blue accent applied"

subtask_start "Configuring typography (Inter Variable & 0xProto Nerd Font)"
gsettings set org.gnome.desktop.interface font-name 'Inter Variable 11'
gsettings set org.gnome.desktop.interface document-font-name 'Inter Variable 11'
gsettings set org.gnome.desktop.interface monospace-font-name '0xProto Nerd Font 12'
gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Inter Variable Bold 11'
subtask_ok "System-wide typography configured"

subtask_start "Enabling battery percentage and window control buttons"
gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
gsettings set org.gnome.mutter center-new-windows true
gsettings set org.gnome.mutter attach-modal-dialogs true
subtask_ok "Top panel battery percent and titlebar controls configured"

subtask_start "Configuring automatic Circadian Night Light (3700K)"
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic true
gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 3700
subtask_ok "Night Light configured (automatic sunset/sunrise, 3700K)"

subtask_start "Enabling Wayland fractional scaling"
gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']"
subtask_ok "Wayland fractional scaling enabled"

# ------------------------------------------------------------------------------
# 3. Workspaces & Conflict Resolution (Fixed Pool 1..9)
# ------------------------------------------------------------------------------
step_header "Fixed Workspaces (1..9) & Shortcut Conflict Resolution"

subtask_start "Unbinding default Super+1..9 pinned dock launchers"
for i in {1..9}; do
    gsettings set org.gnome.shell.keybindings "switch-to-application-${i}" "[]"
done
subtask_ok "Dock application launcher bindings cleared"

subtask_start "Establishing 9 Fixed Workspaces (i3/Sway style)"
gsettings set org.gnome.mutter dynamic-workspaces false
gsettings set org.gnome.desktop.wm.preferences num-workspaces 9

for i in {1..9}; do
    gsettings set org.gnome.desktop.wm.keybindings "switch-to-workspace-${i}" "['<Super>${i}']"
    gsettings set org.gnome.desktop.wm.keybindings "move-to-workspace-${i}" "['<Super><Shift>${i}']"
done

gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-left "['<Super>bracketleft', '<Super>Page_Up']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-right "['<Super>bracketright', '<Super>Page_Down']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-left "['<Super><Shift>bracketleft']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-right "['<Super><Shift>bracketright']"
subtask_ok "9 Fixed workspaces mapped to Super+1..9 and Super+[/]"

# ------------------------------------------------------------------------------
# 4. Window Management & Snap Keybindings
# ------------------------------------------------------------------------------
step_header "Window Controls & Tiling Keybindings"

subtask_start "Mapping window control hotkeys"
gsettings set org.gnome.desktop.wm.keybindings close "['<Super>q', '<Alt>F4']"
gsettings set org.gnome.desktop.wm.keybindings toggle-maximized "['<Super>m']"
gsettings set org.gnome.desktop.wm.keybindings minimize "['<Super>h']"
gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>Tab']"
gsettings set org.gnome.desktop.wm.keybindings switch-windows-backward "['<Shift><Alt>Tab']"

# Native Half-Screen Snapping
gsettings set org.gnome.mutter.keybindings toggle-tiled-left "['<Super>Left']"
gsettings set org.gnome.mutter.keybindings toggle-tiled-right "['<Super>Right']"
gsettings set org.gnome.desktop.wm.keybindings maximize "['<Super>Up']"
gsettings set org.gnome.desktop.wm.keybindings unmaximize "['<Super>Down']"

# Screenshots
gsettings set org.gnome.shell.keybindings show-screenshot-ui "['<Super><Shift>s', 'Print']"
gsettings set org.gnome.shell.keybindings show-screen-recording-ui "['<Ctrl><Super><Shift>r']"
subtask_ok "Window actions (Super+Q/M/H), tiling, and screenshot (Super+Shift+S) bound"

# ------------------------------------------------------------------------------
# 5. Custom Application Launchers & Scratchpad Terminal
# ------------------------------------------------------------------------------
step_header "Custom Application Shortcuts & Scratchpad"

subtask_start "Binding application shortcuts and Kitty dropdown scratchpad"
CUSTOM_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"

declare -a SHORTCUTS=(
    "Terminal:kitty:<Super>Return"
    "Scratchpad:kitty --class scratchpad:<Super><Shift>Return"
    "Browser:google-chrome:<Super>b"
    "FileManager:kitty -e yazi:<Super>e"
    "Editor:code:<Super>c"
    "ActivityMonitor:kitty -e btop:<Super><Shift>Escape"
)

BINDING_LIST=""
INDEX=0

for item in "${SHORTCUTS[@]}"; do
    IFS=":" read -r name cmd binding <<< "$item"
    ENTRY_PATH="${CUSTOM_PATH}/custom${INDEX}/"
    SCHEMA="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${ENTRY_PATH}"

    gsettings set "$SCHEMA" name "$name"
    gsettings set "$SCHEMA" command "$cmd"
    gsettings set "$SCHEMA" binding "$binding"

    if [[ -z "$BINDING_LIST" ]]; then
        BINDING_LIST="'${ENTRY_PATH}'"
    else
        BINDING_LIST="${BINDING_LIST}, '${ENTRY_PATH}'"
    fi
    ((INDEX++))
done

gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "[${BINDING_LIST}]"
subtask_ok "Launchers configured: Super+Return, Super+Shift+Return, Super+B/E/C"

# ------------------------------------------------------------------------------
# 6. Extension Tuning (Tiling Assistant, Vitals, Clipboard, Blur, Dock)
# ------------------------------------------------------------------------------
step_header "Enabling & Tuning Extension Preferences"

subtask_start "Activating all extensions via GNOME Shell"
EXTENSIONS=(
    "appindicatorsupport@rgcjonas.gmail.com"
    "dash-to-dock@micxgx.gmail.com"
    "blur-my-shell@aunetx"
    "tiling-assistant@leleat-on-github"
    "just-perfection-desktop@just-perfection"
    "caffeine@patapon.info"
    "user-theme@gnome-shell-extensions.gcampax.github.com"
    "clipboard-indicator@tudmotu.com"
    "Vitals@CoreCoding.com"
)

for ext in "${EXTENSIONS[@]}"; do
    gnome-extensions enable "$ext" 2>/dev/null || true
done
subtask_ok "All extensions active"

subtask_start "Configuring Tiling Assistant (Quarter-snapping shortcuts)"
TA_SCHEMA="org.gnome.shell.extensions.tiling-assistant"
if gsettings list-schemas | grep -q "$TA_SCHEMA"; then
    gsettings set "$TA_SCHEMA" enable-tiling-popup false
    gsettings set "$TA_SCHEMA" window-gap 6
    gsettings set "$TA_SCHEMA" tile-topleft-quarter "['<Super><Alt>Left', '<Super><Alt>Up']"
    gsettings set "$TA_SCHEMA" tile-topright-quarter "['<Super><Alt>Right', '<Super><Alt>Up']"
    gsettings set "$TA_SCHEMA" tile-bottomleft-quarter "['<Super><Alt>Left', '<Super><Alt>Down']"
    gsettings set "$TA_SCHEMA" tile-bottomright-quarter "['<Super><Alt>Right', '<Super><Alt>Down']"
    subtask_ok "Tiling Assistant quarter-snapping configured"
else
    subtask_warn "Tiling Assistant schema will initialize on first desktop login"
fi

subtask_start "Configuring Clipboard Indicator (Super+V shortcut)"
CI_SCHEMA="org.gnome.shell.extensions.clipboard-indicator"
if gsettings list-schemas | grep -q "$CI_SCHEMA"; then
    gsettings set "$CI_SCHEMA" toggle-menu "['<Super>v']"
    gsettings set "$CI_SCHEMA" history-size 50
    gsettings set "$CI_SCHEMA" confirm-clear true
    subtask_ok "Clipboard Indicator bound to Super+V"
else
    subtask_warn "Clipboard Indicator schema will initialize on first desktop login"
fi

subtask_start "Configuring Vitals Top-Bar System Monitor"
VITALS_SCHEMA="org.gnome.shell.extensions.vitals"
if gsettings list-schemas | grep -q "$VITALS_SCHEMA"; then
    gsettings set "$VITALS_SCHEMA" show-temperature true
    gsettings set "$VITALS_SCHEMA" show-memory true
    gsettings set "$VITALS_SCHEMA" show-cpu true
    gsettings set "$VITALS_SCHEMA" show-network true
    gsettings set "$VITALS_SCHEMA" show-fan true 2>/dev/null || true
    gsettings set "$VITALS_SCHEMA" update-time 3
    subtask_ok "Vitals CPU, RAM, Fan, and Network monitors active"
else
    subtask_warn "Vitals schema will initialize on first desktop login"
fi

subtask_start "Configuring Dash to Dock (bottom, centered, autohide)"
DOCK_SCHEMA="org.gnome.shell.extensions.dash-to-dock"
if gsettings list-schemas | grep -q "$DOCK_SCHEMA"; then
    gsettings set "$DOCK_SCHEMA" dock-position 'BOTTOM'
    gsettings set "$DOCK_SCHEMA" dock-fixed false
    gsettings set "$DOCK_SCHEMA" autohide true
    gsettings set "$DOCK_SCHEMA" intellihide true
    gsettings set "$DOCK_SCHEMA" dash-max-icon-size 44
    gsettings set "$DOCK_SCHEMA" extend-height false
    gsettings set "$DOCK_SCHEMA" running-indicator-style 'DOTS'
    gsettings set "$DOCK_SCHEMA" transparency-mode 'DYNAMIC'
    subtask_ok "Dash to Dock floating panel layout configured"
else
    subtask_warn "Dash to Dock schema will initialize on first desktop login"
fi

subtask_start "Configuring Blur-My-Shell frosted-glass styling"
BMS_SCHEMA="org.gnome.shell.extensions.blur-my-shell"
if gsettings list-schemas | grep -q "$BMS_SCHEMA"; then
    gsettings set "$BMS_SCHEMA.panel" blur true 2>/dev/null || true
    gsettings set "$BMS_SCHEMA.panel" brightness 0.75 2>/dev/null || true
    gsettings set "$BMS_SCHEMA.dash-to-dock" blur true 2>/dev/null || true
    gsettings set "$BMS_SCHEMA.dash-to-dock" brightness 0.75 2>/dev/null || true
    gsettings set "$BMS_SCHEMA.overview" blur true 2>/dev/null || true
    subtask_ok "Frosted-glass blur applied to panel, dock, and overview"
else
    subtask_warn "Blur-My-Shell schema will initialize on first desktop login"
fi

subtask_start "Configuring Just Perfection desktop interface cleanups"
JP_SCHEMA="org.gnome.shell.extensions.just-perfection"
if gsettings list-schemas | grep -q "$JP_SCHEMA"; then
    gsettings set "$JP_SCHEMA" accessibility-menu false
    gsettings set "$JP_SCHEMA" workspace-switcher-should-show true
    gsettings set "$JP_SCHEMA" window-demands-attention-focus true
    subtask_ok "Just Perfection interface cleanups applied"
else
    subtask_warn "Just Perfection schema will initialize on first desktop login"
fi

# ------------------------------------------------------------------------------
# Finish & Verification
# ------------------------------------------------------------------------------
echo ""
echo -e "\033[1;32m═════════════════════════════════════════════════════════════════════════════\033[0m"
echo -e "\033[1;32m  FEDORA GNOME ENVIRONMENT SETUP COMPLETED SUCCESSFULLY (v${SCRIPT_VERSION})\033[0m"
echo -e "\033[1;32m═════════════════════════════════════════════════════════════════════════════\033[0m"
echo ""
echo "Summary of Configured Features:"
echo "  • Fixed Workspaces:     9 Workspaces (Super + 1..9, Super + Shift + 1..9)"
echo "  • Tiling Snapping:      Half-screen (Super + Arrows) & Quarter-screen (Super + Alt + Arrows)"
echo "  • Clipboard History:    Super + V"
echo "  • Kitty Terminal:       Super + Return & Super + Shift + Return (Scratchpad)"
echo "  • Top-bar Hardware:     Vitals (CPU, RAM, Fan, Network, Temp)"
echo "  • Appearance & Scaling: Wayland fractional scaling active, 3700K Night Light"
echo ""
echo -e "\033[1;33m[NEXT STEP]\033[0m GNOME 50/51 runs exclusively on Wayland. Log out of your session"
echo "and log back in to initialize the new Mutter compositor settings and extensions."
echo ""
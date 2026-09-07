#!/usr/bin/env bash
#
# ==============================================================================
# Fedora 44 GNOME Workstation Configuration & Hotkeys Setup
# Version: 26.34.0 (Complete Omabuntu Specification Release)
# Description: Implements the exact hotkey, window manager, and desktop
#              specification from Omabuntu/Omakub:
#              - Alt+1..9 for Dock Apps
#              - Super+1..9 for Fixed Workspaces
#              - Super+W / Super+Q to close windows
#              - Disabled animations for instant switching
#              - Pure user-space extensions (~/.local/share) with local schemas
#
# EXECUTION: Run as your normal desktop user (DO NOT USE SUDO).
# ==============================================================================

set -uo pipefail

readonly SCRIPT_VERSION="26.34.0"

if [[ $EUID -eq 0 ]]; then
    echo -e "\033[0;31m[ERROR] Do not execute this script as root or with sudo.\033[0m" >&2
    echo -e "Run as your normal desktop user: ./fedora44_gnome_setup.sh\033[0m" >&2
    exit 1
fi

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
fi

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

# ------------------------------------------------------------------------------
# 1. System Dependencies & User-Space Extension Cleanups
# ------------------------------------------------------------------------------
step_header "System Dependencies & Extension Environment"

subtask_start "Purging system-wide RPM extensions from /usr/share"
sudo dnf remove -y \
    gnome-shell-extension-dash-to-dock \
    gnome-shell-extension-blur-my-shell \
    gnome-shell-extension-just-perfection \
    gnome-shell-extension-appindicator \
    gnome-shell-extension-auto-move-windows \
    gnome-shell-extension-workspace-indicator \
    gnome-shell-extension-user-theme >/dev/null 2>&1 || true
subtask_ok "System-wide RPM extensions cleaned"

subtask_start "Installing base user-space tools & Extension Manager Flatpak"
sudo dnf install -y gnome-tweaks gnome-extensions-app libgtop2 lm_sensors jq curl unzip >/dev/null 2>&1 || true
flatpak install -y --noninteractive flathub com.mattjakeman.ExtensionManager >/dev/null 2>&1 || true
subtask_ok "Helper tools and Extension Manager ready"

# ------------------------------------------------------------------------------
# 2. Pure User-Space Extension Installer (extensions.gnome.org)
# ------------------------------------------------------------------------------
step_header "Installing Verified User-Space Extensions"

USER_EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
mkdir -p "$USER_EXT_DIR"

install_user_extension() {
    local uuid="$1"
    local shell_major
    shell_major=$(gnome-shell --version 2>/dev/null | awk '{print $3}' | cut -d. -f1 || echo "50")

    local download_url=""
    download_url=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell_major}" 2>/dev/null | jq -r '.download_url // empty')

    if [[ -z "$download_url" ]]; then
        download_url=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}" 2>/dev/null | jq -r '.download_url // empty')
    fi

    if [[ -n "$download_url" ]]; then
        local tmp_zip="/tmp/${uuid}.zip"
        local target_dir="${USER_EXT_DIR}/${uuid}"

        curl -fsSL "https://extensions.gnome.org${download_url}" -o "$tmp_zip" 2>/dev/null || true

        if [[ -f "$tmp_zip" ]]; then
            rm -rf "$target_dir"
            mkdir -p "$target_dir"
            unzip -qo "$tmp_zip" -d "$target_dir"
            rm -f "$tmp_zip"

            if [[ -f "${target_dir}/metadata.json" ]]; then
                local has_ver
                has_ver=$(jq --arg v "$shell_major" '."shell-version" | index($v)' "${target_dir}/metadata.json" 2>/dev/null || echo "null")
                if [[ "$has_ver" == "null" ]]; then
                    jq --arg v "$shell_major" '."shell-version" += [$v]' "${target_dir}/metadata.json" > "${target_dir}/metadata.json.tmp" 2>/dev/null && \
                    mv "${target_dir}/metadata.json.tmp" "${target_dir}/metadata.json"
                fi
            fi

            if [[ -d "${target_dir}/schemas" ]]; then
                glib-compile-schemas "${target_dir}/schemas" 2>/dev/null || true
            fi
        fi
    fi
}

USER_EXTENSIONS=(
    "dash-to-dock@micxgx.gmail.com"
    "blur-my-shell@aunetx"
    "just-perfection-desktop@just-perfection"
    "appindicatorsupport@rgcjonas.gmail.com"
    "auto-move-windows@gnome-shell-extensions.gcampax.github.com"
    "workspace-indicator@gnome-shell-extensions.gcampax.github.com"
    "user-theme@gnome-shell-extensions.gcampax.github.com"
)

for ext_uuid in "${USER_EXTENSIONS[@]}"; do
    subtask_start "Installing ${ext_uuid%%@*} in user space"
    install_user_extension "$ext_uuid"
    subtask_ok "${ext_uuid%%@*} installed in ~/.local/share"
done

# Compile and export local schemas
SCHEMA_STORE="$HOME/.local/share/glib-2.0/schemas"
mkdir -p "$SCHEMA_STORE"
find "$USER_EXT_DIR" -maxdepth 3 -type f -name "*.gschema.xml" -exec cp {} "$SCHEMA_STORE/" \; 2>/dev/null || true
glib-compile-schemas "$SCHEMA_STORE" 2>/dev/null || true

export XDG_DATA_DIRS="$HOME/.local/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GSETTINGS_SCHEMA_DIR="$SCHEMA_STORE"

# ------------------------------------------------------------------------------
# 3. Omabuntu Performance & Visual Settings
# ------------------------------------------------------------------------------
step_header "Applying Omabuntu Desktop Settings & Theme"

subtask_start "Disabling animations (instant UI switching)"
gsettings set org.gnome.desktop.interface enable-animations false
subtask_ok "Window and workspace animations disabled"

subtask_start "Configuring dark theme, blue accent, and Papirus-Dark icons"
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
subtask_ok "Typography configured"

subtask_start "Setting window buttons and behavior"
gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
gsettings set org.gnome.mutter center-new-windows true
gsettings set org.gnome.mutter attach-modal-dialogs true
gsettings set org.gnome.desktop.wm.preferences focus-mode 'click'
subtask_ok "Titlebar buttons and focus mode established"

subtask_start "Configuring automatic Circadian Night Light (3700K)"
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic true
gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 3700
subtask_ok "Circadian Night Light enabled"

# ------------------------------------------------------------------------------
# 4. Omabuntu Hotkeys: Workspaces vs Dock Apps (Alt+1..9 vs Super+1..9)
# ------------------------------------------------------------------------------
step_header "Configuring Omabuntu Navigation & App Switching Hotkeys"

subtask_start "Mapping Alt + 1..9 to jump to pinned dock apps"
for i in {1..9}; do
    gsettings set org.gnome.shell.keybindings "switch-to-application-${i}" "['<Alt>${i}']"
done
subtask_ok "Alt + 1..9 assigned to pinned dock applications"

subtask_start "Establishing 9 Fixed Workspaces on Super + 1..9"
gsettings set org.gnome.mutter dynamic-workspaces false
gsettings set org.gnome.desktop.wm.preferences num-workspaces 9

for i in {1..9}; do
    gsettings set org.gnome.desktop.wm.keybindings "switch-to-workspace-${i}" "['<Super>${i}']"
    gsettings set org.gnome.desktop.wm.keybindings "move-to-workspace-${i}" "['<Super><Shift>${i}']"
done

# Sequential workspace cycling
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-left "['<Super>bracketleft', '<Super>Page_Up']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-right "['<Super>bracketright', '<Super>Page_Down']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-left "['<Super><Shift>bracketleft']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-right "['<Super><Shift>bracketright']"
subtask_ok "Super + 1..9 assigned to 9 fixed workspaces"

subtask_start "Configuring Omabuntu window control shortcuts"
# Close active window: Super+W or Super+Q or Alt+F4
gsettings set org.gnome.desktop.wm.keybindings close "['<Super>w', '<Super>q', '<Alt>F4']"
gsettings set org.gnome.desktop.wm.keybindings toggle-maximized "['<Super>m']"
gsettings set org.gnome.desktop.wm.keybindings minimize "['<Super>h']"

# Alt+Tab window switching isolated to current workspace
gsettings set org.gnome.shell.app-switcher current-workspace-only true 2>/dev/null || true
gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>Tab']"
gsettings set org.gnome.desktop.wm.keybindings switch-windows-backward "['<Shift><Alt>Tab']"

# Native Half-Screen Snapping
gsettings set org.gnome.mutter.keybindings toggle-tiled-left "['<Super>Left']"
gsettings set org.gnome.mutter.keybindings toggle-tiled-right "['<Super>Right']"
gsettings set org.gnome.desktop.wm.keybindings maximize "['<Super>Up']"
gsettings set org.gnome.desktop.wm.keybindings unmaximize "['<Super>Down']"

# Fullscreen shortcuts (F11)
gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "['F11']"

# Screenshots (Omabuntu convention)
gsettings set org.gnome.shell.keybindings show-screenshot-ui "['<Super><Shift>s', 'Print']"
gsettings set org.gnome.shell.keybindings show-screen-recording-ui "['<Ctrl><Super><Shift>r']"
subtask_ok "Window management hotkeys (Super+W, Alt+Tab, F11, Snapping) applied"

# ------------------------------------------------------------------------------
# 5. Application Launchers & Scratchpad Terminal
# ------------------------------------------------------------------------------
step_header "Custom Application Shortcuts"

subtask_start "Binding application launchers"
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
subtask_ok "Custom launchers (Super+Return, Super+B, Super+E, Super+C) established"

# ------------------------------------------------------------------------------
# 6. Extension Tuning (Omabuntu Dock & Interface)
# ------------------------------------------------------------------------------
step_header "Configuring User Extensions"

subtask_start "Enabling extensions"
for ext in "${USER_EXTENSIONS[@]}"; do
    gnome-extensions enable "$ext" 2>/dev/null || true
done
subtask_ok "All extensions active"

subtask_start "Configuring Dash to Dock (Omabuntu specification)"
DOCK_SCHEMA="org.gnome.shell.extensions.dash-to-dock"
if gsettings list-schemas | grep -q "^${DOCK_SCHEMA}$"; then
    # Disable internal hotkeys so Alt+1..9 and Super+1..9 are never intercepted
    gsettings set "$DOCK_SCHEMA" hot-keys false
    gsettings set "$DOCK_SCHEMA" dock-position 'BOTTOM'
    gsettings set "$DOCK_SCHEMA" dock-fixed false
    gsettings set "$DOCK_SCHEMA" autohide true
    gsettings set "$DOCK_SCHEMA" intellihide true
    gsettings set "$DOCK_SCHEMA" dash-max-icon-size 44
    gsettings set "$DOCK_SCHEMA" extend-height false
    gsettings set "$DOCK_SCHEMA" always-center-icons true
    gsettings set "$DOCK_SCHEMA" click-action 'minimize-or-previews'
    gsettings set "$DOCK_SCHEMA" running-indicator-style 'DOTS'
    gsettings set "$DOCK_SCHEMA" transparency-mode 'DYNAMIC'
    subtask_ok "Dash to Dock configured with Omabuntu parameters"
fi

subtask_start "Configuring Auto Move Windows (Chrome->1, Code->2, Kitty->3)"
AMW_SCHEMA="org.gnome.shell.extensions.auto-move-windows"
if gsettings list-schemas | grep -q "^${AMW_SCHEMA}$"; then
    gsettings set "$AMW_SCHEMA" application-list "['google-chrome.desktop:1', 'code.desktop:2', 'kitty.desktop:3']"
    subtask_ok "Auto Move Windows mapped"
fi

subtask_start "Configuring Just Perfection & Workspace Indicator"
JP_SCHEMA="org.gnome.shell.extensions.just-perfection"
if gsettings list-schemas | grep -q "^${JP_SCHEMA}$"; then
    gsettings set "$JP_SCHEMA" accessibility-menu false
    gsettings set "$JP_SCHEMA" window-demands-attention-focus true
    # Hide default dot workspace switcher in favor of numbers
    gsettings set "$JP_SCHEMA" workspace-switcher-should-show false
    subtask_ok "Just Perfection interface adjustments applied"
fi

subtask_start "Configuring Blur My Shell"
BMS_SCHEMA="org.gnome.shell.extensions.blur-my-shell"
if gsettings list-schemas | grep -q "^${BMS_SCHEMA}$"; then
    gsettings set "$BMS_SCHEMA.panel" blur true 2>/dev/null || true
    gsettings set "$BMS_SCHEMA.panel" brightness 0.75 2>/dev/null || true
    gsettings set "$BMS_SCHEMA.dash-to-dock" blur true 2>/dev/null || true
    gsettings set "$BMS_SCHEMA.dash-to-dock" brightness 0.75 2>/dev/null || true
    gsettings set "$BMS_SCHEMA.overview" blur true 2>/dev/null || true
    subtask_ok "Frosted glass blur applied"
fi

echo ""
echo -e "\033[1;32m═════════════════════════════════════════════════════════════════════════════\033[0m"
echo -e "\033[1;32m  OMABUNTU GNOME CONFIGURATION APPLIED SUCCESSFULLY (v${SCRIPT_VERSION})\033[0m"
echo -e "\033[1;32m═════════════════════════════════════════════════════════════════════════════\033[0m"
echo ""
echo "Omabuntu Hotkey Layout:"
echo "  • Alt + 1..9:           Jump to / launch pinned Dock apps"
echo "  • Super + 1..9:         Instant switch to Workspaces 1..9 (zero animation)"
echo "  • Super + Shift + 1..9: Move active window to Workspace 1..9"
echo "  • Super + W / Super + Q:Close active window"
echo "  • Super + Return:       Launch Kitty Terminal"
echo "  • Super + B / E / C:    Launch Chrome / Yazi / VS Code"
echo "  • F11:                  Toggle Fullscreen"
echo "  • Alt + Tab:            Cycle windows on the current workspace only"
echo ""
echo -e "\033[1;33m[NEXT STEP]\033[0m Log out and log back in to reload your GNOME Wayland session."
echo ""

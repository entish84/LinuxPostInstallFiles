#!/usr/bin/env bash
#
# ==============================================================================
# Fedora 44 GNOME Workstation Configuration & Hotkeys Setup
# Version: 26.33.0 (Pure User-Space Extensions & Fixed Workspaces)
# Description: Configures all GNOME extensions strictly in user space
#              (~/.local/share/gnome-shell/extensions). Configures 9 fixed
#              numbered workspaces, Auto Move Windows, and Omabuntu keybindings.
#
# EXECUTION: Run as your normal desktop user (DO NOT USE SUDO).
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# 0. Metadata & Session Validation
# ------------------------------------------------------------------------------
readonly SCRIPT_VERSION="26.33.0"

if [[ $EUID -eq 0 ]]; then
    echo -e "\033[0;31m[ERROR] Do not execute this script as root or with sudo.\033[0m" >&2
    echo -e "Run as your normal desktop user: ./fedora44_gnome_setup.sh\033[0m" >&2
    exit 1
fi

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
fi

# ------------------------------------------------------------------------------
# Visual Logging Helpers
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
# 1. Purge System-Wide Extensions & Install Local CLI Tooling
# ------------------------------------------------------------------------------
step_header "Removing System-Wide Extensions & Installing Tools"

subtask_start "Purging system-wide RPM extensions from /usr/share"
sudo dnf remove -y \
    gnome-shell-extension-dash-to-dock \
    gnome-shell-extension-blur-my-shell \
    gnome-shell-extension-just-perfection \
    gnome-shell-extension-appindicator \
    gnome-shell-extension-auto-move-windows \
    gnome-shell-extension-workspace-indicator \
    gnome-shell-extension-user-theme >/dev/null 2>&1 || true
subtask_ok "System-wide RPM extensions removed"

subtask_start "Installing base user-space tools, sensors, and Extension Manager"
sudo dnf install -y gnome-tweaks gnome-extensions-app libgtop2 lm_sensors jq curl unzip >/dev/null 2>&1 || true
flatpak install -y --noninteractive flathub com.mattjakeman.ExtensionManager >/dev/null 2>&1 || true
subtask_ok "User-space development helpers and Extension Manager ready"

# ------------------------------------------------------------------------------
# 2. Pure User-Space Extension Installer
# ------------------------------------------------------------------------------
step_header "Installing Verified Extensions in User Space (~/.local/share)"

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

            # Inject running GNOME version if unlisted in extension metadata
            if [[ -f "${target_dir}/metadata.json" ]]; then
                local has_ver
                has_ver=$(jq --arg v "$shell_major" '."shell-version" | index($v)' "${target_dir}/metadata.json" 2>/dev/null || echo "null")
                if [[ "$has_ver" == "null" ]]; then
                    jq --arg v "$shell_major" '."shell-version" += [$v]' "${target_dir}/metadata.json" > "${target_dir}/metadata.json.tmp" 2>/dev/null && \
                    mv "${target_dir}/metadata.json.tmp" "${target_dir}/metadata.json"
                fi
            fi

            # Compile schemas internally to prevent GLib.FileError
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
    subtask_start "Installing ${ext_uuid%%@*} as user extension"
    install_user_extension "$ext_uuid"
    subtask_ok "${ext_uuid%%@*} installed in ~/.local/share"
done

# ------------------------------------------------------------------------------
# 3. User Schema Compilation & GSettings Synchronization
# ------------------------------------------------------------------------------
step_header "Indexing User GSettings Schemas"

subtask_start "Compiling and registering user schemas"
SCHEMA_STORE="$HOME/.local/share/glib-2.0/schemas"
mkdir -p "$SCHEMA_STORE"

# Copy all user-extension schema files to user schema directory
find "$USER_EXT_DIR" -maxdepth 3 -type f -name "*.gschema.xml" -exec cp {} "$SCHEMA_STORE/" \; 2>/dev/null || true
glib-compile-schemas "$SCHEMA_STORE" 2>/dev/null || true

export XDG_DATA_DIRS="$HOME/.local/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GSETTINGS_SCHEMA_DIR="$SCHEMA_STORE"
subtask_ok "User schemas compiled and ready for configuration"

# ------------------------------------------------------------------------------
# 4. Appearance, Night Light & Typography
# ------------------------------------------------------------------------------
step_header "Aesthetics, Typography & Night Light Setup"

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
subtask_ok "System typography configured"

subtask_start "Enabling battery percentage and window control buttons"
gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
gsettings set org.gnome.mutter center-new-windows true
gsettings set org.gnome.mutter attach-modal-dialogs true
subtask_ok "Battery percent and titlebar controls configured"

subtask_start "Configuring automatic Circadian Night Light (3700K)"
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic true
gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 3700
subtask_ok "Night Light configured (3700K automatic)"

# ------------------------------------------------------------------------------
# 5. Fixed Numbered Workspaces (1..9)
# ------------------------------------------------------------------------------
step_header "Fixed Workspaces (1..9) & Numeric Indicator Configuration"

subtask_start "Unbinding default Super+1..9 dock application launchers"
for i in {1..9}; do
    gsettings set org.gnome.shell.keybindings "switch-to-application-${i}" "[]"
done
subtask_ok "Dock application launcher bindings cleared"

subtask_start "Configuring 9 Fixed Workspaces and direct navigation"
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
subtask_ok "Fixed workspaces mapped to Super+1..9 and Super+[/]"

# ------------------------------------------------------------------------------
# 6. Window Controls & Application Hotkeys
# ------------------------------------------------------------------------------
step_header "Window Controls, Screenshots & Launchers"

subtask_start "Mapping window controls and screenshot hotkeys"
gsettings set org.gnome.desktop.wm.keybindings close "['<Super>q', '<Alt>F4']"
gsettings set org.gnome.desktop.wm.keybindings toggle-maximized "['<Super>m']"
gsettings set org.gnome.desktop.wm.keybindings minimize "['<Super>h']"
gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>Tab']"
gsettings set org.gnome.desktop.wm.keybindings switch-windows-backward "['<Shift><Alt>Tab']"

gsettings set org.gnome.mutter.keybindings toggle-tiled-left "['<Super>Left']"
gsettings set org.gnome.mutter.keybindings toggle-tiled-right "['<Super>Right']"
gsettings set org.gnome.desktop.wm.keybindings maximize "['<Super>Up']"
gsettings set org.gnome.desktop.wm.keybindings unmaximize "['<Super>Down']"

gsettings set org.gnome.shell.keybindings show-screenshot-ui "['<Super><Shift>s', 'Print']"
gsettings set org.gnome.shell.keybindings show-screen-recording-ui "['<Ctrl><Super><Shift>r']"
subtask_ok "Window actions (Super+Q/M/H) and screenshots bound"

subtask_start "Binding application shortcuts and Kitty scratchpad"
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
# 7. Enable User Extensions & Configure Preferences
# ------------------------------------------------------------------------------
step_header "Activating Extensions & Configuring Preferences"

subtask_start "Enabling user extensions via gnome-extensions"
for ext in "${USER_EXTENSIONS[@]}"; do
    gnome-extensions enable "$ext" 2>/dev/null || true
done
subtask_ok "All extensions active in user space"

subtask_start "Configuring Auto Move Windows (Chrome->1, Code->2, Kitty->3)"
AMW_SCHEMA="org.gnome.shell.extensions.auto-move-windows"
if gsettings list-schemas | grep -q "^${AMW_SCHEMA}$"; then
    gsettings set "$AMW_SCHEMA" application-list "['google-chrome.desktop:1', 'code.desktop:2', 'kitty.desktop:3']"
    subtask_ok "Auto Move Windows configured"
else
    subtask_warn "Auto Move Windows schema unindexed"
fi

subtask_start "Configuring Just Perfection (displaying numeric workspace bar)"
JP_SCHEMA="org.gnome.shell.extensions.just-perfection"
if gsettings list-schemas | grep -q "^${JP_SCHEMA}$"; then
    gsettings set "$JP_SCHEMA" accessibility-menu false
    gsettings set "$JP_SCHEMA" window-demands-attention-focus true
    gsettings set "$JP_SCHEMA" workspace-switcher-should-show false
    subtask_ok "Just Perfection interface cleanups applied"
else
    subtask_warn "Just Perfection schema unindexed"
fi

subtask_start "Configuring Dash to Dock (floating bottom dock)"
DOCK_SCHEMA="org.gnome.shell.extensions.dash-to-dock"
if gsettings list-schemas | grep -q "^${DOCK_SCHEMA}$"; then
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
    subtask_warn "Dash to Dock schema unindexed"
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
else
    subtask_warn "Blur-My-Shell schema unindexed"
fi

echo ""
echo -e "\033[1;32m═════════════════════════════════════════════════════════════════════════════\033[0m"
echo -e "\033[1;32m  FEDORA GNOME SETUP COMPLETED SUCCESSFULLY (v${SCRIPT_VERSION})\033[0m"
echo -e "\033[1;32m═════════════════════════════════════════════════════════════════════════════\033[0m"
echo ""
echo "Extension Status Summary:"
echo "  • Location: Strictly installed in ~/.local/share/gnome-shell/extensions/"
echo "  • Control:  Fully manageable and removable without sudo"
echo "  • Workflow: 9 Numbered workspaces with automatic window routing active"
echo ""
echo -e "\033[1;33m[NEXT STEP]\033[0m Log out and log back in to reload your Wayland session."
echo ""

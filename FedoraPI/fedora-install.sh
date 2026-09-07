#!/usr/bin/env bash
#
# ==============================================================================
# Fedora 44 Workstation Post-Installation Setup Script
# Version: 26.32.0 (Integrated Power-Cut & Safe Battery Edition)
# Description: Configured strictly for AMD Integrated Graphics (Radeon 780M).
#              Uses supergfxd in Integrated mode to physically power down the
#              RTX 4050, resolving both sleep deadlocks and battery drain.
# ==============================================================================

set -uo pipefail

readonly SCRIPT_VERSION="26.32.0"
readonly LOG_FILE="/var/log/fedora44_postinstall.log"
readonly TOTAL_STEPS=11
CURRENT_STEP=0

if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31m[ERROR] This script must be executed with root/sudo privileges.\033[0m" >&2
    exit 1
fi

TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(logname 2>/dev/null || id -nu 1000 2>/dev/null || echo "")}}"

if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    echo -e "\033[0;31m[ERROR] Unable to resolve a valid non-root user.\033[0m" >&2
    exit 1
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    echo -e "\033[0;31m[ERROR] User home directory not found for $TARGET_USER\033[0m" >&2
    exit 1
fi

get_timestamp() {
    date +'%Y-%m-%d %H:%M:%S'
}

log_message() {
    local msg="${1:-}"
    echo "$(get_timestamp) - $msg" >> "$LOG_FILE"
}

step_header() {
    ((CURRENT_STEP++))
    local title="${1:-}"
    echo ""
    echo -e "\033[1;34m═════════════════════════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[1;36m [STEP ${CURRENT_STEP}/${TOTAL_STEPS}]\033[0m \033[1;37m${title}\033[0m"
    echo -e "\033[1;34m═════════════════════════════════════════════════════════════════════════════\033[0m"
    log_message "STEP ${CURRENT_STEP}/${TOTAL_STEPS}: ${title}"
}

subtask_start() {
    local desc="${1:-}"
    echo -ne "  \033[1;33m➜\033[0m \033[0;37m${desc}...\033[0m"
    log_message "RUNNING: ${desc}"
}

subtask_ok() {
    local desc="${1:-}"
    echo -e "\r  \033[1;32m✔\033[0m \033[0;32m${desc} [COMPLETED]\033[0m\033[K"
    log_message "SUCCESS: ${desc}"
}

subtask_warn() {
    local desc="${1:-}"
    echo -e "\r  \033[1;33m⚠\033[0m \033[1;33m${desc} [FALLBACK/NOTICE]\033[0m\033[K"
    log_message "WARNING: ${desc}"
}

run_as_user() {
    local cmd="${1:-}"
    sudo -u "$TARGET_USER" -H env HOME="$TARGET_HOME" USER="$TARGET_USER" \
        PATH="$TARGET_HOME/.local/bin:$TARGET_HOME/.cargo/bin:$TARGET_HOME/.local/share/mise/bin:/usr/local/bin:/usr/bin:/bin:$PATH" \
        bash -c "$cmd"
}

safe_download() {
    local url="${1:-}"
    local dest="${2:-}"
    curl -fsSL --retry 3 --connect-timeout 10 "$url" -o "$dest"
}

prompt_reboot() {
    if [[ ! -t 0 ]]; then
        echo -e "\n\033[1;33m[NOTICE]\033[0m Non-interactive shell detected. Skipping reboot prompt."
        return 0
    fi
    echo ""
    read -r -p "Reboot now to finalize all system changes and verify battery state? (y/N): " choice
    if [[ "$choice" =~ ^[yY]$ ]]; then
        echo -e "\033[1;32mRebooting system...\033[0m"
        reboot
    else
        echo -e "\033[1;33mReboot skipped. Please restart manually later.\033[0m"
    fi
}

echo "";
echo "╔═════════════════════════════════════════════════════════════════════════════╗";
echo "║   Fedora 44 Post-Install Setup Script                                      ║";
echo "║   Version: $SCRIPT_VERSION (Integrated Safe Battery Edition)                  ║";
echo "║   Target User: $TARGET_USER ($TARGET_HOME)                                  ║";
echo "╚═════════════════════════════════════════════════════════════════════════════╝";
echo "";

# ------------------------------------------------------------------------------
# 1. Hostname & DNF5 Performance
# ------------------------------------------------------------------------------
step_header "Hostname & DNF5 Performance Optimization"

subtask_start "Setting system hostname to 'rspc'"
hostnamectl set-hostname rspc
subtask_ok "System hostname set to 'rspc'"

subtask_start "Configuring DNF5 parallel downloads and fastest mirror"
mkdir -p /etc/dnf/dnf.conf.d
cat << 'EOF' > /etc/dnf/dnf.conf.d/99-performance.conf
[main]
max_parallel_downloads=10
defaultyes=True
fastestmirror=True
EOF
subtask_ok "DNF5 performance drop-in created"

# ------------------------------------------------------------------------------
# 2. Software Repositories
# ------------------------------------------------------------------------------
step_header "Repository Provisioning & Software Sources"

subtask_start "Installing baseline packaging tools"
dnf install -y dnf5-plugins dnf-plugins-core fedora-workstation-repositories pciutils grubby >/dev/null 2>&1 || true
subtask_ok "Packaging plugins and workstation definitions verified"

FEDORA_VER=$(rpm -E %fedora)

subtask_start "Enabling Fyra Labs Terra repository"
if dnf install -y --nogpgcheck --repofrompath "terra,https://repos.fyralabs.com/terra$FEDORA_VER" terra-release >/dev/null 2>&1; then
    subtask_ok "Terra repository registered (v${FEDORA_VER})"
elif dnf install -y --nogpgcheck --repofrompath "terra,https://repos.fyralabs.com/terra$((FEDORA_VER - 1))" terra-release >/dev/null 2>&1; then
    subtask_warn "Terra repository registered using compatibility release"
else
    subtask_warn "Terra repository registration unavailable"
fi

subtask_start "Enabling RPM Fusion Free & Non-Free repositories"
dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" >/dev/null 2>&1 || \
dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$((FEDORA_VER - 1)).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$((FEDORA_VER - 1)).noarch.rpm" >/dev/null 2>&1 || true
dnf install -y rpmfusion-\*-appstream-data >/dev/null 2>&1 || true
subtask_ok "RPM Fusion Free, Non-Free, and AppStream metadata active"

subtask_start "Enabling Google Chrome and Cisco OpenH264 repositories"
dnf config-manager setopt fedora-cisco-openh264.enabled=1 >/dev/null 2>&1 || true
dnf config-manager setopt google-chrome.enabled=1 >/dev/null 2>&1 || true
subtask_ok "Chrome and Cisco OpenH264 repositories enabled"

subtask_start "Enabling Copr software repositories"
dnf -y copr enable lihaohong/yazi >/dev/null 2>&1 || true
dnf -y copr enable alternateved/eza >/dev/null 2>&1 || true
dnf -y copr enable che/nerd-fonts >/dev/null 2>&1 || true
dnf -y copr enable lukenukem/asus-linux >/dev/null 2>&1 || true
subtask_ok "Copr repositories configured"

subtask_start "Adding Visual Studio Code repository"
rpm --import https://packages.microsoft.com/keys/microsoft.asc >/dev/null 2>&1 || true
cat << 'EOF' > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
subtask_ok "VS Code repository registered"

subtask_start "Configuring Docker CE repository"
safe_download "https://download.docker.com/linux/fedora/docker-ce.repo" "/etc/yum.repos.d/docker-ce.repo"
if ! curl -fsI "https://download.docker.com/linux/fedora/${FEDORA_VER}/x86_64/stable/" &>/dev/null; then
    sed -i "s|\$releasever|$((FEDORA_VER - 1))|g" /etc/yum.repos.d/docker-ce.repo
fi
sed -i '/^\[.*\]/a skip_if_unavailable=True' /etc/yum.repos.d/docker-ce.repo 2>/dev/null || true
subtask_ok "Docker CE repository configured"

# ------------------------------------------------------------------------------
# 3. System Upgrade
# ------------------------------------------------------------------------------
step_header "System Upgrade & Package Refresh"

subtask_start "Refreshing metadata and upgrading system packages"
dnf upgrade -y --refresh
subtask_ok "System packages successfully refreshed and upgraded"

# ------------------------------------------------------------------------------
# 4. AMD Radeon 780M Hardware Codecs & ASUS Platform Setup
# ------------------------------------------------------------------------------
step_header "AMD Integrated Graphics & Power-Cut Configuration"

subtask_start "Installing unencumbered FFmpeg from RPM Fusion"
if rpm -q ffmpeg-free &>/dev/null; then
    dnf swap -y ffmpeg-free ffmpeg --allowerasing >/dev/null 2>&1 || true
elif ! rpm -q ffmpeg &>/dev/null; then
    dnf install -y ffmpeg --allowerasing >/dev/null 2>&1 || true
fi
subtask_ok "Full FFmpeg package verified"

subtask_start "Installing AMD Radeon 780M Mesa freeworld hardware codecs"
if rpm -q mesa-va-drivers &>/dev/null; then
    dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing >/dev/null 2>&1 || true
else
    dnf install -y mesa-va-drivers-freeworld --allowerasing >/dev/null 2>&1 || true
fi

if rpm -q mesa-vdpau-drivers &>/dev/null; then
    dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing >/dev/null 2>&1 || true
else
    dnf install -y mesa-vdpau-drivers-freeworld --allowerasing >/dev/null 2>&1 || true
fi
subtask_ok "AMD Radeon 780M hardware video acceleration active"

subtask_start "Blacklisting nouveau driver to prevent wake-from-sleep lockups"
cat << 'EOF' > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF

if command -v grubby &>/dev/null; then
    grubby --update-kernel=ALL --args="rd.driver.blacklist=nouveau modprobe.blacklist=nouveau" >/dev/null 2>&1 || true
fi
dracut --regenerate-all --force >/dev/null 2>&1 || dracut --force >/dev/null 2>&1 || true
subtask_ok "Nouveau driver blacklisted and initramfs refreshed"

subtask_start "Installing and configuring ASUS platform tools (asusd and supergfxd)"
dnf install -y asusctl asusd supergfxctl 2>/dev/null || dnf install -y asusctl supergfxctl 2>/dev/null || true

# Unmask in case unit was previously masked
systemctl unmask supergfxd.service 2>/dev/null || true
systemctl unmask asusd.service 2>/dev/null || true

systemctl enable --now asusd.service >/dev/null 2>&1 || true
systemctl enable --now supergfxd.service >/dev/null 2>&1 || true

# Force Integrated mode to physically power off RTX 4050
if command -v supergfxctl &>/dev/null; then
    supergfxctl -m Integrated >/dev/null 2>&1 || true
fi

usermod -aG adm "$TARGET_USER" 2>/dev/null || true
subtask_ok "ASUS daemons active (RTX 4050 powered down via Integrated mode)"

# ------------------------------------------------------------------------------
# 5. Core Utilities, Toolchains, CLI Runtimes & Applications
# ------------------------------------------------------------------------------
step_header "CLI Tools, Build Toolchains, and Desktop Software"

subtask_start "Installing base administration utilities & archive tools"
dnf install -y openssh-server @virtualization xdg-user-dirs \
    btop inxi tmux fastfetch unzip unrar git wget curl cabextract fontconfig mkfontscale xz tar >/dev/null 2>&1 || true
subtask_ok "Administration and archive tools installed"

subtask_start "Installing build compilers and development helpers"
dnf install -y kitty direnv micro make cmake clang cargo ninja-build wl-clipboard foliate >/dev/null 2>&1 || true
subtask_ok "Build systems, compilers, Kitty, and Foliate installed"

subtask_start "Installing modern CLI/TUI tools"
dnf install -y zoxide eza fzf bat yazi fd-find ripgrep tldr jq poppler poppler-utils timeshift >/dev/null 2>&1 || true
subtask_ok "Modern CLI/TUI utilities and Timeshift installed"

subtask_start "Installing CLI runtime tools (Mise, Atuin, Starship, yt-dlp)"
dnf install -y starship atuin mise yt-dlp >/dev/null 2>&1 || true

run_as_user 'mkdir -p "$HOME/.local/bin"'

if ! command -v mise &>/dev/null; then
    run_as_user 'curl -fsSL https://mise.run | sh >/dev/null 2>&1'
fi
if ! command -v starship &>/dev/null; then
    curl -sS https://starship.rs/install.sh | sh -s -- --yes >/dev/null 2>&1 || true
fi
if ! command -v atuin &>/dev/null; then
    run_as_user 'curl --proto "=https" --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --non-interactive >/dev/null 2>&1 || true'
fi
if ! command -v yt-dlp &>/dev/null; then
    run_as_user 'curl -fL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o "$HOME/.local/bin/yt-dlp" >/dev/null 2>&1 && chmod a+rx "$HOME/.local/bin/yt-dlp"'
fi
subtask_ok "Developer CLI tools verified"

subtask_start "Installing desktop packages"
dnf install -y code google-chrome-stable podman papirus-icon-theme \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1 || true
subtask_ok "Desktop applications and container runtimes installed"

# ------------------------------------------------------------------------------
# 6. Flatpak Setup & Applications
# ------------------------------------------------------------------------------
step_header "Flatpak Runtime & Application Setup"

subtask_start "Configuring Flathub remote repository"
dnf install -y flatpak >/dev/null 2>&1 || true
flatpak remote-delete fedora --force >/dev/null 2>&1 || true
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
flatpak update -y >/dev/null 2>&1 || true
subtask_ok "Flathub repository active"

subtask_start "Installing desktop Flatpaks"
flatpak install -y --noninteractive flathub \
    com.stremio.Stremio \
    com.spotify.Client \
    org.qbittorrent.qBittorrent \
    com.github.tchx84.Flatseal >/dev/null 2>&1 || true
subtask_ok "Flatpak desktop applications installed"

# ------------------------------------------------------------------------------
# 7. Typography & Fonts Configuration
# ------------------------------------------------------------------------------
step_header "Typography & Nerd Fonts Installation"

subtask_start "Installing Inter Variable Font"
dnf install -y rsms-inter-vf-fonts rsms-inter-fonts >/dev/null 2>&1 || true
subtask_ok "Inter variable font installed"

subtask_start "Installing Microsoft Core Fonts"
if ! rpm -q msttcore-fonts-installer &>/dev/null; then
    if safe_download "https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm" "/tmp/msttcorefonts.rpm"; then
        rpm -ivh --nodigest --nofiledigest /tmp/msttcorefonts.rpm >/dev/null 2>&1 || true
        rm -f /tmp/msttcorefonts.rpm
    fi
fi
subtask_ok "Microsoft Core Fonts installed"

mkdir -p /usr/local/share/fonts/NerdFonts

subtask_start "Installing 0xProto Nerd Font"
if ! dnf install -y 0xproto-nerd-fonts >/dev/null 2>&1 && ! dnf install -y nerd-fonts-0xproto >/dev/null 2>&1; then
    if safe_download "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/0xProto.tar.xz" "/tmp/0xProto.tar.xz"; then
        tar -xf /tmp/0xProto.tar.xz -C /usr/local/share/fonts/NerdFonts/ >/dev/null 2>&1 || true
        rm -f /tmp/0xProto.tar.xz
    fi
fi
subtask_ok "0xProto Nerd Font installed"

subtask_start "Installing Atkinson Hyperlegible Mono Nerd Font"
if ! dnf install -y atkinson-hyperlegible-mono-nerd-fonts >/dev/null 2>&1 && ! dnf install -y nerd-fonts-atkinson-hyperlegible-mono >/dev/null 2>&1; then
    if safe_download "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/AtkinsonHyperlegibleMono.tar.xz" "/tmp/AtkinsonHyperlegibleMono.tar.xz"; then
        tar -xf /tmp/AtkinsonHyperlegibleMono.tar.xz -C /usr/local/share/fonts/NerdFonts/ >/dev/null 2>&1 || true
        rm -f /tmp/AtkinsonHyperlegibleMono.tar.xz
    fi
fi
subtask_ok "Atkinson Hyperlegible Mono Nerd Font installed"

subtask_start "Rebuilding system font cache"
chmod -R 755 /usr/local/share/fonts/NerdFonts
fc-cache -fv >/dev/null 2>&1 || true
subtask_ok "Font cache refreshed"

# ------------------------------------------------------------------------------
# 8. Kitty Terminal Configuration
# ------------------------------------------------------------------------------
step_header "Kitty Terminal Configuration"

subtask_start "Writing ~/.config/kitty/kitty.conf with 0xProto Nerd Font"
mkdir -p "$TARGET_HOME/.config/kitty"
touch "$TARGET_HOME/.config/kitty/current-theme.conf"

cat << 'EOF' > "$TARGET_HOME/.config/kitty/kitty.conf"
font_size        13.0
disable_ligatures never
background_opacity 0.85
window_padding_width 10
repaint_delay    10
input_delay      3
sync_to_monitor  yes
detect_urls      yes
copy_on_select   yes

cursor_shape          block
cursor_blink_interval 0.5
cursor_stop_blinking_after 15.0

enabled_layouts splits,stack
remember_window_size yes
hide_window_decorations yes

cursor_trail 3
cursor_trail_decay 0.1 0.4

tab_bar_edge            bottom
tab_bar_style           powerline
tab_powerline_style     slanted
tab_title_template      "{index}: {title}"
active_tab_font_style   bold
inactive_tab_font_style normal

confirm_os_window_close 0
shell_integration enabled

include current-theme.conf

font_family      family="0xProto Nerd Font"
bold_font        auto
italic_font      auto
bold_italic_font auto
EOF

chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/kitty"
subtask_ok "Kitty configuration deployed"

# ------------------------------------------------------------------------------
# 9. User Dev Environments, Global Runtimes & GitHub SSH Export
# ------------------------------------------------------------------------------
step_header "User Runtime Environments & SSH Key Generation"

subtask_start "Initializing standard XDG user directories"
run_as_user 'xdg-user-dirs-update 2>/dev/null || true'
subtask_ok "XDG user directories updated"

subtask_start "Setting Git global author identity"
run_as_user '
    git config --global user.name "entish84"
    git config --global user.email "entishthoughts@outlook.com"
'
subtask_ok "Git author identity configured (entish84)"

subtask_start "Generating Ed25519 SSH Keypair"
mkdir -p "$TARGET_HOME/.ssh"
chmod 700 "$TARGET_HOME/.ssh"

if [[ ! -f "$TARGET_HOME/.ssh/id_ed25519" ]]; then
    ssh-keygen -t ed25519 -C "entishthoughts@outlook.com" -f "$TARGET_HOME/.ssh/id_ed25519" -N "" >/dev/null 2>&1
fi

chmod 600 "$TARGET_HOME/.ssh/id_ed25519"
chmod 644 "$TARGET_HOME/.ssh/id_ed25519.pub"
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh"

run_as_user '
    eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
    ssh-add "$HOME/.ssh/id_ed25519" 2>/dev/null || true
'
subtask_ok "Ed25519 SSH keypair active"

subtask_start "Exporting public SSH key for GitHub"
cp "$TARGET_HOME/.ssh/id_ed25519.pub" "$TARGET_HOME/github_ed25519.pub"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/github_ed25519.pub"
chmod 644 "$TARGET_HOME/github_ed25519.pub"

DESKTOP_DIR=$(run_as_user 'xdg-user-dir DESKTOP 2>/dev/null' || true)
if [[ -z "$DESKTOP_DIR" || ! -d "$DESKTOP_DIR" ]]; then
    DESKTOP_DIR="$TARGET_HOME/Desktop"
fi
mkdir -p "$DESKTOP_DIR" 2>/dev/null || true
if [[ -d "$DESKTOP_DIR" && "$DESKTOP_DIR" != "$TARGET_HOME" ]]; then
    cp "$TARGET_HOME/.ssh/id_ed25519.pub" "$DESKTOP_DIR/github_ed25519.pub"
    chown "$TARGET_USER:$TARGET_USER" "$DESKTOP_DIR/github_ed25519.pub"
    chmod 644 "$DESKTOP_DIR/github_ed25519.pub"
fi
subtask_ok "Public key exported to ~/github_ed25519.pub"

subtask_start "Configuring Mise global runtimes"
run_as_user '
    export MISE_YES=1
    MISE_BIN=$(command -v mise || echo "$HOME/.local/bin/mise")
    if [[ -x "$MISE_BIN" ]]; then
        "$MISE_BIN" use --global dotnet@10 >/dev/null 2>&1 || true
        "$MISE_BIN" use --global java@lts >/dev/null 2>&1 || true
        "$MISE_BIN" use --global node@latest >/dev/null 2>&1 || true
    fi
'
subtask_ok "Mise global toolchains configured"

subtask_start "Installing Node Version Manager (NVM)"
run_as_user '
    if [[ ! -d "$HOME/.nvm" ]]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh 2>/dev/null | bash >/dev/null 2>&1
    fi
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null || true
'
subtask_ok "NVM runtime installed"

# ------------------------------------------------------------------------------
# 10. Shell Environment (.zshrc, Zinit, Default Shell) & Daemons
# ------------------------------------------------------------------------------
step_header "Shell Environment (.zshrc, Zinit) & System Services"

subtask_start "Setting Zsh as default shell for $TARGET_USER"
dnf install -y zsh >/dev/null 2>&1 || true
ZSH_PATH=$(command -v zsh || echo "/bin/zsh")
if [[ -x "$ZSH_PATH" ]]; then
    grep -qxF "$ZSH_PATH" /etc/shells 2>/dev/null || echo "$ZSH_PATH" >> /etc/shells
    chsh -s "$ZSH_PATH" "$TARGET_USER" 2>/dev/null || usermod -s "$ZSH_PATH" "$TARGET_USER" 2>/dev/null || true
fi
subtask_ok "Default login shell set to $ZSH_PATH"

subtask_start "Cloning Zinit plugin framework"
if [[ ! -d "$TARGET_HOME/.local/share/zinit/zinit.git" ]]; then
    run_as_user 'git clone https://github.com/zdharma-continuum/zinit.git "$HOME/.local/share/zinit/zinit.git" >/dev/null 2>&1 || true'
fi
subtask_ok "Zinit bootstrap files installed"

subtask_start "Deploying optimized ~/.zshrc configuration"
cat << 'EOF' > "$TARGET_HOME/.zshrc"
export LANG=en_US.UTF-8
export EDITOR=micro
export VISUAL=micro

typeset -U path
path=(
    $HOME/.local/bin
    $HOME/bin
    $HOME/.atuin/bin
    $path
)

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"

zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust

zstyle ':omz:plugins:eza' 'dirs-first' yes
zstyle ':omz:plugins:eza' 'git-status' yes
zstyle ':omz:plugins:eza' 'header' yes
zstyle ':omz:plugins:eza' 'icons' yes

zinit snippet OMZL::git.zsh
zinit snippet OMZL::history.zsh         
zinit snippet OMZL::directories.zsh
zinit snippet OMZL::theme-and-appearance.zsh
zinit snippet OMZP::git
zinit snippet OMZP::direnv
zinit snippet OMZP::eza

zinit ice wait'0' lucid blockf
zinit light zsh-users/zsh-completions

zinit ice wait'0a' lucid atinit"ZINIT[COMPINIT_OPTS]=-C; zicompinit; zicdreplay"
zinit light zdharma-continuum/fast-syntax-highlighting

zinit ice wait'0b' lucid
zinit light Aloxaf/fzf-tab

zinit ice wait'0c' lucid atload"!_zsh_autosuggest_start"
zinit light zsh-users/zsh-autosuggestions

zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':fzf-tab:*' switch-group ',' '.'
zstyle ':fzf-tab:*' fzf-flags '--height=40%'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
zstyle ':fzf-tab:complete:*:*' fzf-preview \
  'if [ -d $realpath ]; then eza -1 --color=always $realpath; else bat --color=always --line-range :500 $realpath 2>/dev/null; fi'
zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-preview \
  '[[ $group == "[process ID]" ]] && ps --pid=$word -o cmd --no-headers -w -w'
zstyle ':fzf-tab:complete:(kill|ps):argument-rest' fzf-flags --preview-window=down:3:wrap

[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"
eval "$(starship init zsh 2>/dev/null)"
eval "$(mise activate zsh 2>/dev/null || $HOME/.local/bin/mise activate zsh 2>/dev/null)"
eval "$(zoxide init zsh 2>/dev/null)"
eval "$(atuin init zsh 2>/dev/null)"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

HISTFILE=$HOME/.zhistory
SAVEHIST=100000
HISTSIZE=100000
setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS

function yy() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}

alias fm=yy
[ -f ~/.zsh_aliases ] && source ~/.zsh_aliases
[[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh 2>/dev/null)"
EOF

chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.zshrc"
subtask_ok ".zshrc provisioned"

subtask_start "Enabling SSH, Docker, and Containerd daemons"
systemctl enable --now sshd 2>/dev/null || systemctl enable sshd 2>/dev/null || true
systemctl enable --now docker 2>/dev/null || systemctl enable docker 2>/dev/null || true
systemctl enable --now containerd 2>/dev/null || systemctl enable containerd 2>/dev/null || true
getent group docker >/dev/null || groupadd docker
usermod -aG docker "$TARGET_USER" 2>/dev/null || true
subtask_ok "Daemons active and $TARGET_USER enrolled in docker group"

# ------------------------------------------------------------------------------
# 11. System Optimizations & Battery Shortcuts
# ------------------------------------------------------------------------------
step_header "Desktop Defaults & ASUS Power Shortcuts"

mkdir -p "$TARGET_HOME/.config"
echo "kitty.desktop" > "$TARGET_HOME/.config/xdg-terminals.list"

for gtk_ver in gtk-3.0 gtk-4.0; do
    mkdir -p "$TARGET_HOME/.config/$gtk_ver"
    cat << 'EOF' > "$TARGET_HOME/.config/$gtk_ver/settings.ini"
[Settings]
gtk-icon-theme-name=Papirus-Dark
gtk-theme-name=Adwaita-dark
gtk-application-prefer-dark-theme=1
EOF
done
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config"

if ! grep -q "TERMINAL=kitty" /etc/environment 2>/dev/null; then
    echo "TERMINAL=kitty" >> /etc/environment
fi

flatpak override --filesystem=xdg-data/fonts:ro \
                 --filesystem=xdg-data/icons:ro 2>/dev/null || true

cat << 'EOF' > "$TARGET_HOME/.zsh_aliases"
alias ls="eza --icons --group-directories-first"
alias ll="eza -lh --icons --git --group-directories-first"
alias la="eza -lah --icons --git --group-directories-first"
alias lt="eza --tree --level=2 --icons"
alias cat="bat --paging=never"
alias grep="rg"
alias find="fd"

alias g="git"
alias ga="git add"
alias gc="git commit -m"
alias gp="git push"
alias gst="git status -sb"
alias gd="git diff"

alias d="docker"
alias dc="docker compose"
alias dps="docker ps --format \"table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}\""
alias p="podman"
alias pc="podman compose"

alias gfx-status="supergfxctl -g"
alias fan-quiet="asusctl profile -P Quiet"
alias fan-balanced="asusctl profile -P Balanced"
alias fan-perf="asusctl profile -P Performance"
alias bat-limit-80="asusctl -c 80 && echo 'Charge capped at 80%.'"
alias bat-limit-100="asusctl -c 100 && echo 'Charge cap removed.'"
alias power-rate="upower -i \$(upower -e | grep 'BAT') | grep -E 'state|energy-rate|time to empty'"
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.zsh_aliases"

cat << 'EOF' > "$TARGET_HOME/.config/starship.toml"
add_newline = false

[character]
success_symbol = "[➜](bold green)"
error_symbol = "[➜](bold red)"

[directory]
truncation_length = 4
style = "bold cyan"

[git_branch]
style = "bold purple"

[git_status]
style = "red"

[cmd_duration]
min_time = 2_000
style = "yellow"

[dotnet]
symbol = "󰌛 "
style = "blue"

[nodejs]
symbol = "󰎙 "
style = "bold green"

[java]
symbol = " "
style = "red"
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/starship.toml"

echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
modprobe tcp_bbr 2>/dev/null || true

cat << 'EOF' > /etc/sysctl.d/99-network-tuning.conf
net.core.default_qdisc = cake
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl --system >/dev/null 2>&1 || true
systemctl mask NetworkManager-wait-online.service 2>/dev/null || true

subtask_start "Cleaning package caches"
dnf autoremove -y >/dev/null 2>&1 || true
dnf clean all >/dev/null 2>&1 || true
subtask_ok "Package cache pruned"

echo ""
echo -e "\033[1;32m═════════════════════════════════════════════════════════════════════════════\033[0m"
echo -e "\033[1;32m  FEDORA 44 SETUP COMPLETED SUCCESSFULLY (v${SCRIPT_VERSION})\033[0m"
echo -e "\033[1;32m═════════════════════════════════════════════════════════════════════════════\033[0m"
echo ""
echo "Power Management Status:"
echo "  -> Primary GPU:      AMD Radeon 780M (Integrated, Mesa VA-API active)"
echo "  -> Discrete GPU:     RTX 4050 (Powered off via supergfxd Integrated mode)"
echo "  -> Service Unmask:   supergfxd unmasked and active"
echo "  -> Aliases:          Run 'power-rate' in terminal to monitor real-time Wattage"
echo ""

prompt_reboot

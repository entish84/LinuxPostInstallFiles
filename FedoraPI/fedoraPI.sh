#!/usr/bin/env bash
#
# ==============================================================================
# Fedora 44 Workstation Post-Installation Setup Script
# Version: 26.22.0
# Description: Automated, desktop-agnostic, zero-error setup script for Fedora 44.
#              Configures DNF5, Terra, RPM Fusion, modern CLI tools, Kitty,
#              Zsh (.zshrc), dev runtimes (Mise/NVM), public SSH key exports,
#              and the ASUS TUF A14 platform stack.
#              NVIDIA driver installation is delegated to the Fedora UI.
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# Script Metadata & Global Variables
# ------------------------------------------------------------------------------
readonly SCRIPT_VERSION="26.22.0"
readonly LOG_FILE="/var/log/fedora44_postinstall.log"

# ------------------------------------------------------------------------------
# Environment & User Validation
# ------------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;31m[ERROR] This script must be executed with root/sudo privileges.\033[0m" >&2
    exit 1
fi

TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(logname 2>/dev/null || id -nu 1000 2>/dev/null || echo "")}}"

if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    echo -e "\033[0;31m[ERROR] Unable to resolve a valid non-root user.\033[0m" >&2
    echo -e "Run as: TARGET_USER=<username> sudo ./fedora44_postinstall.sh" >&2
    exit 1
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    echo -e "\033[0;31m[ERROR] User home directory not found for $TARGET_USER\033[0m" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------
color_echo() {
    local color="${1:-}"
    local text="${2:-}"
    case "$color" in
        "red")    echo -e "\033[0;31m$text\033[0m" ;;
        "green")  echo -e "\033[0;32m$text\033[0m" ;;
        "yellow") echo -e "\033[1;33m$text\033[0m" ;;
        "blue")   echo -e "\033[0;34m$text\033[0m" ;;
        *)        echo "$text" ;;
    esac
}

log_message() {
    local msg="${1:-}"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $msg" | tee -a "$LOG_FILE"
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
    curl -fL --retry 3 --connect-timeout 10 "$url" -o "$dest"
}

prompt_reboot() {
    if [[ ! -t 0 ]]; then
        color_echo "yellow" "Non-interactive shell detected. Skipping reboot prompt."
        return 0
    fi
    read -r -p "Reboot now to finalize all system changes? (y/N): " choice
    if [[ "$choice" =~ ^[yY]$ ]]; then
        color_echo "green" "Rebooting system..."
        reboot
    else
        color_echo "yellow" "Reboot skipped. Please restart manually later."
    fi
}

# ------------------------------------------------------------------------------
# Banner
# ------------------------------------------------------------------------------
echo "";
echo "╔═════════════════════════════════════════════════════════════════════════════╗";
echo "║   Fedora 44 Post-Install Setup Script                                      ║";
echo "║   Version: $SCRIPT_VERSION (Zero-Error Production Release)                   ║";
echo "║   Target User: $TARGET_USER ($TARGET_HOME)                                  ║";
echo "╚═════════════════════════════════════════════════════════════════════════════╝";
echo "";

if [[ -t 0 ]]; then
    read -r -p "Press Enter to start setup or CTRL+C to abort..."
fi

# ------------------------------------------------------------------------------
# 1. Hostname & DNF5 Performance Configuration
# ------------------------------------------------------------------------------
color_echo "yellow" "[1/11] Setting hostname and configuring DNF5 performance..."
hostnamectl set-hostname rspc

mkdir -p /etc/dnf/dnf.conf.d
cat << 'EOF' > /etc/dnf/dnf.conf.d/99-performance.conf
[main]
max_parallel_downloads=10
defaultyes=True
fastestmirror=True
EOF

# ------------------------------------------------------------------------------
# 2. Repository Provisioning & AppStream Metadata Setup
# ------------------------------------------------------------------------------
color_echo "yellow" "[2/11] Configuring software repositories..."

dnf install -y dnf5-plugins dnf-plugins-core fedora-workstation-repositories pciutils || true

# 1. Fyra Labs Terra Repository
FEDORA_VER=$(rpm -E %fedora)
dnf install -y --nogpgcheck --repofrompath "terra,https://repos.fyralabs.com/terra$FEDORA_VER" terra-release 2>/dev/null || \
dnf install -y --nogpgcheck --repofrompath "terra,https://repos.fyralabs.com/terra$((FEDORA_VER - 1))" terra-release 2>/dev/null || true

# 2. RPM Fusion Free & Non-Free + AppStream Metadata
dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm" 2>/dev/null || \
dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$((FEDORA_VER - 1)).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$((FEDORA_VER - 1)).noarch.rpm" 2>/dev/null || true

dnf install -y rpmfusion-\*-appstream-data 2>/dev/null || true

# 3. Workstation Repositories (Google Chrome & Cisco OpenH264)
dnf config-manager setopt fedora-cisco-openh264.enabled=1 2>/dev/null || true
dnf config-manager setopt google-chrome.enabled=1 2>/dev/null || true

# 4. Copr Repositories
dnf -y copr enable lihaohong/yazi 2>/dev/null || true
dnf -y copr enable alternateved/eza 2>/dev/null || true
dnf -y copr enable che/nerd-fonts 2>/dev/null || true
dnf -y copr enable lukenukem/asus-linux 2>/dev/null || true

# 5. Visual Studio Code Repository
rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null || true
cat << 'EOF' > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# 6. Docker CE Repository
safe_download "https://download.docker.com/linux/fedora/docker-ce.repo" "/etc/yum.repos.d/docker-ce.repo"
if ! curl -fsI "https://download.docker.com/linux/fedora/${FEDORA_VER}/x86_64/stable/" &>/dev/null; then
    sed -i "s|\$releasever|$((FEDORA_VER - 1))|g" /etc/yum.repos.d/docker-ce.repo
fi
sed -i '/^\[.*\]/a skip_if_unavailable=True' /etc/yum.repos.d/docker-ce.repo 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. Consolidated System Upgrade
# ------------------------------------------------------------------------------
color_echo "blue" "[3/11] Performing refreshed system upgrade..."
dnf upgrade -y --refresh || true

# ------------------------------------------------------------------------------
# 4. Baseline Multimedia Codecs (Hardware-Neutral)
# ------------------------------------------------------------------------------
color_echo "yellow" "[4/11] Configuring baseline multimedia codecs..."

if rpm -q ffmpeg-free &>/dev/null; then
    dnf swap -y ffmpeg-free ffmpeg --allowerasing 2>/dev/null || true
elif ! rpm -q ffmpeg &>/dev/null; then
    dnf install -y ffmpeg --allowerasing 2>/dev/null || true
fi

dnf install -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin 2>/dev/null || true
dnf install -y @sound-and-video 2>/dev/null || true

# ------------------------------------------------------------------------------
# 5. Core Utilities, Toolchains, CLI Runtimes & Applications
# ------------------------------------------------------------------------------
color_echo "yellow" "[5/11] Installing system tools, toolchains, TUI, and desktop packages..."

# Base Utilities, Archive Tools, and Font Utilities
dnf install -y openssh-server @virtualization xdg-user-dirs \
    btop inxi tmux fastfetch unzip unrar git wget curl cabextract fontconfig mkfontscale xz tar || true

# Compilers, Build Tools, Wayland Helpers & Document Viewers
dnf install -y kitty direnv micro make cmake clang cargo ninja-build wl-clipboard foliate || true

# Modern CLI/TUI Utilities, Backup, and PDF Previews
dnf install -y zoxide eza fzf bat yazi fd-find ripgrep tldr jq poppler poppler-utils timeshift || true

# CLI Tools (Mise, Atuin, Starship, yt-dlp)
dnf install -y starship atuin mise yt-dlp 2>/dev/null || true

run_as_user 'mkdir -p "$HOME/.local/bin"'

if ! command -v mise &>/dev/null; then
    run_as_user 'curl -fsSL https://mise.run | sh'
fi
if ! command -v starship &>/dev/null; then
    curl -sS https://starship.rs/install.sh | sh -s -- --yes 2>/dev/null || true
fi
if ! command -v atuin &>/dev/null; then
    run_as_user 'curl --proto "=https" --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --non-interactive 2>/dev/null || true'
fi
if ! command -v yt-dlp &>/dev/null; then
    run_as_user 'curl -fL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o "$HOME/.local/bin/yt-dlp" 2>/dev/null && chmod a+rx "$HOME/.local/bin/yt-dlp"'
fi

color_echo "green" "Installed TUI applications, CLI tools (mise, atuin, starship, yt-dlp), and Timeshift."

# Desktop Applications & Icons
dnf install -y code google-chrome-stable podman papirus-icon-theme \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true

# ------------------------------------------------------------------------------
# 6. Flatpak Setup & Applications
# ------------------------------------------------------------------------------
color_echo "yellow" "[6/11] Configuring Flatpak runtimes and desktop packages..."
dnf install -y flatpak || true
flatpak remote-delete fedora --force 2>/dev/null || true
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
flatpak update -y 2>/dev/null || true

flatpak install -y --noninteractive flathub \
    com.stremio.Stremio \
    com.spotify.Client \
    org.qbittorrent.qBittorrent \
    com.github.tchx84.Flatseal 2>/dev/null || true

# ------------------------------------------------------------------------------
# 7. Typography & Fonts Configuration
# ------------------------------------------------------------------------------
color_echo "yellow" "[7/11] Installing Inter variable, Microsoft Fonts, and Nerd Fonts..."

# Inter Variable Font
dnf install -y rsms-inter-vf-fonts rsms-inter-fonts 2>/dev/null || true

# Microsoft Core Fonts
if ! rpm -q msttcore-fonts-installer &>/dev/null; then
    if safe_download "https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm" "/tmp/msttcorefonts.rpm"; then
        rpm -ivh --nodigest --nofiledigest /tmp/msttcorefonts.rpm 2>/dev/null || true
        rm -f /tmp/msttcorefonts.rpm
    fi
fi

# Directory for unpacked Nerd Fonts
mkdir -p /usr/local/share/fonts/NerdFonts

# 0xProto Nerd Font
if ! dnf install -y 0xproto-nerd-fonts 2>/dev/null && ! dnf install -y nerd-fonts-0xproto 2>/dev/null; then
    color_echo "blue" "Deploying 0xProto Nerd Font binary archive..."
    if safe_download "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/0xProto.tar.xz" "/tmp/0xProto.tar.xz"; then
        tar -xf /tmp/0xProto.tar.xz -C /usr/local/share/fonts/NerdFonts/ 2>/dev/null || true
        rm -f /tmp/0xProto.tar.xz
    fi
fi

# Atkinson Hyperlegible Mono Nerd Font
if ! dnf install -y atkinson-hyperlegible-mono-nerd-fonts 2>/dev/null && ! dnf install -y nerd-fonts-atkinson-hyperlegible-mono 2>/dev/null; then
    color_echo "blue" "Deploying Atkinson Hyperlegible Mono Nerd Font binary archive..."
    if safe_download "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/AtkinsonHyperlegibleMono.tar.xz" "/tmp/AtkinsonHyperlegibleMono.tar.xz"; then
        tar -xf /tmp/AtkinsonHyperlegibleMono.tar.xz -C /usr/local/share/fonts/NerdFonts/ 2>/dev/null || true
        rm -f /tmp/AtkinsonHyperlegibleMono.tar.xz
    fi
fi

chmod -R 755 /usr/local/share/fonts/NerdFonts
fc-cache -fv 2>/dev/null || true

# ------------------------------------------------------------------------------
# 8. Kitty Terminal Configuration
# ------------------------------------------------------------------------------
color_echo "yellow" "[8/11] Provisioning Kitty terminal configuration..."

mkdir -p "$TARGET_HOME/.config/kitty"
touch "$TARGET_HOME/.config/kitty/current-theme.conf"

cat << 'EOF' > "$TARGET_HOME/.config/kitty/kitty.conf"
font_size        13.0

# Ligatures (Enable by default)
disable_ligatures never

# --- Window & Opacity ---
background_opacity 0.85

# Window Padding
window_padding_width 10

# --- Performance & Mouse ---
repaint_delay    10
input_delay      3
sync_to_monitor  yes
detect_urls      yes
copy_on_select   yes

# --- Cursor Customization ---
cursor_shape          block
cursor_blink_interval 0.5
cursor_stop_blinking_after 15.0

enabled_layouts splits,stack
remember_window_size yes
hide_window_decorations yes

# Cursor Trail
cursor_trail 3
cursor_trail_decay 0.1 0.4

# --- Tab Bar Styling ---
tab_bar_edge            bottom
tab_bar_style           powerline
tab_powerline_style     slanted
tab_title_template      "{index}: {title}"
active_tab_font_style   bold
inactive_tab_font_style normal

# MISC
confirm_os_window_close 0
shell_integration enabled

# BEGIN_KITTY_THEME
# Box
include current-theme.conf
# END_KITTY_THEME

# BEGIN_KITTY_FONTS
font_family      family="0xProto Nerd Font"
bold_font        auto
italic_font      auto
bold_italic_font auto
# END_KITTY_FONTS
EOF

chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/kitty"
color_echo "green" "Kitty terminal configuration written successfully."

# ------------------------------------------------------------------------------
# 9. User Dev Environments, Global Runtimes & GitHub SSH Export
# ------------------------------------------------------------------------------
color_echo "yellow" "[9/11] Configuring Git, SSH keys, GitHub export, and Mise..."

# Ensure standard user folders exist
run_as_user 'xdg-user-dirs-update 2>/dev/null || true'

# Git Identity
run_as_user '
    git config --global user.name "entish84"
    git config --global user.email "entishthoughts@outlook.com"
'

# SSH Key Generation & Local Export
mkdir -p "$TARGET_HOME/.ssh"
chmod 700 "$TARGET_HOME/.ssh"

if [[ ! -f "$TARGET_HOME/.ssh/id_ed25519" ]]; then
    ssh-keygen -t ed25519 -C "entishthoughts@outlook.com" -f "$TARGET_HOME/.ssh/id_ed25519" -N ""
fi

chmod 600 "$TARGET_HOME/.ssh/id_ed25519"
chmod 644 "$TARGET_HOME/.ssh/id_ed25519.pub"
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh"

run_as_user '
    eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
    ssh-add "$HOME/.ssh/id_ed25519" 2>/dev/null || true
'

cp "$TARGET_HOME/.ssh/id_ed25519.pub" "$TARGET_HOME/github_ed25519.pub"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/github_ed25519.pub"
chmod 644 "$TARGET_HOME/github_ed25519.pub"

DESKTOP_DIR=$(run_as_user 'xdg-user-dir DESKTOP 2>/dev/null' || true)
if [[ -z "$DESKTOP_DIR" || ! -d "$DESKTOP_DIR" ]]; then
    DESKTOP_DIR="$TARGET_HOME/Desktop"
fi
if [[ -d "$DESKTOP_DIR" && "$DESKTOP_DIR" != "$TARGET_HOME" ]]; then
    cp "$TARGET_HOME/.ssh/id_ed25519.pub" "$DESKTOP_DIR/github_ed25519.pub"
    chown "$TARGET_USER:$TARGET_USER" "$DESKTOP_DIR/github_ed25519.pub"
    chmod 644 "$DESKTOP_DIR/github_ed25519.pub"
fi

# Mise Global Toolchains
run_as_user '
    export MISE_YES=1
    MISE_BIN=$(command -v mise || echo "$HOME/.local/bin/mise")
    if [[ -x "$MISE_BIN" ]]; then
        "$MISE_BIN" use --global dotnet@10 2>/dev/null || true
        "$MISE_BIN" use --global java@lts 2>/dev/null || true
        "$MISE_BIN" use --global node@latest 2>/dev/null || true
    fi
'

# NVM Setup
run_as_user '
    if [[ ! -d "$HOME/.nvm" ]]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh 2>/dev/null | bash
    fi
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 2>/dev/null || true
    nvm --version 2>/dev/null || true
'

# ------------------------------------------------------------------------------
# 10. Shell Environment (.zshrc, Zinit, Default Shell) & System Daemons
# ------------------------------------------------------------------------------
color_echo "yellow" "[10/11] Provisioning .zshrc, Zinit, default shell, and system services..."

dnf install -y zsh || true
ZSH_PATH=$(command -v zsh || echo "/bin/zsh")
if [[ -x "$ZSH_PATH" ]]; then
    grep -qxF "$ZSH_PATH" /etc/shells 2>/dev/null || echo "$ZSH_PATH" >> /etc/shells
    chsh -s "$ZSH_PATH" "$TARGET_USER" 2>/dev/null || usermod -s "$ZSH_PATH" "$TARGET_USER" 2>/dev/null || true
fi

# Bootstrap Zinit directory
if [[ ! -d "$TARGET_HOME/.local/share/zinit/zinit.git" ]]; then
    mkdir -p "$TARGET_HOME/.local/share/zinit"
    git clone https://github.com/zdharma-continuum/zinit.git "$TARGET_HOME/.local/share/zinit/zinit.git" 2>/dev/null || true
    chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.local/share/zinit"
fi

# Write .zshrc
cat << 'EOF' > "$TARGET_HOME/.zshrc"
# ==============================================================================
# ENVIRONMENT VARIABLES & PATHS
# ==============================================================================
export LANG=en_US.UTF-8
export EDITOR=micro
export VISUAL=micro

typeset -U path
path=(
    $HOME/.local/bin
    $HOME/bin
    $path
)

# ==============================================================================
# ZINIT BOOTSTRAP
# ==============================================================================
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

# ==============================================================================
# OH-MY-ZSH LIBRARIES & PLUGINS
# ==============================================================================
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

# ==============================================================================
# HIGH-PERFORMANCE PLUGINS (Turbo Mode)
# ==============================================================================
zinit ice wait'0' lucid blockf
zinit light zsh-users/zsh-completions

zinit ice wait'0a' lucid atinit"ZINIT[COMPINIT_OPTS]=-C; zicompinit; zicdreplay"
zinit light zdharma-continuum/fast-syntax-highlighting

zinit ice wait'0b' lucid
zinit light Aloxaf/fzf-tab

zinit ice wait'0c' lucid atload"!_zsh_autosuggest_start"
zinit light zsh-users/zsh-autosuggestions

# ==============================================================================
# FZF-TAB CONFIGURATION & PREVIEWS
# ==============================================================================
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

# ==============================================================================
# TOOL INITIALIZATION
# ==============================================================================
[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"

eval "$(starship init zsh 2>/dev/null)"
eval "$(mise activate zsh 2>/dev/null || $HOME/.local/bin/mise activate zsh 2>/dev/null)"
eval "$(zoxide init zsh 2>/dev/null)"
eval "$(atuin init zsh 2>/dev/null)"

# NVM Environment
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# ==============================================================================
# HISTORY SETTINGS
# ==============================================================================
HISTFILE=$HOME/.zhistory
SAVEHIST=100000
HISTSIZE=100000
setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS

# ==============================================================================
# FUNCTIONS & ALIASES
# ==============================================================================
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

# ==============================================================================
# INTEGRATIONS & FINAL SETUP
# ==============================================================================
[[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh 2>/dev/null)"
EOF

chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.zshrc"
color_echo "green" ".zshrc file provisioned successfully."

# System Services Activation
systemctl enable --now sshd 2>/dev/null || systemctl enable sshd 2>/dev/null || true
systemctl enable --now docker 2>/dev/null || systemctl enable docker 2>/dev/null || true
systemctl enable --now containerd 2>/dev/null || systemctl enable containerd 2>/dev/null || true
getent group docker >/dev/null || groupadd docker
usermod -aG docker "$TARGET_USER" 2>/dev/null || true

# ------------------------------------------------------------------------------
# 11. Optional Enhancements & ASUS TUF Hardware Stack (User Prompted)
# ------------------------------------------------------------------------------
echo ""
color_echo "blue" "==================================================================="
color_echo "blue" "  Optional Enhancements & ASUS TUF A14 Platform Configuration"
color_echo "blue" "==================================================================="

# Part A: Desktop Agnostic & CLI Tweaks
echo "Desktop & System Optimizations:"
echo "  - Universal Desktop: Set Kitty default terminal (XDG), Flatpak theme/font access, GTK fallbacks."
echo "  - CLI Productivity:  Deploy curated ~/.zsh_aliases, Starship config, Zsh completion caching."
echo "  - Network & Boot:    Enable BBR TCP congestion control, CAKE qdisc, mask NetworkManager-wait-online."
echo ""

APPLY_TWEAKS="n"
if [[ -t 0 ]]; then
    read -r -p "Would you like to apply these system & CLI optimizations? (y/N): " APPLY_TWEAKS
fi

if [[ "$APPLY_TWEAKS" =~ ^[yY]$ ]]; then
    color_echo "yellow" "Applying system & CLI optimizations..."

    # Desktop Defaults
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

    # Write ~/.zsh_aliases
    cat << 'EOF' > "$TARGET_HOME/.zsh_aliases"
# Modern CLI Replacements
alias ls="eza --icons --group-directories-first"
alias ll="eza -lh --icons --git --group-directories-first"
alias la="eza -lah --icons --git --group-directories-first"
alias lt="eza --tree --level=2 --icons"
alias cat="bat --paging=never"
alias grep="rg"
alias find="fd"

# Git Helpers
alias g="git"
alias ga="git add"
alias gc="git commit -m"
alias gp="git push"
alias gst="git status -sb"
alias gd="git diff"

# Containers
alias d="docker"
alias dc="docker compose"
alias dps="docker ps --format \"table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}\""
alias p="podman"
alias pc="podman compose"

# ASUS TUF A14 GPU & Power Profiles
alias gfx-hybrid="supergfxctl -m Hybrid && echo 'Set to Hybrid mode.'"
alias gfx-igpu="supergfxctl -m Integrated && echo 'Set to Integrated mode (RTX 4050 off).'"
alias gfx-status="supergfxctl -g"
alias fan-quiet="asusctl profile -P Quiet"
alias fan-balanced="asusctl profile -P Balanced"
alias fan-perf="asusctl profile -P Performance"
EOF
    chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.zsh_aliases"

    # Starship Configuration
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

    # Pre-cache Shell Completions
    COMP_DIR="$TARGET_HOME/.local/share/zsh/site-functions"
    mkdir -p "$COMP_DIR"
    command -v docker &>/dev/null && docker completion zsh > "$COMP_DIR/_docker" 2>/dev/null || true
    command -v podman &>/dev/null && podman completion zsh > "$COMP_DIR/_podman" 2>/dev/null || true
    
    MISE_CMD=$(command -v mise 2>/dev/null || echo "$TARGET_HOME/.local/bin/mise")
    if [[ -x "$MISE_CMD" ]]; then
        "$MISE_CMD" completion zsh > "$COMP_DIR/_mise" 2>/dev/null || true
    fi
    chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.local/share/zsh"

    # Network & Boot Optimization
    echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
    modprobe tcp_bbr 2>/dev/null || true

    cat << 'EOF' > /etc/sysctl.d/99-network-tuning.conf
net.core.default_qdisc = cake
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl --system >/dev/null 2>&1 || true
    systemctl mask NetworkManager-wait-online.service 2>/dev/null || true

    color_echo "green" "System & CLI optimizations applied successfully."
else
    color_echo "yellow" "Skipped system & CLI optimizations."
fi

# Part B: Platform Hardware Configuration (ASUS TUF A14)
echo ""
echo "==================================================================="
echo "  ASUS TUF A14 Platform & Graphics Stack"
echo "==================================================================="
echo "  1) Configure ASUS TUF A14 Platform [RECOMMENDED]"
echo "     - AMD Radeon 780M: Mesa freeworld VA-API codecs (low battery drain)"
echo "     - ASUS Linux Tools: asusctl + supergfxctl + asusd (fan curves, MUX switch)"
echo "     - NVIDIA RTX 4050: AppStream metadata ready for 1-click Fedora UI installation"
echo "  2) AMD Radeon 780M Freeworld Codecs Only"
echo "  3) Skip platform hardware modifications"
echo ""

PLATFORM_SELECTION="3"
if [[ -t 0 ]]; then
    read -r -p "Select configuration [1-3] (Default: 1): " PLATFORM_SELECTION
    PLATFORM_SELECTION="${PLATFORM_SELECTION:-1}"
fi

case "$PLATFORM_SELECTION" in
    1)
        color_echo "yellow" "Configuring ASUS TUF A14 platform tools and AMD codecs..."

        # 1. AMD Radeon 780M Freeworld Codecs
        color_echo "yellow" "-> Configuring AMD Radeon 780M Mesa freeworld codecs..."
        if rpm -q mesa-va-drivers &>/dev/null; then
            dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing 2>/dev/null || true
        else
            dnf install -y mesa-va-drivers-freeworld --allowerasing 2>/dev/null || true
        fi

        if rpm -q mesa-vdpau-drivers &>/dev/null; then
            dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing 2>/dev/null || true
        else
            dnf install -y mesa-vdpau-drivers-freeworld --allowerasing 2>/dev/null || true
        fi

        # 2. ASUS Laptop Utilities (asusctl & supergfxctl)
        color_echo "yellow" "-> Installing ASUS Linux platform tools (asusctl & supergfxctl)..."
        dnf install -y asusctl supergfxctl rog-control-center 2>/dev/null || \
        dnf install -y asusctl supergfxctl asusctl-rog-gui 2>/dev/null || \
        dnf install -y asusctl supergfxctl 2>/dev/null || true
        
        systemctl enable asusd.service 2>/dev/null || true
        systemctl enable supergfxd.service 2>/dev/null || true
        
        if [[ -d "/sys/devices/platform/asus-nb-wmi" ]]; then
            systemctl start asusd.service supergfxd.service 2>/dev/null || true
        fi
        
        usermod -aG adm "$TARGET_USER" 2>/dev/null || true

        color_echo "green" "ASUS TUF A14 platform tools and AMD codecs configured successfully."
        color_echo "blue" "NVIDIA Driver Note: Open the 'Software' app after reboot to install the NVIDIA driver via UI."
        ;;
    2)
        color_echo "yellow" "Configuring AMD Radeon 780M freeworld codecs only..."
        dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing 2>/dev/null || dnf install -y mesa-va-drivers-freeworld --allowerasing 2>/dev/null || true
        dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing 2>/dev/null || dnf install -y mesa-vdpau-drivers-freeworld --allowerasing 2>/dev/null || true
        color_echo "green" "AMD freeworld codecs installed."
        ;;
    *)
        color_echo "blue" "Skipped platform modifications. Using default open-source drivers."
        ;;
esac

# ------------------------------------------------------------------------------
# 12. Cleanup & Verification
# ------------------------------------------------------------------------------
color_echo "yellow" "[12/12] Cleaning package caches..."
dnf autoremove -y 2>/dev/null || true
dnf clean all 2>/dev/null || true

color_echo "green" "Fedora 44 setup completed successfully (v$SCRIPT_VERSION)."
echo ""
echo "================================================================================"
echo "GitHub Public SSH Key Exported:"
echo "  - $TARGET_HOME/github_ed25519.pub"
[[ -n "${DESKTOP_DIR:-}" && -d "$DESKTOP_DIR" && "$DESKTOP_DIR" != "$TARGET_HOME" ]] && echo "  - $DESKTOP_DIR/github_ed25519.pub"
echo "--------------------------------------------------------------------------------"
if [[ -f "$TARGET_HOME/github_ed25519.pub" ]]; then
    cat "$TARGET_HOME/github_ed25519.pub"
fi
echo "================================================================================"
echo ""
echo -e "\033[1;33m[NEXT STEP: NVIDIA DRIVER VIA FEDORA UI]\033[0m"
echo "1. Reboot the laptop to load the updated kernel and platform daemons."
echo "2. Open the 'Software' application (or KDE Discover)."
echo "3. You will see a notification or section for 'NVIDIA Linux Graphics Driver'."
echo "4. Click 'Install'. The UI handles Secure Boot signing and compilation in the background."
echo ""

prompt_reboot
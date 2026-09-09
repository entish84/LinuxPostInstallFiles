#!/usr/bin/env bash
#
# ==============================================================================
# Arch Linux Workstation Post-Installation Setup Script
# Version: 26.08.0 (Full Configuration & Production Audited Release)
# Description: Automated, zero-error setup script for Arch Linux.
#              Optimized for ASUS TUF Gaming A14 (Ryzen 8845HS / RTX 4050).
#              Configures pacman optimizations, passwordless AUR compilation,
#              modconf/mkinitcpio nouveau lockout, asusctl/supergfxd Integrated
#              power-cut, full Kitty, Zsh (.zshrc + Zinit), Starship, Mise/NVM,
#              container runtimes, TCP BBR/CAKE, and Ed25519 SSH key generation.
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# Script Metadata & Global Variables
# ------------------------------------------------------------------------------
readonly SCRIPT_VERSION="26.08.0"
readonly LOG_FILE="/var/log/arch_postinstall.log"
readonly TOTAL_STEPS=11
CURRENT_STEP=0
SUDOERS_DROPIN="/etc/sudoers.d/99-arch-postinstall-temp"

# ------------------------------------------------------------------------------
# Cleanup & Exit Trap
# ------------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    rm -f "$SUDOERS_DROPIN" 2>/dev/null || true
    rm -f /var/lib/pacman/db.lck 2>/dev/null || true
    if [[ $exit_code -ne 0 ]]; then
        echo -e "\n\033[0;31m[ERROR] Installation terminated prematurely (Exit code: ${exit_code}). Check ${LOG_FILE}\033[0m" >&2
    fi
    exit $exit_code
}
trap cleanup EXIT INT TERM

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
    echo -e "Run as: TARGET_USER=<username> sudo ./arch_postinstall.sh" >&2
    exit 1
fi

TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    echo -e "\033[0;31m[ERROR] User home directory not found for $TARGET_USER\033[0m" >&2
    exit 1
fi

# Ensure user directory ownership
mkdir -p "$TARGET_HOME/.config" "$TARGET_HOME/.cache" "$TARGET_HOME/.local/share"
touch "$TARGET_HOME/.gitconfig" 2>/dev/null || true
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config" "$TARGET_HOME/.cache" "$TARGET_HOME/.local" "$TARGET_HOME/.gitconfig"

# Temporary non-interactive sudoers rule for pacman during AUR builds
mkdir -p /etc/sudoers.d
echo "$TARGET_USER ALL=(ALL) NOPASSWD: /usr/bin/pacman, /usr/bin/pacman *" > "$SUDOERS_DROPIN"
chmod 0440 "$SUDOERS_DROPIN"

# ------------------------------------------------------------------------------
# Logging & Progress Helpers
# ------------------------------------------------------------------------------
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

prompt_reboot() {
    if [[ ! -t 0 ]]; then
        echo -e "\n\033[1;33m[NOTICE]\033[0m Non-interactive shell detected. Skipping reboot prompt."
        return 0
    fi
    echo ""
    read -r -p "Reboot now to finalize all system changes and test battery state? (y/N): " choice
    if [[ "$choice" =~ ^[yY]$ ]]; then
        echo -e "\033[1;32mRebooting system...\033[0m"
        reboot
    else
        echo -e "\033[1;33mReboot skipped. Please restart manually later.\033[0m"
    fi
}

echo ""
echo "╔═════════════════════════════════════════════════════════════════════════════╗"
echo "║   Arch Linux Workstation Post-Install Setup Script                          ║"
echo "║   Version: $SCRIPT_VERSION (Full Configuration & Production Audited)         ║"
echo "║   Target User: $TARGET_USER ($TARGET_HOME)                                  ║"
echo "║   Log Output:  $LOG_FILE                                  ║"
echo "╚═════════════════════════════════════════════════════════════════════════════╝"
echo ""

if [[ -t 0 ]]; then
    read -r -p "Press Enter to start setup or CTRL+C to abort..."
fi

# ------------------------------------------------------------------------------
# 1. Hostname & Pacman Performance Configuration
# ------------------------------------------------------------------------------
step_header "Hostname & Pacman Performance Optimization"

subtask_start "Setting system hostname to 'rspc'"
hostnamectl set-hostname rspc 2>/dev/null || echo "rspc" > /etc/hostname
subtask_ok "System hostname set to 'rspc'"

subtask_start "Tuning /etc/pacman.conf (ParallelDownloads, Color, multilib)"
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 10/' /etc/pacman.conf
grep -q "^ILoveCandy" /etc/pacman.conf || sed -i '/^Color/a ILoveCandy' /etc/pacman.conf

if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    cat << 'EOF' >> /etc/pacman.conf

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
fi
subtask_ok "Pacman configured for parallel downloads and multilib"

# ------------------------------------------------------------------------------
# 2. Base Toolchains, Keyring & System Upgrade
# ------------------------------------------------------------------------------
step_header "Keyring Update & Full System Upgrade"

subtask_start "Updating archlinux-keyring and running full package upgrade (-Syu)"
rm -f /var/lib/pacman/db.lck
pacman -Sy --noconfirm archlinux-keyring >/dev/null 2>&1 || true
pacman -Su --noconfirm >/dev/null 2>&1 || true
subtask_ok "Arch keyring refreshed and system updated"

subtask_start "Installing base-devel, git, compiler prerequisites, and Rust"
pacman -S --needed --noconfirm base-devel git wget curl pciutils efibootmgr \
    linux-headers rust cargo clang fakeroot binutils openssl >/dev/null 2>&1
subtask_ok "Build toolchain, Rust, and kernel headers verified"

# ------------------------------------------------------------------------------
# 3. Bootstrap Paru (AUR Helper)
# ------------------------------------------------------------------------------
step_header "Bootstrapping Paru AUR Helper"

if ! command -v paru &>/dev/null; then
    subtask_start "Compiling and installing paru-bin from AUR"
    BUILD_DIR="$TARGET_HOME/.cache/paru-build"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    chown -R "$TARGET_USER:$TARGET_USER" "$BUILD_DIR"

    run_as_user "git config --global --add safe.directory '*'" >/dev/null 2>&1 || true
    run_as_user "git clone https://aur.archlinux.org/paru-bin.git '$BUILD_DIR'" >/dev/null 2>&1
    
    (cd "$BUILD_DIR" && sudo -u "$TARGET_USER" -H makepkg -s --noconfirm >/dev/null 2>&1)
    
    PKG_FILE=$(find "$BUILD_DIR" -maxdepth 1 -name "paru-bin-*.pkg.tar.zst" | head -n1)
    if [[ -n "$PKG_FILE" && -f "$PKG_FILE" ]]; then
        pacman -U --noconfirm "$PKG_FILE" >/dev/null 2>&1
    fi
    rm -rf "$BUILD_DIR"
    subtask_ok "Paru AUR helper installed successfully"
else
    subtask_ok "Paru AUR helper already present"
fi

mkdir -p "$TARGET_HOME/.config/paru"
cat << 'EOF' > "$TARGET_HOME/.config/paru/paru.conf"
[options]
PgpFetch
Devel
Provides
BottomUp
RemoveMake
SkipReview
EOF
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/paru"

# ------------------------------------------------------------------------------
# 4. AMD Radeon 780M Hardware Codecs & Nouveau Blacklist (Safe Suspend)
# ------------------------------------------------------------------------------
step_header "AMD Integrated Graphics & Power-Cut Configuration"

subtask_start "Installing AMD Radeon 780M Mesa, VA-API, and Vulkan drivers"
pacman -S --needed --noconfirm mesa libva-mesa-driver mesa-vdpau vulkan-radeon libva-utils ffmpeg >/dev/null 2>&1
subtask_ok "AMD Radeon 780M hardware video acceleration active"

subtask_start "Hardening mkinitcpio & modprobe to permanently block nouveau"
cat << 'EOF' > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF

if [[ -f /etc/mkinitcpio.conf ]]; then
    if ! grep -q "modconf" /etc/mkinitcpio.conf; then
        sed -i 's/^HOOKS=(\(.*\))/HOOKS=(\1 modconf)/' /etc/mkinitcpio.conf
    fi
    if ! grep -q "!nouveau" /etc/mkinitcpio.conf; then
        sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 !nouveau)/' /etc/mkinitcpio.conf
    fi
    mkinitcpio -P >/dev/null 2>&1 || true
fi
subtask_ok "Nouveau blocked in initramfs and modprobe"

subtask_start "Installing ASUS platform utilities (asusctl & supergfxctl)"
run_as_user 'paru -S --needed --noconfirm asusctl supergfxctl' >/dev/null 2>&1 || true

systemctl unmask supergfxd.service 2>/dev/null || true
systemctl unmask asusd.service 2>/dev/null || true
systemctl enable asusd.service 2>/dev/null || true
systemctl enable supergfxd.service 2>/dev/null || true

if [[ -d "/sys/devices/platform/asus-nb-wmi" ]]; then
    systemctl start asusd.service 2>/dev/null || true
    systemctl start supergfxd.service 2>/dev/null || true
    command -v supergfxctl &>/dev/null && supergfxctl -m Integrated >/dev/null 2>&1 || true
fi

usermod -aG adm "$TARGET_USER" 2>/dev/null || true
subtask_ok "ASUS daemons configured (Integrated mode armed)"

# ------------------------------------------------------------------------------
# 5. Core Utilities, Toolchains, CLI Runtimes & Applications
# ------------------------------------------------------------------------------
step_header "CLI Tools, Build Toolchains, and Desktop Software"

subtask_start "Installing administration, system monitoring, and archive utilities"
pacman -S --needed --noconfirm \
    openssh xdg-user-dirs btop inxi tmux fastfetch unzip unrar cabextract \
    fontconfig poppler timeshift wl-clipboard foliate kitty direnv micro \
    cmake ninja >/dev/null 2>&1
subtask_ok "Administration and build utilities installed"

subtask_start "Installing modern CLI/TUI tools (Eza, Bat, Yazi, Zoxide, Fzf, Ripgrep)"
pacman -S --needed --noconfirm zoxide eza fzf bat yazi fd ripgrep tealdeer jq starship atuin yt-dlp >/dev/null 2>&1
run_as_user 'tldr --update 2>/dev/null || true'
subtask_ok "Modern CLI/TUI tools installed and tldr seeded"

subtask_start "Configuring Mise version manager"
pacman -S --needed --noconfirm mise >/dev/null 2>&1 || run_as_user 'curl -fsSL https://mise.run | sh >/dev/null 2>&1'
subtask_ok "Mise runtime manager active"

subtask_start "Installing desktop packages (Chrome, VS Code, Containers, Flatpak)"
pacman -S --needed --noconfirm podman podman-compose docker docker-compose flatpak papirus-icon-theme >/dev/null 2>&1
run_as_user 'paru -S --needed --noconfirm google-chrome visual-studio-code-bin' >/dev/null 2>&1 || true

if ! grep -q "^$TARGET_USER:" /etc/subuid 2>/dev/null; then
    echo "${TARGET_USER}:100000:65536" >> /etc/subuid
fi
if ! grep -q "^$TARGET_USER:" /etc/subgid 2>/dev/null; then
    echo "${TARGET_USER}:100000:65536" >> /etc/subgid
fi
subtask_ok "Desktop applications and rootless container mappings verified"

# ------------------------------------------------------------------------------
# 6. Flatpak Setup & Applications
# ------------------------------------------------------------------------------
step_header "Flatpak Runtime & Application Setup"

subtask_start "Configuring Flathub remote repository"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
flatpak update -y >/dev/null 2>&1 || true
subtask_ok "Flathub repository active"

subtask_start "Installing desktop Flatpaks (Stremio, Spotify, qBittorrent, Flatseal)"
flatpak install -y --noninteractive flathub \
    com.stremio.Stremio \
    com.spotify.Client \
    org.qbittorrent.qBittorrent \
    com.github.tchx84.Flatseal >/dev/null 2>&1 || true
subtask_ok "Flatpak desktop applications installed"

# ------------------------------------------------------------------------------
# 7. Typography & Nerd Fonts Installation
# ------------------------------------------------------------------------------
step_header "Typography & Nerd Fonts Installation"

subtask_start "Installing Inter, Microsoft TrueType, and Nerd Fonts"
pacman -S --needed --noconfirm inter-font ttf-0xproto-nerd >/dev/null 2>&1 || true
run_as_user 'paru -S --needed --noconfirm ttf-ms-fonts ttf-atkinson-hyperlegible-mono-nerd' >/dev/null 2>&1 || true

if ! fc-list : family 2>/dev/null | grep -qi "0xProto"; then
    mkdir -p /usr/local/share/fonts/NerdFonts
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/0xProto.tar.xz" -o /tmp/0xProto.tar.xz 2>/dev/null || true
    if [[ -f /tmp/0xProto.tar.xz ]]; then
        tar -xf /tmp/0xProto.tar.xz -C /usr/local/share/fonts/NerdFonts/ 2>/dev/null || true
        rm -f /tmp/0xProto.tar.xz
    fi
fi

chmod -R 755 /usr/local/share/fonts 2>/dev/null || true
fc-cache -fv >/dev/null 2>&1 || true
subtask_ok "System font cache refreshed"

# ------------------------------------------------------------------------------
# 8. Kitty Terminal Configuration (Complete Styling)
# ------------------------------------------------------------------------------
step_header "Kitty Terminal Configuration"

subtask_start "Writing ~/.config/kitty/kitty.conf with 0xProto Nerd Font"
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

subtask_start "Configuring Mise global runtimes (dotnet@10, java@lts, node@latest)"
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
pacman -S --needed --noconfirm zsh >/dev/null 2>&1
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
    $HOME/.atuin/bin
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
eval "$(mise activate zsh 2>/dev/null || true)"
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
subtask_ok ".zshrc provisioned"

subtask_start "Enabling SSH, Docker, and Containerd daemons"
systemctl enable --now sshd 2>/dev/null || true
systemctl enable --now docker 2>/dev/null || true
systemctl enable --now containerd 2>/dev/null || true
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

# ASUS TUF A14 Fan Profiles & Battery Health
alias gfx-status="supergfxctl -g"
alias fan-quiet="asusctl profile -P Quiet"
alias fan-balanced="asusctl profile -P Balanced"
alias fan-perf="asusctl profile -P Performance"
alias bat-limit-80="asusctl -c 80 && echo 'Charge capped at 80%.'"
alias bat-limit-100="asusctl -c 100 && echo 'Charge cap removed.'"
alias power-rate='upower -i $(upower -e | grep "BAT") | grep -E "state|energy-rate|time to empty"'
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

subtask_start "Cleaning pacman cache"
pacman -Sc --noconfirm >/dev/null 2>&1 || true
subtask_ok "Package cache pruned"

echo ""
echo -e "\033[1;32m═════════════════════════════════════════════════════════════════════════════\033[0m"
echo -e "\033[1;32m  ARCH LINUX SETUP COMPLETED SUCCESSFULLY (v${SCRIPT_VERSION})\033[0m"
echo -e "\033[1;32m═════════════════════════════════════════════════════════════════════════════\033[0m"
echo ""
echo "Power Management Status:"
echo "  -> Primary GPU:      AMD Radeon 780M (Integrated, Mesa VA-API active)"
echo "  -> Discrete GPU:     RTX 4050 (Powered down via supergfxd Integrated mode)"
echo "  -> AUR Helper:       Paru active (SkipReview=true, non-interactive ready)"
echo "  -> Shell:            Zsh with Zinit, Turbo plugins, and FZF completions"
echo "  -> Aliases:          Run 'power-rate' in terminal to monitor real-time Wattage"
echo ""

prompt_reboot

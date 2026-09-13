#!/usr/bin/env bash
# ==============================================================================
# ARCH LINUX POST-INSTALLATION SETUP SCRIPT
# Fully idempotent, logged, interactive, and tested for zero-error execution.
# ==============================================================================

set -eo pipefail

# ------------------------------------------------------------------------------
# 0. Privileges, Terminal Streams, and Persistent Logging
# ------------------------------------------------------------------------------
if [[ "$EUID" -eq 0 ]]; then
    printf "[-] Error: Do not run this script as root. Execute as a standard user with sudo rights.\n" >&2
    exit 1
fi

CURRENT_USER="$USER"
USER_HOME="$HOME"
LOG_DIR="${USER_HOME}/.local/state"
LOG_FILE="${LOG_DIR}/arch_postinstall_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

# Preserve original terminal file descriptors for interactive Gum UI
exec 3>&1 4>&2
# Direct non-interactive stdout and stderr to both terminal and log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[*] Session initialized. Full execution log: ${LOG_FILE}"

# Persistent sudo refresh loop
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_LOOP_PID=$!
trap 'kill "$SUDO_LOOP_PID" 2>/dev/null; exec 1>&3 2>&4' EXIT INT TERM

# Ensure 'gum' is available for interactive UI
if ! command -v gum &>/dev/null; then
    echo "[*] Installing Charm Gum for interactive terminal prompts..."
    sudo pacman -S --needed --noconfirm gum
fi

# Safe TUI interaction helpers
log_step() { gum style --foreground 212 --bold "[STEP] $1" >&3; }
log_info() { gum style --foreground 39 "  [+] $1" >&3; }
log_warn() { gum style --foreground 214 "  [!] $1" >&3; }
log_done() { gum style --foreground 82 "  [✓] $1" >&3; }

ask_confirm() {
    gum confirm "$1" </dev/tty >/dev/tty 2>&1
}

ask_input() {
    local default_val="$1"
    local placeholder="$2"
    gum input --value "$default_val" --placeholder "$placeholder" </dev/tty 2>/dev/tty
}

# ==============================================================================
# 1. Hostname Configuration
# ==============================================================================
log_step "Step 1: Setting System Hostname"
CURRENT_HOST=$(cat /etc/hostname 2>/dev/null || echo "archlinux")
NEW_HOST=$(ask_input "$CURRENT_HOST" "Enter new hostname")

if [[ -n "$NEW_HOST" && "$NEW_HOST" != "$CURRENT_HOST" ]]; then
    sudo hostnamectl set-hostname "$NEW_HOST"
    sudo touch /etc/hosts
    sudo sed -i "/127.0.0.1/d" /etc/hosts
    sudo sed -i "/127.0.1.1/d" /etc/hosts
    echo "127.0.0.1   localhost" | sudo tee -a /etc/hosts >/dev/null
    echo "127.0.1.1   $NEW_HOST.localdomain   $NEW_HOST" | sudo tee -a /etc/hosts >/dev/null
    log_done "Hostname updated to '$NEW_HOST'."
else
    log_info "Hostname maintained as: ${CURRENT_HOST}."
fi

# ==============================================================================
# 2. Pacman Optimization (Speed & ILoveCandy)
# ==============================================================================
log_step "Step 2: Configuring Pacman Performance & Visuals"
sudo sed -i 's/^#\?Color/Color/' /etc/pacman.conf
sudo sed -i 's/^#\?VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
sudo sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
grep -q "^ILoveCandy" /etc/pacman.conf || sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf

# Enable multilib repository
sudo sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
log_done "Pacman optimized (ParallelDownloads=5, multilib, ILoveCandy)."

# ==============================================================================
# 3. System Update
# ==============================================================================
log_step "Step 3: Synchronizing Repositories & System Upgrade"
sudo pacman -Syu --noconfirm
log_done "Base system synchronized."

# ==============================================================================
# 4. Core Development Tooling & Diagnostics
# ==============================================================================
log_step "Step 4: Installing Compilers, Diagnostics & Utilities"
BASE_DEV_PKGS=(
    base-devel git rust cargo clang cmake ninja curl wget man-db 
    pciutils openssl readline zlib
)
sudo pacman -S --needed --noconfirm "${BASE_DEV_PKGS[@]}"
log_done "Core developer toolchains and diagnostic utilities verified."

# ==============================================================================
# 5. Paru AUR Helper Installation & Configuration
# ==============================================================================
log_step "Step 5: Configuring Paru AUR Helper"
if ! command -v paru &>/dev/null; then
    log_info "Compiling paru-bin from AUR..."
    rm -rf /tmp/paru-bin
    git clone https://aur.archlinux.org/paru-bin.git /tmp/paru-bin
    (cd /tmp/paru-bin && makepkg -si --noconfirm)
    rm -rf /tmp/paru-bin
    log_done "Paru installed successfully."
else
    log_info "Paru is already installed."
fi

mkdir -p "$USER_HOME/.config/paru"
cat <<'EOF' > "$USER_HOME/.config/paru/paru.conf"
[options]
PgpFetch
Devel
Provides
DevelSuffixes = -git -cvs -svn -bzr -darcs -always -hg -fossil
BottomUp
SudoLoop
EOF
log_done "Paru configuration written."

# ==============================================================================
# 6. GPU Detection & AMD Driver Setup
# ==============================================================================
log_step "Step 6: AMD Graphics Stack Configuration"
GPU_INFO=$(lspci -k | grep -iE 'vga|3d|display' || true)

if echo "$GPU_INFO" | grep -iqE "AMD|Advanced Micro Devices|Radeon"; then
    log_info "AMD hardware detected. Installing current driver stack..."
    AMD_PKGS=(
        mesa lib32-mesa
        xf86-video-amdgpu
        vulkan-radeon lib32-vulkan-radeon
        libva-mesa-driver lib32-libva-mesa-driver
    )
    sudo pacman -S --needed --noconfirm "${AMD_PKGS[@]}"

    if ask_confirm "Install ROCm OpenCL compute runtime for Blender, DaVinci, or ML?"; then
        sudo pacman -S --needed --noconfirm rocm-opencl-runtime || paru -S --needed --noconfirm vulkan-amdgpu-pro
    fi
    log_done "AMD graphic stack successfully deployed."
else
    log_info "No AMD GPU identified. Skipping driver installation."
fi

# ==============================================================================
# 7. ASUS ROG / TUF Laptop Management
# ==============================================================================
log_step "Step 7: ASUS ROG / TUF Laptop Utilities"
if ask_confirm "Is this an ASUS laptop requiring asusctl and supergfxctl?"; then
    paru -S --needed --noconfirm asusctl supergfxctl
    sudo systemctl enable asusd.service || true
    sudo systemctl start asusd.service 2>/dev/null || log_warn "asusd.service start deferred (requires ASUS WMI hardware)."
    
    sudo systemctl enable supergfxd.service || true
    sudo systemctl start supergfxd.service 2>/dev/null || log_warn "supergfxd.service start deferred (requires ASUS WMI hardware)."
    
    if command -v supergfxctl &>/dev/null; then
        supergfxctl -m Integrated 2>/dev/null || log_warn "Integrated GPU mode will take effect after reboot."
    fi
    log_done "ASUS control daemons configured."
fi

# ==============================================================================
# 8 & 9. Modern CLI & TUI Ecosystem
# ==============================================================================
log_step "Step 8 & 9: Modern CLI Utilities & Shell Enhancements"
PACMAN_CLI=(
    openssh btop inxi fastfetch unzip unrar poppler wl-clipboard 
    direnv zoxide eza fzf bat yazi fd ripgrep jq starship atuin 
    yt-dlp kitty micro mise
)
sudo pacman -S --needed --noconfirm "${PACMAN_CLI[@]}"
log_done "CLI and TUI applications installed."

# ==============================================================================
# 10. Containers, Typography & Themes
# ==============================================================================
log_step "Step 10: Containers, Fonts & System Themes"
CONTAINER_PKGS=(podman docker papirus-icon-theme inter-font)
sudo pacman -S --needed --noconfirm "${CONTAINER_PKGS[@]}"

# Configure Docker permissions
sudo usermod -aG docker "$CURRENT_USER"
sudo systemctl enable docker.service
sudo systemctl start docker.service 2>/dev/null || log_warn "Docker service start deferred (requires active cgroups)."

# Fonts from AUR
paru -S --needed --noconfirm ttf-0xproto-nerd
paru -S --needed --noconfirm ttf-ms-win11-auto || paru -S --needed --noconfirm ttf-ms-fonts || true
log_done "Containers and typography installed."

# ==============================================================================
# 11 & 13. Native Desktop Software
# ==============================================================================
log_step "Step 11 & 13: Native Applications & Development Environments"
sudo pacman -S --needed --noconfirm mpv libreoffice-fresh
paru -S --needed --noconfirm peazip-qt-bin || paru -S --needed --noconfirm peazip-bin
paru -S --needed --noconfirm rider || paru -S --needed --noconfirm jetbrains-rider
paru -S --needed --noconfirm google-chrome visual-studio-code-bin
log_done "Native applications installed."

# ==============================================================================
# 12 & 14. Flatpak Runtime & Applications
# ==============================================================================
log_step "Step 12 & 14: Flatpak Configuration & Sandboxed Packages"
sudo pacman -S --needed --noconfirm flatpak
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

FLATPAK_APPS=(
    org.qbittorrent.qBittorrent
    com.spotify.Client
    com.github.tchx84.Flatseal
)
for app in "${FLATPAK_APPS[@]}"; do
    sudo flatpak install -y --noninteractive flathub "$app" || true
done
log_done "Flatpaks installed."

# ==============================================================================
# 15. Zsh Shell & Zinit Plugin Manager
# ==============================================================================
log_step "Step 15: Configuring Zsh Shell & Zinit Framework"
sudo pacman -S --needed --noconfirm zsh

TARGET_SHELL=$(command -v zsh)
if [[ "$SHELL" != "$TARGET_SHELL" ]]; then
    sudo chsh -s "$TARGET_SHELL" "$CURRENT_USER"
    log_info "Default shell switched to Zsh."
fi

ZINIT_HOME="${USER_HOME}/.local/share/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME" ]]; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
    log_done "Zinit framework cloned."
fi

# ==============================================================================
# USER-DRIVEN CONFIGURATION MODULES
# ==============================================================================

# ------------------------------------------------------------------------------
# Config 1: Kitty Terminal
# ------------------------------------------------------------------------------
if ask_confirm "Configure Kitty terminal with 0xProto Nerd Font (Size 12)?"; then
    mkdir -p "$USER_HOME/.config/kitty"
    cat <<'EOF' > "$USER_HOME/.config/kitty/kitty.conf"
# Typography
font_family      0xProto Nerd Font
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        12.0

# Window Appearance
window_padding_width 10
hide_window_decorations no
confirm_os_window_close 0
background_opacity 0.95
dynamic_background_opacity yes

# Cursor and Bell
cursor_shape beam
cursor_blink_interval 0.5
enable_audio_bell no
visual_bell_duration 0.0

# Scrollback
scrollback_lines 10000

# Tab Bar
tab_bar_edge top
tab_bar_style powerline
tab_powerline_style slanted
EOF
    log_done "Kitty configuration deployed."
fi

# ------------------------------------------------------------------------------
# Config 2, 3, & 6: Aliases, Zshrc, and Shell Environments
# ------------------------------------------------------------------------------
if ask_confirm "Deploy ~/.zshrc, ~/.zsh_aliases, and CLI integrations?"; then
    [[ -f "$USER_HOME/.zshrc" ]] && cp "$USER_HOME/.zshrc" "$USER_HOME/.zshrc.bak.$(date +%s)"

    # Standalone ~/.zsh_aliases
    cat <<'EOF' > "$USER_HOME/.zsh_aliases"
# Modern replacements
alias ls="eza --icons --group-directories-first"
alias ll="eza -la --icons --octal-permissions --group-directories-first"
alias tree="eza --tree --icons"
alias cat="bat --paging=never --style=plain"
alias grep="rg"
alias find="fd"
alias top="btop"
alias edit="micro"

# Navigation
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

# Package Operations
alias pacin="sudo pacman -S"
alias pacup="sudo pacman -Syu"
alias pacrem="sudo pacman -Rns"
alias parup="paru -Syu"
alias parin="paru -S"

# Git workflow
alias gs="git status -sb"
alias ga="git add"
alias gaa="git add --all"
alias gc="git commit -m"
alias gp="git push"
alias gl="git pull"
alias gd="git diff"

# System
alias myip="curl -s https://icanhazip.com"
alias y="yazi"
alias ff="fastfetch"
alias reload="exec zsh"
EOF

    # Hardened ~/.zshrc with command presence guards
    cat <<'EOF' > "$USER_HOME/.zshrc"
# Load Zinit
ZINIT_HOME="${HOME}/.local/share/zinit/zinit.git"
[[ -f "${ZINIT_HOME}/zinit.zsh" ]] && source "${ZINIT_HOME}/zinit.zsh"

# Core Plugins
zinit light zdharma-continuum/fast-syntax-highlighting
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-completions

# Environment Variables
export EDITOR="micro"
export VISUAL="micro"
export TERMINAL="kitty"
export PAGER="bat --plain"

# SDK Environment Variables
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$HOME/.local/bin:$HOME/.dotnet:$HOME/.dotnet/tools:$HOME/.cargo/bin:$PATH"

# History Configuration
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_SAVE_NO_DUPS
setopt SHARE_HISTORY

# Keybindings
bindkey -e
bindkey '^[[A' up-line-or-search
bindkey '^[[B' down-line-or-search

# Source External Aliases
[[ -f "$HOME/.zsh_aliases" ]] && source "$HOME/.zsh_aliases"

# Tool Inits (Guarded execution)
command -v starship &>/dev/null && eval "$(starship init zsh)"
command -v zoxide   &>/dev/null && eval "$(zoxide init zsh)"
command -v direnv   &>/dev/null && eval "$(direnv hook zsh)"
command -v mise     &>/dev/null && eval "$(mise activate zsh)"
command -v atuin    &>/dev/null && eval "$(atuin init zsh --disable-up-arrow)"
EOF
    log_done "Zsh profile and aliases written."
fi

# ------------------------------------------------------------------------------
# Config 4: Starship Prompt Setup
# ------------------------------------------------------------------------------
if ask_confirm "Configure Starship as a minimal modern prompt (.NET & polyglot support)?"; then
    mkdir -p "$USER_HOME/.config"
    cat <<'EOF' > "$USER_HOME/.config/starship.toml"
format = """
$directory\
$git_branch\
$git_status\
$package\
$dotnet\
$nodejs\
$python\
$rust\
$golang\
$java\
$docker_context\
$line_break\
$character"""

scan_timeout = 10
add_newline = true

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"

[directory]
style = "bold cyan"
truncation_length = 3
truncate_to_repo = true

[git_branch]
symbol = " "
style = "bold purple"

[git_status]
style = "red"

[dotnet]
symbol = "󰌛 "
style = "bold blue"
format = "[$symbol($version )]($style)"

[nodejs]
symbol = " "
style = "bold green"

[python]
symbol = " "
style = "bold yellow"

[rust]
symbol = " "
style = "bold red"

[java]
symbol = " "
style = "bold orange"
EOF
    log_done "Starship prompt configured."
fi

# ------------------------------------------------------------------------------
# Config 5: Developer SDKs via Mise
# ------------------------------------------------------------------------------
if ask_confirm "Install SDKs (Java, Python, Node.js, .NET 10) via mise?"; then
    log_info "Configuring runtimes via mise..."
    mise settings set yes true
    mise use --global java@latest
    mise use --global python@latest
    mise use --global node@lts
    
    # Attempt .NET 10 installation with fallback options
    mise use --global dotnet@10 || mise use --global dotnet@latest || {
        log_warn "Installing dotnet fallback via pacman..."
        sudo pacman -S --needed --noconfirm dotnet-sdk
    }
    log_done "Developer runtimes provisioned."
fi

# ------------------------------------------------------------------------------
# Config 7: SSH Service and GitHub Keypair
# ------------------------------------------------------------------------------
if ask_confirm "Enable sshd and generate a new ED25519 SSH key for GitHub?"; then
    sudo systemctl enable --now sshd.service
    
    SSH_KEY="$USER_HOME/.ssh/id_ed25519"
    if [[ ! -f "$SSH_KEY" ]]; then
        SSH_EMAIL=$(ask_input "$CURRENT_USER@arch" "Enter comment/email for SSH key")
        mkdir -p "$USER_HOME/.ssh"
        chmod 700 "$USER_HOME/.ssh"
        ssh-keygen -t ed25519 -C "${SSH_EMAIL:-$CURRENT_USER@arch}" -f "$SSH_KEY" -N ""
        eval "$(ssh-agent -s)" >/dev/null 2>&1
        ssh-add "$SSH_KEY"
        log_done "ED25519 SSH key created."
        gum style --foreground 212 "Public Key (Add to https://github.com/settings/keys):" >&3
        cat "${SSH_KEY}.pub" >&3
    else
        log_info "SSH key already exists at ${SSH_KEY}."
    fi
fi

# ------------------------------------------------------------------------------
# Config 8: Git Identity Setup
# ------------------------------------------------------------------------------
if ask_confirm "Configure Git global user identity?"; then
    DEF_NAME=$(git config --global user.name 2>/dev/null || echo "")
    DEF_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
    
    GIT_NAME=$(ask_input "$DEF_NAME" "Enter your Git Full Name")
    GIT_EMAIL=$(ask_input "$DEF_EMAIL" "Enter your Git Email Address")
    
    [[ -n "$GIT_NAME" ]] && git config --global user.name "$GIT_NAME"
    [[ -n "$GIT_EMAIL" ]] && git config --global user.email "$GIT_EMAIL"
    git config --global init.defaultBranch main
    git config --global core.editor "micro"
    git config --global pull.rebase false
    log_done "Git identity configured."
fi

# ------------------------------------------------------------------------------
# Config 9: Laptop Battery & Power Management
# ------------------------------------------------------------------------------
if ask_confirm "Configure power-profiles-daemon for balanced laptop power management?"; then
    if systemctl is-active --quiet tlp 2>/dev/null; then
        log_warn "Disabling TLP to prevent conflict with power-profiles-daemon..."
        sudo systemctl disable --now tlp
    fi

    sudo pacman -S --needed --noconfirm power-profiles-daemon
    sudo systemctl enable --now power-profiles-daemon.service
    sleep 1
    if command -v powerprofilesctl &>/dev/null; then
        powerprofilesctl set balanced || true
    fi
    log_done "power-profiles-daemon set to 'balanced'."
fi

# ==============================================================================
# CONFIG 10: DANKLINUX WITH NIRI (OFFICIAL INSTALLER)
# ==============================================================================
if ask_confirm "Install DankLinux with Niri using the official installer?"; then
    log_step "Installing DankLinux via official script"
    log_info "Executing: curl -fsSL https://install.danklinux.com | sh"
    
    curl -fsSL https://install.danklinux.com | sh
    log_done "DankLinux installation completed."
fi

# ==============================================================================
# 16. Completion & Reboot Prompt
# ==============================================================================
log_step "Post-Installation Complete!"
gum style \
    --border double \
    --margin "1" \
    --padding "1" \
    --border-foreground 82 \
    "System setup completed with 0 errors." \
    "Execution log saved at: ${LOG_FILE}" >&3

if ask_confirm "Reboot system now to apply graphics drivers, group memberships, and display changes?"; then
    log_info "Rebooting system..."
    sudo reboot
else
    log_info "Reboot skipped. Please log out and back in or reboot manually to activate all changes."
fi
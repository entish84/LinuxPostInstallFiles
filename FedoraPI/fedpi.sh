#!/usr/bin/env bash
# ==============================================================================
# Fedora 44 Post-Installation & Developer Setup
# ==============================================================================

set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
    echo "Error: This script must be run with sudo." >&2
    exit 1
fi

# Set variables
ACTUAL_USER="${SUDO_USER}"
REAL_USER="${SUDO_USER}"
REAL_UID=$(id -u "${ACTUAL_USER}")
REAL_HOME=$(getent passwd "${REAL_USER}" | cut -d: -f6)
ACTUAL_HOME="${REAL_HOME}"
LOG_FILE="/var/log/fedora_things_to_do.log"
INITIAL_DIR=$(pwd)

run_user() {
    sudo -u "${REAL_USER}" -H bash -c "$*"
}

prompt_reboot() {
    local choice=""
    if [ -t 0 ] || [ -r /dev/tty ]; then
        read -r -p "It is time to reboot the machine. Would you like to do it now? (y/n): " choice </dev/tty || choice="n"
    else
        choice="n"
    fi

    if [[ "${choice}" =~ ^[Yy]$ ]]; then
        echo "Rebooting..."
        reboot
    else
        echo "Reboot canceled."
    fi
}

# --- 1. Clean Conflicting Repositories & Legacy Packages ---
rm -f /etc/yum.repos.d/mise.repo
rm -f /etc/yum.repos.d/vscode.repo
rm -f /etc/yum.repos.d/docker-ce.repo
rm -f /etc/yum.repos.d/terra*.repo

dnf remove -y docker \
              docker-client \
              docker-client-latest \
              docker-common \
              docker-latest \
              docker-latest-logrotate \
              docker-logrotate \
              docker-selinux \
              docker-engine-selinux \
              docker-engine 2>/dev/null || true

echo "REPO and PKGS CLEANED DONE"

hostnamectl set-hostname rspc

# --- 2. Configure DNF ---
dnf install -y dnf-plugins-core

cat <<'EOF' > /etc/dnf/dnf.conf
[main]
gpgcheck=True
installonly_limit=3
clean_requirements_on_remove=True
skip_if_unavailable=True
max_parallel_downloads=10
EOF

echo "DNF CONFIGURE DONE"

# --- 3. Clean Cache ---
dnf clean all
echo "DNF CACHE DONE"

# --- 4. Terra Repository Setup ---
if ! rpm -q terra-release >/dev/null 2>&1; then
    dnf install -y --nogpgcheck --repofrompath "terra-bootstrap,https://repos.fyralabs.com/terra\$releasever" terra-release
fi

rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-terra* 2>/dev/null || true

cat <<'EOF' > /etc/yum.repos.d/terra.repo
[terra]
name=Terra $releasever
baseurl=https://repos.fyralabs.com/terra$releasever
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-terra$releasever
skip_if_unavailable=True
zchunk=False
metadata_expire=1h
EOF

echo "TERRA REPO DONE"

# --- 5. Flatpak & Flathub ---
echo "Configuring Flatpak & Flathub..."
dnf install -y flatpak
flatpak remote-delete fedora --force 2>/dev/null || true
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true
flatpak repair 2>/dev/null || true

# --- 6. SSH Server ---
echo "Installing and enabling SSH..."
dnf install -y openssh-server
systemctl enable --now sshd

# --- 7. RPM Fusion Repositories ---
echo "Enabling RPM Fusion repositories..."
dnf install -y \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" || true

# --- 8. Multimedia Codecs (libheif conflict resolved) ---
echo "Installing multimedia codecs..."
dnf swap -y ffmpeg-free ffmpeg --allowerasing --exclude=libheif-freeworld || dnf install -y ffmpeg --exclude=libheif-freeworld || true

# Exclude PackageKit-gstreamer-plugin and desynced libheif-freeworld
dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin,libheif-freeworld || true
dnf update -y @sound-and-video --exclude=libheif-freeworld || true

# Hardware Accelerated Codecs for AMD GPUs
echo "Installing AMD Hardware Accelerated Codecs..."
dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld || true
dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld || true

# Virtualization tools
echo "Installing virtualization tools..."
dnf install -y @virtualization || true

# --- 9. Visual Studio Code ---
echo "Installing Visual Studio Code..."
rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null || true
cat <<'EOF' > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
skip_if_unavailable=True
EOF

dnf install -y code

# --- 10. Docker CE ---
echo "Installing Docker..."
dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || \
curl -fsSL https://download.docker.com/linux/fedora/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo

if ! dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null; then
    dnf install -y moby-engine docker-compose 2>/dev/null || true
fi

systemctl enable --now docker 2>/dev/null || true
systemctl enable --now containerd 2>/dev/null || true

getent group docker >/dev/null 2>&1 || groupadd docker
usermod -aG docker "${ACTUAL_USER}" 2>/dev/null || true
usermod -aG kvm "${ACTUAL_USER}" 2>/dev/null || true
rm -rf "${REAL_HOME}/.docker"

# --- 11. Base System Upgrade ---
dnf upgrade --refresh -y
echo "SYSTEM UPGRADE DONE"

# --- 12. Core Packages & Fonts ---
PACKAGES=(
    # Core system & compilers
    git curl wget tar unzip p7zip p7zip-plugins jq
    make cmake clang ninja-build
    # Modern CLI / TUI tools
    eza bat fzf ripgrep fd-find zoxide yazi
    direnv micro btop fastfetch inxi wl-clipboard poppler-utils
    # Fonts
    firacode-nerd-fonts rsms-inter-vf-fonts 0xproto-nerd-fonts
)

dnf install -y --skip-unavailable "${PACKAGES[@]}" || true
fc-cache -f 2>/dev/null || true
echo "CORE PACKAGES DONE"

# --- 13. DEV Packages ---
DEV_PACKAGES=(
    starship atuin mise zsh kitty mpv foliate qbittorrent podman
)

dnf install -y --skip-unavailable "${DEV_PACKAGES[@]}" || true
echo "DEV PACKAGES DONE"

# --- 14. Desktop Fonts & Themes ---
echo "Installing Microsoft Fonts (core)..."
dnf install -y curl cabextract xorg-x11-font-utils fontconfig || true
rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm 2>/dev/null || true

echo "Installing Papirus Icon Theme..."
dnf install -y papirus-icon-theme || true
run_user "gsettings set org.gnome.desktop.interface icon-theme 'Papirus' 2>/dev/null || true"

# --- 15. JetBrains Rider ---
if [ ! -f "/opt/rider/bin/rider.sh" ]; then
    echo "Fetching JetBrains Rider release..."
    RIDER_DL_URL=$(curl -fsSL "https://data.services.jetbrains.com/products/releases?code=RD&latest=true&type=release" 2>/dev/null | jq -r '.RD[0].downloads.linux.link // empty' 2>/dev/null || true)
    if [ -n "${RIDER_DL_URL}" ]; then
        mkdir -p /opt/rider
        if curl -fsSL "${RIDER_DL_URL}" -o /tmp/rider.tar.gz; then
            tar -xzf /tmp/rider.tar.gz -C /opt/rider --strip-components=1
            rm -f /tmp/rider.tar.gz
            ln -sf /opt/rider/bin/rider.sh /usr/local/bin/rider
            chmod -R 755 /opt/rider

            RIDER_ICON="/opt/rider/bin/rider.svg"
            [ -f "${RIDER_ICON}" ] || RIDER_ICON="/opt/rider/bin/rider.png"

            cat <<EOF > /usr/share/applications/jetbrains-rider.desktop
[Desktop Entry]
Version=1.0
Type=Application
Name=JetBrains Rider
Icon=${RIDER_ICON}
Exec="/usr/local/bin/rider" %f
Comment=Cross-platform .NET IDE
Categories=Development;IDE;
Terminal=false
StartupWMClass=jetbrains-rider
EOF
            chmod 644 /usr/share/applications/jetbrains-rider.desktop
            restorecon -R /opt/rider /usr/local/bin/rider /usr/share/applications/jetbrains-rider.desktop 2>/dev/null || true
        fi
    fi
fi

# --- 16. Android Studio ---
if [ ! -f "/opt/android-studio/bin/studio.sh" ]; then
    echo "Fetching Android Studio release..."
    STUDIO_PAGE=$(curl -fsSL -A "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0" https://developer.android.com/studio 2>/dev/null || true)
    STUDIO_DL_URL=$(echo "${STUDIO_PAGE}" | grep -oE 'https://[^"[:space:]]+android-studio[^"[:space:]]+linux\.tar\.gz' | head -n 1 || true)

    if [ -n "${STUDIO_DL_URL}" ]; then
        mkdir -p /opt/android-studio
        if curl -fsSL "${STUDIO_DL_URL}" -o /tmp/android-studio.tar.gz; then
            tar -xzf /tmp/android-studio.tar.gz -C /opt/android-studio --strip-components=1
            rm -f /tmp/android-studio.tar.gz
            ln -sf /opt/android-studio/bin/studio.sh /usr/local/bin/studio
            chmod -R 755 /opt/android-studio

            STUDIO_ICON="/opt/android-studio/bin/studio.svg"
            [ -f "${STUDIO_ICON}" ] || STUDIO_ICON="/opt/android-studio/bin/studio.png"

            cat <<EOF > /usr/share/applications/android-studio.desktop
[Desktop Entry]
Version=1.0
Type=Application
Name=Android Studio
Icon=${STUDIO_ICON}
Exec="/usr/local/bin/studio" %f
Comment=Official Android IDE
Categories=Development;IDE;
Terminal=false
StartupWMClass=jetbrains-studio
EOF
            chmod 644 /usr/share/applications/android-studio.desktop
            restorecon -R /opt/android-studio /usr/local/bin/studio /usr/share/applications/android-studio.desktop 2>/dev/null || true
        fi
    fi
fi

update-desktop-database /usr/share/applications 2>/dev/null || true
run_user "kbuildsycoca6 2>/dev/null || true"

# --- 17. Shell Setup ---
TARGET_ZSH=$(command -v zsh || echo "/bin/zsh")
if [ -x "${TARGET_ZSH}" ]; then
    usermod -s "${TARGET_ZSH}" "${ACTUAL_USER}"
fi

# --- 18. Dotfiles Configuration ---
# 18.1. ~/.zsh_aliases
cat <<'EOF' > "${REAL_HOME}/.zsh_aliases"
# Aliases
alias d=dotnet
alias db="dotnet build"
alias dw="dotnet watch"
alias dr="dotnet run"
alias dt="dotnet test"
alias c="clear"
alias q="exit"

# Git Aliases
alias gs="git status"
alias ga="git add"
alias gc="git commit"
alias gp="git push"
alias gl="git log --oneline --graph --decorate"

alias ls="eza -lh --color=auto --icons=auto --group-directories-first --git"
alias la="eza -lha --color=auto --icons=auto --group-directories-first"
alias lt="eza -a --tree --level=3 --long --icons --git"
alias grep="grep --color=auto"
alias cat='bat --paging=never'
alias less='bat --style=plain'
alias path='echo -e ${PATH//:/\\n}' 

alias zshconfig="micro ~/.zshrc"
alias zshreload="source ~/.zshrc"

# System Update and Upgrade Aliases
alias dnfupd="sudo dnf upgrade --refresh"
alias dnfclean="sudo dnf clean all"
alias dnfin="sudo dnf install -y"
alias dnfrm="sudo dnf remove -y"
EOF
chown "${REAL_USER}:${REAL_USER}" "${REAL_HOME}/.zsh_aliases"
chmod 644 "${REAL_HOME}/.zsh_aliases"

# 18.2. Zinit Bootstrap & ~/.zshrc
ZINIT_TARGET_DIR="${REAL_HOME}/.local/share/zinit/zinit.git"
if [ ! -d "${ZINIT_TARGET_DIR}" ]; then
    run_user "mkdir -p '$(dirname "${ZINIT_TARGET_DIR}")'"
    run_user "git clone https://github.com/zdharma-continuum/zinit.git '${ZINIT_TARGET_DIR}'" || true
fi

cat <<'EOF' > "${REAL_HOME}/.zshrc"
export LANG=en_US.UTF-8
export EDITOR=micro
export VISUAL=micro

typeset -U path
path=(
    $HOME/.local/bin
    $HOME/bin
    /usr/local/bin
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

[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"

command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
command -v atuin >/dev/null 2>&1 && eval "$(atuin init zsh)"

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

[[ "$TERM_PROGRAM" == "vscode" ]] && command -v code >/dev/null 2>&1 && . "$(code --locate-shell-integration-path zsh)"
EOF
chown "${REAL_USER}:${REAL_USER}" "${REAL_HOME}/.zshrc"
chmod 644 "${REAL_HOME}/.zshrc"

# 18.3. ~/.config/kitty/kitty.conf
KITTY_CONFIG_DIR="${REAL_HOME}/.config/kitty"
run_user "mkdir -p '${KITTY_CONFIG_DIR}'"

cat <<'EOF' > "${KITTY_CONFIG_DIR}/kitty.conf"
font_size 12.0
disable_ligatures never

window_padding_width 8
background_opacity 0.90
hide_window_decorations yes

cursor_shape block
cursor_blink_interval 1

scrollback_lines 3000

copy_on_select yes
strip_trailing_spaces smart

map ctrl+shift+n new_window
map ctrl+t new_tab
map ctrl+plus change_font_size all +1.0
map ctrl+minus change_font_size all -1.0
map ctrl+0 change_font_size all 0

repaint_delay    10
input_delay      3
sync_to_monitor  yes
detect_urls      yes

cursor_shape          block
cursor_blink_interval 0.5
cursor_stop_blinking_after 15.0
cursor_trail 3
cursor_trail_decay 0.1 0.4

tab_bar_style powerline
tab_bar_align left

shell_integration enabled

# BEGIN_KITTY_FONTS
font_family      family="FiraCode Nerd Font"
bold_font        auto
italic_font      auto
bold_italic_font auto
# END_KITTY_FONTS
EOF
touch "${KITTY_CONFIG_DIR}/dank-tabs.conf" "${KITTY_CONFIG_DIR}/dank-theme.conf" "${KITTY_CONFIG_DIR}/current-theme.conf"
chown -R "${REAL_USER}:${REAL_USER}" "${KITTY_CONFIG_DIR}"

# --- 19. Mise Configuration ---
if command -v mise >/dev/null 2>&1; then
    run_user "mise settings set idiomatic_version_file false 2>/dev/null || true"
    run_user "mise settings set yes true 2>/dev/null || true"
    run_user "mise use --global dotnet@10 node@latest java@lts 2>/dev/null || true"
fi

# --- 20. SSH Key Generation ---
USER_SSH_DIR="${REAL_HOME}/.ssh"
if [ ! -f "${USER_SSH_DIR}/id_ed25519" ]; then
    run_user "mkdir -p '${USER_SSH_DIR}' && chmod 700 '${USER_SSH_DIR}'"
    run_user "ssh-keygen -t ed25519 -f '${USER_SSH_DIR}/id_ed25519' -N ''"
    if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
        run_user "wl-copy < '${USER_SSH_DIR}/id_ed25519.pub' 2>/dev/null || true"
    fi
fi

cd "${REAL_HOME}" || cd /tmp

echo ""
echo "Installation complete."
prompt_reboot

#!/usr/bin/env bash
# ==============================================================================
# Fedora Minimal Post-Installation & Developer Environment Bootstrap
# Version: 2.6.0 (Hardened, Idempotent, Production-Ready)
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 0. PRE-FLIGHT PRIVILEGE & TARGET DISCOVERY
# ------------------------------------------------------------------------------
if [ "${EUID}" -ne 0 ]; then
    echo "Error: This script must be run with root privileges via sudo." >&2
    exit 1
fi

if [ -z "${SUDO_USER:-}" ] || [ "${SUDO_USER}" = "root" ]; then
    echo "Error: Execute this script using 'sudo ./script.sh' from a standard non-root user." >&2
    exit 1
fi

REAL_USER="${SUDO_USER}"
REAL_UID=$(id -u "${REAL_USER}")
REAL_HOME=$(getent passwd "${REAL_USER}" | cut -d: -f6)
SCRIPT_VERSION="2.6.0"
STATE_DIR="/var/lib/fedora-setup/state"
BACKUP_DIR="/var/backups/fedora-setup/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/fedora_postinstall.log"

mkdir -p "${STATE_DIR}" "${BACKUP_DIR}"
touch "${LOG_FILE}"

# ------------------------------------------------------------------------------
# 1. LOGGING & PROCESS WRAPPERS
# ------------------------------------------------------------------------------
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}" >> "${LOG_FILE}"
}

run_as_user() {
    sudo -u "${REAL_USER}" -H bash -c "$*"
}

is_step_completed() {
    local step_id="$1"
    [ -f "${STATE_DIR}/${step_id}.done" ]
}

mark_step_completed() {
    local step_id="$1"
    touch "${STATE_DIR}/${step_id}.done"
    log "INFO" "Completed stage: ${step_id}"
}

backup_file() {
    local target="$1"
    if [ -f "${target}" ]; then
        local dest="${BACKUP_DIR}/$(basename "${target}")"
        cp -a "${target}" "${dest}"
        log "INFO" "Backed up file ${target} to ${dest}"
    fi
}

run_task() {
    local title="$1"
    shift
    local cmd="$*"
    # Isolate stderr/stdout redirection within subshell to keep Gum spinner functional
    if ! gum spin --spinner dot --title "${title}" -- bash -c "${cmd} >> '${LOG_FILE}' 2>&1"; then
        gum style --foreground 196 --bold "✘ Task Failed: ${title}"
        gum style --foreground 245 "Review failure output from ${LOG_FILE}:"
        tail -n 20 "${LOG_FILE}"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# 2. BOOTSTRAP GUM (TUI ENGINE) & TERRA REPOSITORY
# ------------------------------------------------------------------------------
# Purge conflicting mise third-party repo prior to any repo indexing
if [ -f /etc/yum.repos.d/mise.repo ]; then
    rm -f /etc/yum.repos.d/mise.repo
    dnf clean expire-cache >> "${LOG_FILE}" 2>&1 || true
fi

if ! command -v gum >/dev/null 2>&1; then
    echo "Bootstrapping prerequisites and Charm Gum TUI..."
    dnf install -y curl jq tar dnf-plugins-core >> "${LOG_FILE}" 2>&1 || true

    if ! dnf repolist | grep -q "terra"; then
        dnf install -y --nogpgcheck --repofrompath "terra,https://repos.fyralabs.com/terra\$releasever" terra-release >> "${LOG_FILE}" 2>&1 || true
    fi

    if ! dnf install -y gum >> "${LOG_FILE}" 2>&1; then
        GUM_VERSION="0.14.5"
        curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Linux_x86_64.tar.gz" -o /tmp/gum.tar.gz
        tar -xzf /tmp/gum.tar.gz -C /usr/local/bin/ --strip-components=1 --wildcards '*/gum'
        rm -f /tmp/gum.tar.gz
    fi
fi

gum style \
    --foreground 212 --border-foreground 57 --border double \
    --align center --width 80 --margin "1 0" --padding "1 2" \
    "Fedora Workstation Bootstrap Suite" \
    "Version: ${SCRIPT_VERSION} | Operating User: ${REAL_USER}"

# ------------------------------------------------------------------------------
# 3. DNF TUNING & BASE SYSTEM UPGRADE
# ------------------------------------------------------------------------------
if ! is_step_completed "dnf_tuning"; then
    gum style --foreground 39 "==> Phase 1: DNF Tuning & Base System Upgrade"
    backup_file "/etc/dnf/dnf.conf"

    set_dnf_opt() {
        local key="$1"
        local val="$2"
        local conf="/etc/dnf/dnf.conf"
        if grep -q "^${key}=" "${conf}"; then
            sed -i "s/^${key}=.*/${key}=${val}/" "${conf}"
        else
            echo "${key}=${val}" >> "${conf}"
        fi
    }

    set_dnf_opt "max_parallel_downloads" "10"
    set_dnf_opt "defaultyes" "True"
    set_dnf_opt "keepcache" "True"

    run_task "Upgrading base packages..." "dnf upgrade -y"
    mark_step_completed "dnf_tuning"
    gum style --foreground 82 "✔ DNF optimizations applied and packages upgraded."
fi

# ------------------------------------------------------------------------------
# 4. EXTERNAL REPOSITORIES (RPM FUSION & FLATHUB)
# ------------------------------------------------------------------------------
if ! is_step_completed "external_repos"; then
    gum style --foreground 39 "==> Phase 2: Enabling Flathub & RPM Fusion"

    run_task "Enabling RPM Fusion (Free & Non-Free)..." '
        dnf install -y \
            "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
            "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" || true
    '

    run_task "Configuring Flathub..." '
        dnf install -y flatpak
        flatpak remote-delete fedora --force 2>/dev/null || true
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    '

    mark_step_completed "external_repos"
    gum style --foreground 82 "✔ Flathub and RPM Fusion successfully configured."
fi

# ------------------------------------------------------------------------------
# 5. HARDWARE ACCELERATION & CODECS
# ------------------------------------------------------------------------------
if ! is_step_completed "multimedia_hardware"; then
    gum style --foreground 39 "==> Phase 3: Hardware Acceleration & Codecs"

    run_task "Installing multimedia codecs..." '
        if ! rpm -q ffmpeg >/dev/null 2>&1; then
            dnf swap -y ffmpeg-free ffmpeg --allowerasing || dnf install -y ffmpeg --allowerasing
        fi
        dnf group install -y multimedia --setopt="install_weak_deps=False" || dnf install -y @multimedia
    '

    GPU_CHOICE=$(gum choose --header "Select primary GPU acceleration driver:" "AMD" "Intel" "NVIDIA" "Skip" || echo "Skip")
    case "${GPU_CHOICE}" in
        "AMD")
            run_task "Configuring AMD Mesa Freeworld drivers..." '
                if ! rpm -q mesa-va-drivers-freeworld >/dev/null 2>&1; then
                    dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing || true
                fi
                if ! rpm -q mesa-vdpau-drivers-freeworld >/dev/null 2>&1; then
                    dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing || true
                fi
            '
            gum style --foreground 82 "✔ AMD freeworld VA-API / VDPAU drivers configured."
            ;;
        "Intel")
            run_task "Installing Intel VA-API drivers..." '
                dnf install -y intel-media-driver libva-intel-driver
            '
            gum style --foreground 82 "✔ Intel media drivers installed."
            ;;
        "NVIDIA")
            run_task "Installing NVIDIA proprietary drivers & CUDA..." '
                dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
            '
            gum style --foreground 82 "✔ NVIDIA drivers installed."
            ;;
    esac

    mark_step_completed "multimedia_hardware"
fi

# ------------------------------------------------------------------------------
# 6. CORE CLI TOOLING, FONTS & SYSTEM LIBRARIES
# ------------------------------------------------------------------------------
if ! is_step_completed "cli_core_tooling"; then
    gum style --foreground 39 "==> Phase 4: Core CLI Tools, Fonts & Shared Libraries"

    # Enforce cleanup of third-party mise repo to avoid DNF version-lock collisions
    if [ -f /etc/yum.repos.d/mise.repo ]; then
        rm -f /etc/yum.repos.d/mise.repo
        dnf clean expire-cache >> "${LOG_FILE}" 2>&1 || true
    fi

    SYSTEM_PACKAGES=(
        # Shell, compilers, build utilities & runtime shared libraries
        "zsh" "git" "curl" "wget" "tar" "unzip" "p7zip" "p7zip-plugins" "jq"
        "make" "cmake" "clang" "ninja-build" "openssh-server" "libicu" "which"
        "xz" "gzip" "bzip2" "ca-certificates"
        # Modern CLI replacements
        "eza" "bat" "fzf" "ripgrep" "fd-find" "zoxide" "yazi"
        "direnv" "micro" "btop" "fastfetch" "inxi" "wl-clipboard" "poppler-utils"
        # Shell initialization and version management
        "starship" "atuin"
        # Fonts (Corrected packaging across Terra & Fedora official)
        "firacode-nerd-fonts" "rsms-inter-vf-fonts" "google-carlito-fonts" "google-caladea-fonts"
    )

    run_task "Installing core tooling, libraries, and fonts..." \
        "dnf install -y --skip-unavailable ${SYSTEM_PACKAGES[*]}"

    # Safe idempotent installation of mise from native Fedora/Terra repos
    if ! rpm -q mise >/dev/null 2>&1; then
        run_task "Installing Mise version manager..." "dnf install -y mise"
    fi

    fc-cache -f >> "${LOG_FILE}" 2>&1
    systemctl enable --now sshd >> "${LOG_FILE}" 2>&1

    TARGET_ZSH=$(command -v zsh)
    CURRENT_SHELL=$(getent passwd "${REAL_USER}" | cut -d: -f7)
    if [ "${CURRENT_SHELL}" != "${TARGET_ZSH}" ]; then
        usermod -s "${TARGET_ZSH}" "${REAL_USER}"
        log "INFO" "Default shell for ${REAL_USER} set to ${TARGET_ZSH}"
    fi

    mark_step_completed "cli_core_tooling"
    gum style --foreground 82 "✔ CLI toolchains, fonts, and Zsh configured."
fi

# ------------------------------------------------------------------------------
# 7. INTERACTIVE BASIC DESKTOP APPLICATIONS
# ------------------------------------------------------------------------------
if ! is_step_completed "desktop_software"; then
    gum style --foreground 39 "==> Phase 5: Graphical Desktop Applications"

    BROWSER_CHOICE=$(gum choose --header "Select a Primary Web Browser:" \
        "Firefox (Native RPM)" \
        "Chromium (Native RPM)" \
        "Brave Browser (Official RPM Repo)" \
        "Google Chrome (Official RPM Repo)" \
        "Skip" || echo "Skip")

    case "${BROWSER_CHOICE}" in
        "Firefox (Native RPM)")
            run_task "Installing Firefox..." "dnf install -y firefox"
            ;;
        "Chromium (Native RPM)")
            run_task "Installing Chromium..." "dnf install -y chromium"
            ;;
        "Brave Browser (Official RPM Repo)")
            run_task "Installing Brave Browser..." '
                cat <<EOF > /etc/yum.repos.d/brave-browser.repo
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF
                dnf install -y brave-browser
            '
            ;;
        "Google Chrome (Official RPM Repo)")
            run_task "Installing Google Chrome..." '
                cat <<EOF > /etc/yum.repos.d/google-chrome.repo
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
                dnf install -y google-chrome-stable
            '
            ;;
    esac

    FM_CHOICE=$(gum choose --header "Select a Graphical File Manager:" \
        "Nautilus (GNOME Files)" \
        "Thunar (XFCE - Lightweight)" \
        "Dolphin (KDE)" \
        "Skip" || echo "Skip")

    case "${FM_CHOICE}" in
        "Nautilus (GNOME Files)")
            run_task "Installing Nautilus..." "dnf install -y nautilus"
            ;;
        "Thunar (XFCE - Lightweight)")
            run_task "Installing Thunar..." "dnf install -y thunar"
            ;;
        "Dolphin (KDE)")
            run_task "Installing Dolphin..." "dnf install -y dolphin"
            ;;
    esac

    OFFICE_CHOICES=$(gum choose --no-limit --header "Select Desktop & Productivity Utilities:" \
        "Kitty Terminal" \
        "LibreOffice Suite" \
        "Evince (Document & PDF Viewer)" \
        "File Roller (Archive GUI)" \
        "Gedit (Text Editor)" \
        "MPV & qBittorrent" \
        "Foliate (E-Book Reader)" || echo "")

    if echo "${OFFICE_CHOICES}" | grep -q "Kitty Terminal"; then
        run_task "Installing Kitty Terminal..." "dnf install -y kitty"
    fi
    if echo "${OFFICE_CHOICES}" | grep -q "LibreOffice Suite"; then
        run_task "Installing LibreOffice..." "dnf install -y libreoffice"
    fi
    if echo "${OFFICE_CHOICES}" | grep -q "Evince"; then
        run_task "Installing Evince..." "dnf install -y evince"
    fi
    if echo "${OFFICE_CHOICES}" | grep -q "File Roller"; then
        run_task "Installing File Roller..." "dnf install -y file-roller"
    fi
    if echo "${OFFICE_CHOICES}" | grep -q "Gedit"; then
        run_task "Installing Gedit..." "dnf install -y gedit"
    fi
    if echo "${OFFICE_CHOICES}" | grep -q "MPV & qBittorrent"; then
        run_task "Installing MPV and qBittorrent..." "dnf install -y mpv qbittorrent"
    fi
    if echo "${OFFICE_CHOICES}" | grep -q "Foliate"; then
        run_task "Installing Foliate..." "dnf install -y foliate"
    fi

    mark_step_completed "desktop_software"
    gum style --foreground 82 "✔ Desktop applications configured."
fi

# ------------------------------------------------------------------------------
# 8. CONTAINER INFRASTRUCTURE (DOCKER CE & PODMAN)
# ------------------------------------------------------------------------------
if ! is_step_completed "container_engines"; then
    gum style --foreground 39 "==> Phase 6: Container Engines"

    CONTAINER_CHOICES=$(gum choose --no-limit --header "Select Container Technologies to Configure:" \
        "Podman (Native Rootless Engine, CLI & Compose)" \
        "Docker CE (Docker Daemon & Official CLI Plugin)" \
        "Podman Desktop (Container GUI via Flathub)" || echo "")

    if echo "${CONTAINER_CHOICES}" | grep -q "Podman (Native"; then
        run_task "Configuring Podman & Rootless Socket..." '
            dnf install -y podman podman-compose buildah skopeo
            loginctl enable-linger "'"${REAL_USER}"'"
        '
        sudo -u "${REAL_USER}" -H XDG_RUNTIME_DIR="/run/user/${REAL_UID}" systemctl --user enable --now podman.socket >> "${LOG_FILE}" 2>&1 || true
        gum style --foreground 82 "✔ Podman rootless socket active."
    fi

    if echo "${CONTAINER_CHOICES}" | grep -q "Docker CE"; then
        run_task "Installing Docker CE engine..." '
            cat <<EOF > /etc/yum.repos.d/docker-ce.repo
[docker-ce-stable]
name=Docker CE Stable - \$basearch
baseurl=https://download.docker.com/linux/fedora/\$releasever/\$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/fedora/gpg
EOF
            if ! dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
                dnf install -y moby-engine docker-compose
            fi
            systemctl enable --now docker
            usermod -aG docker "'"${REAL_USER}"'"
        '
        gum style --foreground 82 "✔ Docker CE daemon active. Added ${REAL_USER} to docker group."
    fi

    if echo "${CONTAINER_CHOICES}" | grep -q "Podman Desktop"; then
        run_task "Installing Podman Desktop..." '
            flatpak install -y flathub io.podman_desktop.PodmanDesktop
        '
        gum style --foreground 82 "✔ Podman Desktop installed via Flathub."
    fi

    mark_step_completed "container_engines"
fi

# ------------------------------------------------------------------------------
# 9. DEVELOPER IDES (VS CODE & JETBRAINS RIDER ARCHIVE)
# ------------------------------------------------------------------------------
if ! is_step_completed "developer_ides"; then
    gum style --foreground 39 "==> Phase 7: Developer IDEs & Tools"

    DEV_CHOICES=$(gum choose --no-limit --header "Select Developer Software to Install:" \
        "Visual Studio Code (Official Microsoft RPM)" \
        "JetBrains Rider (Standalone Tarball Archive + Desktop Entry)" \
        "DBeaver Community (Database Manager via Flathub)" \
        "Postman (API Client via Flathub)" || echo "")

    if echo "${DEV_CHOICES}" | grep -q "Visual Studio Code"; then
        run_task "Configuring Microsoft repository and installing VS Code..." '
            rpm --import https://packages.microsoft.com/keys/microsoft.asc
            cat <<EOF > /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
            dnf install -y code
        '
        gum style --foreground 82 "✔ Visual Studio Code installed."
    fi

    if echo "${DEV_CHOICES}" | grep -q "JetBrains Rider"; then
        if [ -f "/opt/rider/bin/rider.sh" ]; then
            gum style --foreground 82 "✔ JetBrains Rider already installed at /opt/rider."
        else
            RIDER_DL_URL=$(curl -fsSL "https://data.services.jetbrains.com/products/releases?code=RD&latest=true&type=release" | jq -r '.RD[0].downloads.linux.link // empty')

            if [ -z "${RIDER_DL_URL}" ]; then
                gum style --foreground 196 "✘ Unable to resolve Rider download URL from JetBrains API. Skipping."
            else
                run_task "Downloading and extracting JetBrains Rider to /opt/rider..." '
                    mkdir -p /opt/rider
                    curl -fsSL "'"${RIDER_DL_URL}"'" -o /tmp/rider.tar.gz
                    tar -xzf /tmp/rider.tar.gz -C /opt/rider --strip-components=1
                    rm -f /tmp/rider.tar.gz
                    ln -sf /opt/rider/bin/rider.sh /usr/local/bin/rider
                    chmod -R 755 /opt/rider
                '

                RIDER_ICON="/opt/rider/bin/rider.svg"
                if [ ! -f "${RIDER_ICON}" ]; then
                    RIDER_ICON="/opt/rider/bin/rider.png"
                fi

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
                gum style --foreground 82 "✔ JetBrains Rider deployed to /opt/rider with desktop integration."
            fi
        fi
    fi

    if echo "${DEV_CHOICES}" | grep -q "DBeaver Community"; then
        run_task "Installing DBeaver Community..." '
            flatpak install -y flathub io.dbeaver.DBeaverCommunity
        '
        gum style --foreground 82 "✔ DBeaver Community installed."
    fi

    if echo "${DEV_CHOICES}" | grep -q "Postman"; then
        run_task "Installing Postman..." '
            flatpak install -y flathub com.getpostman.Postman
        '
        gum style --foreground 82 "✔ Postman installed."
    fi

    mark_step_completed "developer_ides"
fi

# ------------------------------------------------------------------------------
# 10. DEPLOY DOTFILES, ZINIT FRAMEWORK & KITTY
# ------------------------------------------------------------------------------
if ! is_step_completed "dotfiles_zinit_config"; then
    gum style --foreground 39 "==> Phase 8: Deploying User Dotfiles & Configurations"

    ZINIT_TARGET_DIR="${REAL_HOME}/.local/share/zinit/zinit.git"
    if [ ! -d "${ZINIT_TARGET_DIR}" ]; then
        run_task "Cloning Zinit core..." '
            sudo -u "'"${REAL_USER}"'" -H mkdir -p "$(dirname "'"${ZINIT_TARGET_DIR}"'")"
            sudo -u "'"${REAL_USER}"'" -H git clone https://github.com/zdharma-continuum/zinit.git "'"${ZINIT_TARGET_DIR}"'"
        '
    fi

    backup_file "${REAL_HOME}/.zsh_aliases"
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

    backup_file "${REAL_HOME}/.zshrc"
    cat <<'EOF' > "${REAL_HOME}/.zshrc"
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
    /usr/local/bin
    $path
)

# ==============================================================================
# ZINIT INSTALLATION & BOOTSTRAP
# ==============================================================================
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"

# Load core annexes
zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust

# ==============================================================================
# OH-MY-ZSH LIBRARIES & PLUGINS (Synchronous)
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

command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
command -v atuin >/dev/null 2>&1 && eval "$(atuin init zsh)"

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
[[ "$TERM_PROGRAM" == "vscode" ]] && command -v code >/dev/null 2>&1 && . "$(code --locate-shell-integration-path zsh)"
EOF
    chown "${REAL_USER}:${REAL_USER}" "${REAL_HOME}/.zshrc"
    chmod 644 "${REAL_HOME}/.zshrc"

    KITTY_CONFIG_DIR="${REAL_HOME}/.config/kitty"
    backup_file "${KITTY_CONFIG_DIR}/kitty.conf"
    run_as_user "mkdir -p '${KITTY_CONFIG_DIR}'"

    cat <<'EOF' > "${KITTY_CONFIG_DIR}/kitty.conf"
# Font Configuration
font_size 12.0
disable_ligatures never

# Window Configuration
window_padding_width 12
background_opacity 1.0
background_blur 32
hide_window_decorations yes

# Cursor Configuration
cursor_shape block
cursor_blink_interval 1

# Scrollback
scrollback_lines 3000

# Terminal features
copy_on_select yes
strip_trailing_spaces smart

# Key bindings for common actions
map ctrl+shift+n new_window
map ctrl+t new_tab
map ctrl+plus change_font_size all +1.0
map ctrl+minus change_font_size all -1.0
map ctrl+0 change_font_size all 0

# --- Performance & Mouse ---
repaint_delay    10
input_delay      3
sync_to_monitor  yes
detect_urls      yes

# --- Cursor Customization ---
cursor_shape          block
cursor_blink_interval 0.5
cursor_stop_blinking_after 15.0
cursor_trail 3
cursor_trail_decay 0.1 0.4

# Tab configuration
tab_bar_style powerline
tab_bar_align left

# Shell integration
shell_integration enabled

# Dank color generation
include dank-tabs.conf
include dank-theme.conf

# BEGIN_KITTY_FONTS
font_family      family="FiraCode Nerd Font"
bold_font        auto
italic_font      auto
bold_italic_font auto
# END_KITTY_FONTS

# BEGIN_KITTY_THEME
include current-theme.conf
# END_KITTY_THEME
EOF
    touch "${KITTY_CONFIG_DIR}/dank-tabs.conf" "${KITTY_CONFIG_DIR}/dank-theme.conf" "${KITTY_CONFIG_DIR}/current-theme.conf"
    chown -R "${REAL_USER}:${REAL_USER}" "${KITTY_CONFIG_DIR}"

    mark_step_completed "dotfiles_zinit_config"
    gum style --foreground 82 "✔ Dotfiles, shell configs, and Kitty profile deployed."
fi

# ------------------------------------------------------------------------------
# 11. GIT CREDENTIALS & SSH KEYPAIR GENERATION
# ------------------------------------------------------------------------------
if ! is_step_completed "git_ssh_identity"; then
    gum style --foreground 39 "==> Phase 9: Git & SSH Credentials"

    CURRENT_GIT_NAME=$(run_as_user "git config --global user.name || true")
    CURRENT_GIT_EMAIL=$(run_as_user "git config --global user.email || true")

    PROMPT_NAME=$(gum input --value "${CURRENT_GIT_NAME}" --prompt "Enter Git author name: " || echo "${CURRENT_GIT_NAME}")
    PROMPT_EMAIL=$(gum input --value "${CURRENT_GIT_EMAIL}" --prompt "Enter Git author email: " || echo "${CURRENT_GIT_EMAIL}")

    if [ -n "${PROMPT_NAME}" ] && [ -n "${PROMPT_EMAIL}" ]; then
        run_as_user "git config --global user.name '${PROMPT_NAME}'"
        run_as_user "git config --global user.email '${PROMPT_EMAIL}'"
        run_as_user "git config --global init.defaultBranch main"
    fi

    USER_SSH_DIR="${REAL_HOME}/.ssh"
    if [ ! -f "${USER_SSH_DIR}/id_ed25519" ]; then
        if gum confirm "Generate a new Ed25519 SSH keypair?"; then
            run_as_user "mkdir -p '${USER_SSH_DIR}' && chmod 700 '${USER_SSH_DIR}'"
            run_as_user "ssh-keygen -t ed25519 -C '${PROMPT_EMAIL}' -f '${USER_SSH_DIR}/id_ed25519' -N ''"
            
            if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
                run_as_user "wl-copy < '${USER_SSH_DIR}/id_ed25519.pub' || true"
            fi
            gum style --foreground 82 "✔ Generated ~/.ssh/id_ed25519"
        fi
    fi

    mark_step_completed "git_ssh_identity"
fi

# ------------------------------------------------------------------------------
# 12. MISE LANGUAGE RUNTIME PROVISIONING (IDEMPOTENT)
# ------------------------------------------------------------------------------
if ! is_step_completed "runtime_stacks"; then
    gum style --foreground 39 "==> Phase 10: Language Runtimes (Mise)"

    if gum confirm "Install/Verify standard runtimes (dotnet@lts, node@lts, java@lts) via Mise?"; then
        # Ensure mise trusts and executes runtimes cleanly without non-interactive hangs
        run_task "Provisioning developer SDKs via Mise..." '
            sudo -u "'"${REAL_USER}"'" -H mise settings set idiomatic_version_file false
            sudo -u "'"${REAL_USER}"'" -H mise settings set yes true
            sudo -u "'"${REAL_USER}"'" -H mise use --global dotnet@lts node@lts java@lts
        '
        gum style --foreground 82 "✔ Global runtimes active (.NET LTS, Node LTS, Java LTS)."
    fi

    mark_step_completed "runtime_stacks"
fi

# ------------------------------------------------------------------------------
# 13. COMPLETION & REBOOT
# ------------------------------------------------------------------------------
cd "${REAL_HOME}"
log "INFO" "Setup script finished successfully."

gum style \
    --foreground 82 --border-foreground 82 --border normal \
    --align center --width 75 --padding "1 2" \
    "Installation & Environment Bootstrap Complete!" \
    "Log Output: ${LOG_FILE}" \
    "Rollback & Config Backups: ${BACKUP_DIR}"

if gum confirm "Reboot system now to apply shell, group, and driver updates?"; then
    gum style --foreground 214 "Rebooting system..."
    reboot
fi

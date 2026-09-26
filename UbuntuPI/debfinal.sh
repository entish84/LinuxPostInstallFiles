#!/usr/bin/env bash
# ==============================================================================
# Debian / Debian-based Distros Post-Installation & Developer Setup
# ==============================================================================

set -euo pipefail

# --- Early Help Check ---
for arg in "$@"; do
    case "${arg}" in
        -h|--help)
            cat <<EOF
Usage: sudo $(basename "$0") [OPTIONS]

Post-installation & developer environment bootstrap script for Debian-based systems.

Options:
  -y, --yes, --all        Install all components including all IDEs and Desktop Apps (non-interactive)
  --default               Run non-interactively using safe defaults (skips IDEs and Desktop Apps)
  --desktop-apps          Install Desktop GUI Applications (Kitty, Foliate, qBittorrent, MPV)
  --no-desktop-apps       Skip Desktop GUI Applications
  --ides                  Install all IDEs (VS Code, Antigravity, Rider, Android Studio)
  --no-ides               Skip all IDEs
  --vscode                Install Visual Studio Code
  --no-vscode             Skip Visual Studio Code
  --antigravity           Install Google Antigravity IDE
  --no-antigravity        Skip Google Antigravity IDE
  --rider                 Install JetBrains Rider
  --no-rider              Skip JetBrains Rider
  --studio                Install Android Studio
  --no-studio             Skip Android Studio
  -h, --help              Display this help message and exit

If run in an interactive terminal without flags, you will be prompted for IDEs and Desktop Apps.
In non-interactive environments without flags, IDEs and Desktop Apps default to 'no'.
EOF
            exit 0
            ;;
    esac
done

# --- 0. Root Check & User Resolution ---
if [ "${EUID}" -ne 0 ]; then
    echo "Error: This script must be run with sudo or as root." >&2
    exit 1
fi

# Detect the non-root invoking user
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    REAL_USER="${SUDO_USER}"
else
    REAL_USER=$(logname 2>/dev/null || who | awk '{print $1}' | head -n 1 || true)
    if [ -z "${REAL_USER}" ] || [ "${REAL_USER}" = "root" ]; then
        REAL_USER=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd || echo "root")
    fi
fi

REAL_HOME=$(getent passwd "${REAL_USER}" | cut -d: -f6)
REAL_UID=$(id -u "${REAL_USER}")
LOG_FILE="/var/log/debian_post_install.log"
INITIAL_DIR="$(pwd)"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo "amd64")"

# Configure Logging
mkdir -p "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"
chmod 600 "${LOG_FILE}"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "===================================================================="
echo " Starting Debian Post-Installation Setup for user: ${REAL_USER}"
echo " Architecture: ${ARCH} | Date: $(date)"
echo " Log file: ${LOG_FILE}"
echo "===================================================================="

# Helper function to execute commands in the context of the target user
run_user() {
    if [ "${REAL_USER}" = "root" ]; then
        bash -c "$*"
    else
        sudo -u "${REAL_USER}" -H bash -c "$*"
    fi
}

prompt_yn() {
    local prompt_msg="$1"
    local default_ans="${2:-n}"
    local ans=""

    if [ "${NON_INTERACTIVE:-0}" -eq 1 ] || { [ ! -t 0 ] && ! (exec </dev/tty) 2>/dev/null; }; then
        echo "${prompt_msg} (defaulting to ${default_ans})"
        [[ "${default_ans}" =~ ^[Yy]$ ]] && return 0 || return 1
    fi

    if [ -t 0 ]; then
        read -r -p "${prompt_msg} " ans || ans="${default_ans}"
    else
        read -r -p "${prompt_msg} " ans </dev/tty 2>/dev/null || ans="${default_ans}"
    fi

    ans="${ans:-${default_ans}}"
    [[ "${ans}" =~ ^[Yy]$ ]]
}

prompt_reboot() {
    local choice=""
    if [ "${NON_INTERACTIVE:-0}" -eq 1 ]; then
        echo "Non-interactive execution completed: skipping automatic reboot."
        return 0
    fi
    if [ -t 0 ]; then
        read -r -p "It is time to reboot the machine. Would you like to do it now? (y/n): " choice || choice="n"
    elif (exec </dev/tty) 2>/dev/null; then
        read -r -p "It is time to reboot the machine. Would you like to do it now? (y/n): " choice </dev/tty 2>/dev/null || choice="n"
    else
        choice="n"
    fi

    if [[ "${choice}" =~ ^[Yy]$ ]]; then
        echo "Rebooting..."
        reboot 2>/dev/null || systemctl reboot 2>/dev/null || echo "Please reboot manually."
    else
        echo "Reboot canceled."
    fi
}

# --- CLI Options & User Intervention Configuration ---
INSTALL_DESKTOP_APPS=""
INSTALL_VSCODE=""
INSTALL_ANTIGRAVITY=""
INSTALL_RIDER=""
INSTALL_STUDIO=""
NON_INTERACTIVE=0

show_help() {
    cat <<EOF
Usage: sudo $(basename "$0") [OPTIONS]

Post-installation & developer environment bootstrap script for Debian-based systems.

Options:
  -y, --yes, --all        Install all components including all IDEs and Desktop Apps (non-interactive)
  --default               Run non-interactively using safe defaults (skips IDEs and Desktop Apps)
  --desktop-apps          Install Desktop GUI Applications (Kitty, Foliate, qBittorrent, MPV)
  --no-desktop-apps       Skip Desktop GUI Applications
  --ides                  Install all IDEs (VS Code, Antigravity, Rider, Android Studio)
  --no-ides               Skip all IDEs
  --vscode                Install Visual Studio Code
  --no-vscode             Skip Visual Studio Code
  --antigravity           Install Google Antigravity IDE
  --no-antigravity        Skip Google Antigravity IDE
  --rider                 Install JetBrains Rider
  --no-rider              Skip JetBrains Rider
  --studio                Install Android Studio
  --no-studio             Skip Android Studio
  -h, --help              Display this help message and exit

If run in an interactive terminal without flags, you will be prompted for IDEs and Desktop Apps.
In non-interactive environments without flags, IDEs and Desktop Apps default to 'no'.
EOF
    exit 0
}

# Parse Command-Line Arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes|--all)
            INSTALL_DESKTOP_APPS=1
            INSTALL_VSCODE=1
            INSTALL_ANTIGRAVITY=1
            INSTALL_RIDER=1
            INSTALL_STUDIO=1
            NON_INTERACTIVE=1
            ;;
        --default|--non-interactive)
            NON_INTERACTIVE=1
            ;;
        --desktop-apps)
            INSTALL_DESKTOP_APPS=1
            ;;
        --no-desktop-apps)
            INSTALL_DESKTOP_APPS=0
            ;;
        --ides)
            INSTALL_VSCODE=1
            INSTALL_ANTIGRAVITY=1
            INSTALL_RIDER=1
            INSTALL_STUDIO=1
            ;;
        --no-ides)
            INSTALL_VSCODE=0
            INSTALL_ANTIGRAVITY=0
            INSTALL_RIDER=0
            INSTALL_STUDIO=0
            ;;
        --vscode)
            INSTALL_VSCODE=1
            ;;
        --no-vscode)
            INSTALL_VSCODE=0
            ;;
        --antigravity)
            INSTALL_ANTIGRAVITY=1
            ;;
        --no-antigravity)
            INSTALL_ANTIGRAVITY=0
            ;;
        --rider)
            INSTALL_RIDER=1
            ;;
        --no-rider)
            INSTALL_RIDER=0
            ;;
        --studio)
            INSTALL_STUDIO=1
            ;;
        --no-studio)
            INSTALL_STUDIO=0
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run '$0 --help' for usage." >&2
            exit 1
            ;;
    esac
    shift
done

# --- Interactive Prompts (if not specified via flags) ---
if [ -z "${INSTALL_DESKTOP_APPS}" ]; then
    echo ""
    if prompt_yn "Install Desktop GUI Applications (Kitty, Foliate, qBittorrent, MPV)? [y/N]:" "n"; then
        INSTALL_DESKTOP_APPS=1
    else
        INSTALL_DESKTOP_APPS=0
    fi
fi

if [ -z "${INSTALL_VSCODE}" ] || [ -z "${INSTALL_ANTIGRAVITY}" ] || [ -z "${INSTALL_RIDER}" ] || [ -z "${INSTALL_STUDIO}" ]; then
    echo ""
    if prompt_yn "Configure and install Development IDEs? [y/N]:" "n"; then
        if prompt_yn "  Install ALL available IDEs (VS Code, Antigravity, Rider, Android Studio)? [y/N]:" "n"; then
            INSTALL_VSCODE="${INSTALL_VSCODE:-1}"
            INSTALL_ANTIGRAVITY="${INSTALL_ANTIGRAVITY:-1}"
            INSTALL_RIDER="${INSTALL_RIDER:-1}"
            INSTALL_STUDIO="${INSTALL_STUDIO:-1}"
        else
            if [ -z "${INSTALL_VSCODE}" ]; then
                prompt_yn "    Install Visual Studio Code? [y/N]:" "n" && INSTALL_VSCODE=1 || INSTALL_VSCODE=0
            fi
            if [ -z "${INSTALL_ANTIGRAVITY}" ]; then
                prompt_yn "    Install Google Antigravity IDE? [y/N]:" "n" && INSTALL_ANTIGRAVITY=1 || INSTALL_ANTIGRAVITY=0
            fi
            if [ -z "${INSTALL_RIDER}" ]; then
                prompt_yn "    Install JetBrains Rider (.NET IDE)? [y/N]:" "n" && INSTALL_RIDER=1 || INSTALL_RIDER=0
            fi
            if [ -z "${INSTALL_STUDIO}" ]; then
                prompt_yn "    Install Android Studio? [y/N]:" "n" && INSTALL_STUDIO=1 || INSTALL_STUDIO=0
            fi
        fi
    else
        INSTALL_VSCODE="${INSTALL_VSCODE:-0}"
        INSTALL_ANTIGRAVITY="${INSTALL_ANTIGRAVITY:-0}"
        INSTALL_RIDER="${INSTALL_RIDER:-0}"
        INSTALL_STUDIO="${INSTALL_STUDIO:-0}"
    fi
fi

INSTALL_DESKTOP_APPS="${INSTALL_DESKTOP_APPS:-0}"
INSTALL_VSCODE="${INSTALL_VSCODE:-0}"
INSTALL_ANTIGRAVITY="${INSTALL_ANTIGRAVITY:-0}"
INSTALL_RIDER="${INSTALL_RIDER:-0}"
INSTALL_STUDIO="${INSTALL_STUDIO:-0}"

fmt_opt() { [ "$1" -eq 1 ] && echo "YES" || echo "NO"; }

echo ""
echo "===================================================================="
echo " Post-Installation Configuration Summary:"
echo "   Desktop GUI Apps (Kitty/MPV/etc): $(fmt_opt "${INSTALL_DESKTOP_APPS}")"
echo "   Visual Studio Code:               $(fmt_opt "${INSTALL_VSCODE}")"
echo "   Google Antigravity IDE:           $(fmt_opt "${INSTALL_ANTIGRAVITY}")"
echo "   JetBrains Rider (.NET):           $(fmt_opt "${INSTALL_RIDER}")"
echo "   Android Studio:                   $(fmt_opt "${INSTALL_STUDIO}")"
echo "===================================================================="
echo ""

# --- 1. Clean Conflicting Repositories & Legacy Packages ---
echo "--- 1. Cleaning legacy packages and old repository lists ---"
rm -f /etc/apt/sources.list.d/docker*.list
rm -f /etc/apt/sources.list.d/mise*.list
rm -f /etc/apt/sources.list.d/gierens*.list
if [ "${INSTALL_VSCODE}" -eq 1 ]; then
    rm -f /etc/apt/sources.list.d/vscode*.list
fi
if [ "${INSTALL_ANTIGRAVITY}" -eq 1 ]; then
    rm -f /etc/apt/sources.list.d/antigravity*.list
fi

# Remove unofficial/conflicting legacy Docker packages
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    dpkg -s "${pkg}" >/dev/null 2>&1 && apt-get remove -y "${pkg}" 2>/dev/null || true
done

# Hostname setup (retains rspc or existing)
TARGET_HOSTNAME="${TARGET_HOSTNAME:-rspc}"
if command -v hostnamectl >/dev/null 2>&1 && [ -n "${TARGET_HOSTNAME}" ]; then
    hostnamectl set-hostname "${TARGET_HOSTNAME}" 2>/dev/null || true
fi

# --- 2. Configure APT & Enable Repositories ---
echo "--- 2. Configuring APT settings and repositories ---"
export DEBIAN_FRONTEND=noninteractive

# Optimized APT configuration
cat <<'EOF' > /etc/apt/apt.conf.d/99post-install
Acquire::Languages "none";
Acquire::Retries "3";
APT::Color "1";
Dpkg::Progress-Fancy "1";
EOF

# Enable contrib, non-free, and non-free-firmware for Debian, or universe/multiverse for Ubuntu
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
    # Modern deb822 format (Debian 12/13+)
    sed -i -E 's/^Components: main(\s*)$/Components: main contrib non-free non-free-firmware\1/' /etc/apt/sources.list.d/debian.sources
fi
if [ -f /etc/apt/sources.list ]; then
    sed -i -E 's/^(deb .* main)$/\1 contrib non-free non-free-firmware/' /etc/apt/sources.list
fi

# If Ubuntu or derivative, ensure universe & multiverse are enabled
if command -v add-apt-repository >/dev/null 2>&1; then
    add-apt-repository -y universe 2>/dev/null || true
    add-apt-repository -y multiverse 2>/dev/null || true
fi

# Pre-accept MS TrueType Core Fonts EULA so debconf never hangs
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections 2>/dev/null || true

# Pre-requisite bootstrap packages
apt-get update -y
apt-get install -y --no-install-recommends \
    ca-certificates curl wget gpg gpg-agent apt-transport-https lsb-release
apt-get install -y --no-install-recommends software-properties-common 2>/dev/null || true

# Setup keyrings directory with secure permissions
install -d -m 0755 /etc/apt/keyrings

# --- 3. Third-Party Repositories Setup (IDEs, Docker, Mise, Eza) ---
echo "--- 3. Configuring Official Third-Party Repositories ---"

# 3.1 Visual Studio Code (if selected)
if [ "${INSTALL_VSCODE}" -eq 1 ]; then
    echo "Adding Visual Studio Code repository..."
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg
    chmod 644 /etc/apt/keyrings/packages.microsoft.gpg
    echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
    chmod 644 /etc/apt/sources.list.d/vscode.list
fi

# 3.2 Google Antigravity IDE (if selected)
if [ "${INSTALL_ANTIGRAVITY}" -eq 1 ]; then
    echo "Adding Google Antigravity IDE repository..."
    curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
    chmod 644 /etc/apt/keyrings/antigravity-repo-key.gpg
    echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" > /etc/apt/sources.list.d/antigravity.list
    chmod 644 /etc/apt/sources.list.d/antigravity.list
fi

# 3.3 Docker CE
echo "Adding Docker CE repository..."
DISTRO_ID="debian"
SUITE_CODENAME="bookworm"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID:-debian}"
    SUITE_CODENAME="${VERSION_CODENAME:-bookworm}"
fi

case "${DISTRO_ID}" in
    ubuntu)
        DOCKER_GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
        DOCKER_REPO_URL="https://download.docker.com/linux/ubuntu"
        DOCKER_SUITE="${UBUNTU_CODENAME:-${SUITE_CODENAME:-noble}}"
        ;;
    debian|*)
        DOCKER_GPG_URL="https://download.docker.com/linux/debian/gpg"
        DOCKER_REPO_URL="https://download.docker.com/linux/debian"
        DOCKER_SUITE="${SUITE_CODENAME}"
        case "${DOCKER_SUITE}" in
            sid|testing|unstable) DOCKER_SUITE="trixie" ;;
        esac
        ;;
esac

curl -fsSL "${DOCKER_GPG_URL}" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] ${DOCKER_REPO_URL} ${DOCKER_SUITE} stable" > /etc/apt/sources.list.d/docker.list
chmod 644 /etc/apt/sources.list.d/docker.list

# 3.4 Mise Runtime Manager
echo "Adding Mise repository..."
curl -fsSL https://mise.jdx.dev/gpg-key.pub | gpg --dearmor --yes -o /etc/apt/keyrings/mise-archive-keyring.gpg
chmod 644 /etc/apt/keyrings/mise-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=${ARCH}] https://mise.jdx.dev/deb stable main" > /etc/apt/sources.list.d/mise.list
chmod 644 /etc/apt/sources.list.d/mise.list

# 3.5 Eza (Modern ls replacement)
if ! apt-cache show eza >/dev/null 2>&1; then
    echo "Adding Eza repository..."
    curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor --yes -o /etc/apt/keyrings/gierens.gpg
    chmod 644 /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" > /etc/apt/sources.list.d/gierens.list
    chmod 644 /etc/apt/sources.list.d/gierens.list
fi

# Refresh repository indices after adding all keys
apt-get update -y

# --- 4. Base System Upgrade ---
echo "--- 4. Upgrading base system packages ---"
apt-get dist-upgrade -y

# --- 5. Flatpak & Flathub ---
echo "--- 5. Configuring Flatpak & Flathub ---"
apt-get install -y flatpak
apt-get install -y gnome-software-plugin-flatpak 2>/dev/null || true
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
flatpak repair 2>/dev/null || true

# --- 6. OpenSSH Server ---
echo "--- 6. Installing and enabling OpenSSH Server ---"
apt-get install -y openssh-server
systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true

# --- 7. Multimedia Codecs & Hardware Acceleration ---
echo "--- 7. Installing Multimedia Codecs and Hardware Accelerated Drivers ---"
apt-get install -y \
    ffmpeg \
    libavcodec-extra \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    mesa-va-drivers \
    mesa-vdpau-drivers \
    va-driver-all \
    vdpau-driver-all 2>/dev/null || true

# --- 8. Virtualization Stack ---
echo "--- 8. Installing Virtualization Tools ---"
apt-get install -y \
    qemu-system \
    qemu-utils \
    libvirt-daemon-system \
    libvirt-clients \
    bridge-utils \
    virt-manager 2>/dev/null || true

systemctl enable --now libvirtd 2>/dev/null || true
usermod -aG libvirt "${REAL_USER}" 2>/dev/null || true
usermod -aG kvm "${REAL_USER}" 2>/dev/null || true

# --- 9. Docker CE Installation ---
echo "--- 9. Installing Docker CE ---"
if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null; then
    apt-get install -y docker.io docker-compose 2>/dev/null || true
fi

systemctl enable --now docker 2>/dev/null || true
systemctl enable --now containerd 2>/dev/null || true

getent group docker >/dev/null 2>&1 || groupadd docker
usermod -aG docker "${REAL_USER}" 2>/dev/null || true
rm -rf "${REAL_HOME}/.docker"

# --- 10. Core Packages & Fonts ---
echo "--- 10. Installing Core CLI, Compilers, and Fonts ---"
CORE_PACKAGES=(
    # Core system & compilers
    git curl wget tar unzip 7zip jq
    make cmake clang ninja-build build-essential pkg-config
    xz-utils fontconfig sudo
    # Modern CLI / TUI tools
    bat fd-find fzf ripgrep zoxide direnv micro btop inxi
    wl-clipboard xclip poppler-utils eza mise
    # System fonts & themes
    fonts-firacode fonts-inter papirus-icon-theme
)

apt-get install -y "${CORE_PACKAGES[@]}" 2>/dev/null || true

# Compatibility symlinks for bat and fd in Debian
if [ -f /usr/bin/batcat ] && [ ! -f /usr/local/bin/bat ]; then
    ln -sf /usr/bin/batcat /usr/local/bin/bat
fi
if [ -f /usr/bin/fdfind ] && [ ! -f /usr/local/bin/fd ]; then
    ln -sf /usr/bin/fdfind /usr/local/bin/fd
fi

# Ensure user is in sudo group
usermod -aG sudo "${REAL_USER}" 2>/dev/null || true

# --- 11. Productivity & Development Software ---
echo "--- 11. Installing Shell and Container Tools ---"
apt-get install -y zsh podman 2>/dev/null || true

if [ "${INSTALL_DESKTOP_APPS}" -eq 1 ]; then
    echo "Installing Desktop GUI Applications (Kitty, Foliate, qBittorrent, MPV)..."
    DESKTOP_PACKAGES=(
        kitty mpv foliate qbittorrent
    )
    apt-get install -y "${DESKTOP_PACKAGES[@]}" 2>/dev/null || true
else
    echo "Skipping Desktop GUI Applications as requested."
fi

# --- 12. Modern CLI Standalone Binaries (Starship, Yazi, Atuin, Fastfetch) ---
echo "--- 12. Installing Latest CLI Utilities ---"

# Starship prompt
if ! command -v starship >/dev/null 2>&1; then
    echo "Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y 2>/dev/null || true
fi

# Architecture mapping for Musl/Binary downloads
case "${ARCH}" in
    amd64)
        YAZI_ARCH="x86_64"
        ATUIN_ARCH="x86_64"
        ;;
    arm64)
        YAZI_ARCH="aarch64"
        ATUIN_ARCH="aarch64"
        ;;
    *)
        YAZI_ARCH="x86_64"
        ATUIN_ARCH="x86_64"
        ;;
esac

# Yazi file manager
if ! command -v yazi >/dev/null 2>&1; then
    echo "Installing Yazi file manager..."
    YAZI_URL=$(curl -fsSL https://api.github.com/repos/sxyazi/yazi/releases/latest 2>/dev/null | \
        jq -r --arg a "${YAZI_ARCH}" '.assets[] | select(.name | test($a + "-unknown-linux-musl\\.zip$")) | .browser_download_url' 2>/dev/null | head -n 1 || true)
    if [ -n "${YAZI_URL}" ]; then
        TMP_YAZI=$(mktemp -d)
        if curl -fsSL "${YAZI_URL}" -o "${TMP_YAZI}/yazi.zip"; then
            unzip -q -o "${TMP_YAZI}/yazi.zip" -d "${TMP_YAZI}"
            install -m 0755 "${TMP_YAZI}"/yazi-*/yazi /usr/local/bin/yazi 2>/dev/null || true
            install -m 0755 "${TMP_YAZI}"/yazi-*/ya /usr/local/bin/ya 2>/dev/null || true
        fi
        rm -rf "${TMP_YAZI}"
    fi
fi

# Atuin magical shell history
if ! command -v atuin >/dev/null 2>&1; then
    echo "Installing Atuin..."
    ATUIN_URL=$(curl -fsSL https://api.github.com/repos/atuinsh/atuin/releases/latest 2>/dev/null | \
        jq -r --arg a "${ATUIN_ARCH}" '.assets[] | select(.name | test("atuin-" + $a + "-unknown-linux-musl\\.tar\\.gz$")) | .browser_download_url' 2>/dev/null | head -n 1 || true)
    if [ -n "${ATUIN_URL}" ]; then
        TMP_ATUIN=$(mktemp -d)
        if curl -fsSL "${ATUIN_URL}" | tar -xz -C "${TMP_ATUIN}"; then
            install -m 0755 "${TMP_ATUIN}"/atuin-*/atuin /usr/local/bin/atuin 2>/dev/null || true
        fi
        rm -rf "${TMP_ATUIN}"
    else
        curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh 2>/dev/null | bash -s -- --non-interactive 2>/dev/null || true
    fi
fi

# Fastfetch system info
if ! command -v fastfetch >/dev/null 2>&1; then
    if ! apt-get install -y fastfetch 2>/dev/null; then
        echo "Fetching Fastfetch debian package..."
        FF_URL=$(curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest 2>/dev/null | \
            jq -r --arg a "${ARCH}" '.assets[] | select(.name | test("linux-" + $a + "\\.deb$")) | .browser_download_url' 2>/dev/null | head -n 1 || true)
        if [ -n "${FF_URL}" ]; then
            TMP_DEB=$(mktemp --suffix=.deb)
            if curl -fsSL "${FF_URL}" -o "${TMP_DEB}"; then
                dpkg -i "${TMP_DEB}" 2>/dev/null || apt-get install -fy 2>/dev/null || true
            fi
            rm -f "${TMP_DEB}"
        fi
    fi
fi

# --- 13. Desktop Fonts & Themes ---
echo "--- 13. Installing Desktop Fonts & Themes ---"
# Microsoft TrueType Core Fonts
apt-get install -y ttf-mscorefonts-installer 2>/dev/null || true

# Install Official Nerd Fonts (FiraCode & 0xProto) into system fonts directory
NERD_FONT_DIR="/usr/local/share/fonts/NerdFonts"
if [ ! -f "${NERD_FONT_DIR}/FiraCodeNerdFont-Regular.ttf" ]; then
    echo "Installing Nerd Fonts (FiraCode & 0xProto)..."
    mkdir -p "${NERD_FONT_DIR}"
    curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz | tar -xJ -C "${NERD_FONT_DIR}" 2>/dev/null || true
    curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/0xProto.tar.xz | tar -xJ -C "${NERD_FONT_DIR}" 2>/dev/null || true
    fc-cache -f 2>/dev/null || true
fi

# Apply Papirus icon theme for GNOME desktop if present
run_user "gsettings set org.gnome.desktop.interface icon-theme 'Papirus' 2>/dev/null || true"

# --- 14. Development IDEs ---
echo "--- 14. Development IDEs Setup ---"

# 14.1 Visual Studio Code
if [ "${INSTALL_VSCODE}" -eq 1 ]; then
    echo "Installing Visual Studio Code..."
    apt-get install -y code 2>/dev/null || echo "Warning: Failed to install Visual Studio Code."
else
    echo "Skipping Visual Studio Code."
fi

# 14.2 Google Antigravity IDE
if [ "${INSTALL_ANTIGRAVITY}" -eq 1 ]; then
    echo "Installing Google Antigravity IDE..."
    apt-get install -y antigravity 2>/dev/null || echo "Warning: Failed to install Google Antigravity IDE."
else
    echo "Skipping Google Antigravity IDE."
fi

# 14.3 JetBrains Rider
if [ "${INSTALL_RIDER}" -eq 1 ]; then
    if [ ! -f "/opt/rider/bin/rider.sh" ]; then
        echo "Installing JetBrains Rider..."
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
                command -v restorecon >/dev/null 2>&1 && restorecon -R /opt/rider /usr/local/bin/rider /usr/share/applications/jetbrains-rider.desktop 2>/dev/null || true
            fi
        fi
    else
        echo "JetBrains Rider is already installed at /opt/rider."
    fi
else
    echo "Skipping JetBrains Rider."
fi

# 14.4 Android Studio
if [ "${INSTALL_STUDIO}" -eq 1 ]; then
    if [ ! -f "/opt/android-studio/bin/studio.sh" ]; then
        echo "Installing Android Studio..."
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
                command -v restorecon >/dev/null 2>&1 && restorecon -R /opt/android-studio /usr/local/bin/studio /usr/share/applications/android-studio.desktop 2>/dev/null || true
            fi
        fi
    else
        echo "Android Studio is already installed at /opt/android-studio."
    fi
else
    echo "Skipping Android Studio."
fi

# Update desktop menus and KDE cache
update-desktop-database /usr/share/applications 2>/dev/null || true
run_user "kbuildsycoca6 2>/dev/null || kbuildsycoca5 2>/dev/null || true"

# --- 15. User Shell Configuration (ZSH) ---
echo "--- 15. Setting default shell to Zsh ---"
TARGET_ZSH=$(command -v zsh || echo "/usr/bin/zsh")
if [ -x "${TARGET_ZSH}" ]; then
    chsh -s "${TARGET_ZSH}" "${REAL_USER}" 2>/dev/null || usermod -s "${TARGET_ZSH}" "${REAL_USER}" 2>/dev/null || true
fi

# --- 16. Dotfiles & Shell Environment ---
echo "--- 16. Configuring Dotfiles & Shell Environment ---"

# 16.1 ~/.zsh_aliases
cat <<'EOF' > "${REAL_HOME}/.zsh_aliases"
# .NET Aliases
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

# Modern CLI Replacements
alias ls="eza -lh --color=auto --icons=auto --group-directories-first --git"
alias la="eza -lha --color=auto --icons=auto --group-directories-first"
alias lt="eza -a --tree --level=3 --long --icons --git"
alias grep="grep --color=auto"
alias cat='bat --paging=never'
alias less='bat --style=plain'
alias path='echo -e ${PATH//:/\\n}'

alias zshconfig="micro ~/.zshrc"
alias zshreload="source ~/.zshrc"

# Debian / APT Package Management Aliases
alias aptupd="sudo apt update && sudo apt upgrade -y"
alias aptclean="sudo apt autoremove -y && sudo apt clean"
alias aptin="sudo apt install -y"
alias aptrm="sudo apt remove -y"
alias aptsearch="apt search"
EOF
chown "${REAL_USER}:${REAL_USER}" "${REAL_HOME}/.zsh_aliases"
chmod 644 "${REAL_HOME}/.zsh_aliases"

# 17.2 Zinit Bootstrap & ~/.zshrc
ZINIT_TARGET_DIR="${REAL_HOME}/.local/share/zinit/zinit.git"
if [ ! -d "${ZINIT_TARGET_DIR}" ]; then
    echo "Bootstrapping Zinit plugin manager..."
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
[[ "$TERM_PROGRAM" == "antigravity" ]] && command -v antigravity >/dev/null 2>&1 && . "$(antigravity --locate-shell-integration-path zsh 2>/dev/null)" 2>/dev/null || true
EOF
chown "${REAL_USER}:${REAL_USER}" "${REAL_HOME}/.zshrc"
chmod 644 "${REAL_HOME}/.zshrc"

# 16.3 ~/.config/kitty/kitty.conf (if Kitty is installed or selected)
if [ "${INSTALL_DESKTOP_APPS}" -eq 1 ] || command -v kitty >/dev/null 2>&1; then
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
fi

# --- 17. Mise Runtime Environments Configuration ---
echo "--- 17. Configuring Mise Runtimes ---"
if command -v mise >/dev/null 2>&1; then
    run_user "mise settings set idiomatic_version_file false 2>/dev/null || true"
    run_user "mise settings set yes true 2>/dev/null || true"
    run_user "mise use --global dotnet@10 node@latest java@lts 2>/dev/null || true"
fi

# --- 18. SSH Key Generation ---
echo "--- 18. Configuring User SSH Keys ---"
USER_SSH_DIR="${REAL_HOME}/.ssh"
if [ ! -f "${USER_SSH_DIR}/id_ed25519" ]; then
    run_user "mkdir -p '${USER_SSH_DIR}' && chmod 700 '${USER_SSH_DIR}'"
    run_user "ssh-keygen -t ed25519 -f '${USER_SSH_DIR}/id_ed25519' -N ''"
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null 2>&1; then
        run_user "wl-copy < '${USER_SSH_DIR}/id_ed25519.pub' 2>/dev/null || true"
    elif [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then
        run_user "xclip -selection clipboard < '${USER_SSH_DIR}/id_ed25519.pub' 2>/dev/null || true"
    fi
fi

cd "${REAL_HOME}" || cd /tmp

echo "===================================================================="
echo " Debian Post-Installation & Developer Setup completed successfully!"
echo " Log saved to: ${LOG_FILE}"
echo ""
echo " Installed Components Summary:"
echo "   - Core CLI Tools & Compilers: Installed"
echo "   - Zsh, Zinit & Plugins:       Installed"
echo "   - Mise Runtimes (Dotnet/Node): Configured"
echo "   - Docker CE & Podman:         Installed"
[ "${INSTALL_DESKTOP_APPS}" -eq 1 ] && echo "   - Desktop GUI Apps:           Installed (Kitty, Foliate, qBittorrent, MPV)" || echo "   - Desktop GUI Apps:           Skipped"
[ "${INSTALL_VSCODE}" -eq 1 ]       && echo "   - Visual Studio Code:         Installed" || echo "   - Visual Studio Code:         Skipped"
[ "${INSTALL_ANTIGRAVITY}" -eq 1 ]   && echo "   - Google Antigravity IDE:     Installed" || echo "   - Google Antigravity IDE:     Skipped"
[ "${INSTALL_RIDER}" -eq 1 ]        && echo "   - JetBrains Rider:            Installed" || echo "   - JetBrains Rider:            Skipped"
[ "${INSTALL_STUDIO}" -eq 1 ]       && echo "   - Android Studio:             Installed" || echo "   - Android Studio:             Skipped"
echo "===================================================================="

prompt_reboot

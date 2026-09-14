# Prepare an Install script to run post fresh install of Arch Linux System.
# Script must be interactive (can use gum), verbose and handle exceptions with logging.
# Script must be robust for rerun without issues/duplications incase of unhandled termination or errors.
# Script must discern when to use sudo and login user for permissions
# Keep the script commands simple and easy to understand.
# Use commands and working statements and popular configurations as per latest versions.
# Operations Steps:
# 1. Set hostname
# 2. Configure pacman to increase speed and ilovecandy
# 3. System Update
# 4. Install base-devel, git, rust, cargo, clang and other base utilities.
# 5. Check and install paru if not available and configure it.
# 6. Check gpu and install latest proprietery AMD Graphics.
# 7. Confirm with user to install and configure asusctl & supergfxctl and set mode to integrated.
# 8. Install CLI tools openssh btop inxi fastfetch unzip unrar poppler wl-clipboard direnv cmake ninja
# 9. Install zoxide eza fzf bat yazi fd ripgrep jq starship atuin yt-dlp kitty micro mise
# 10. Install podman docker papirus-icon-theme. inter variable font, 0xProto Nerd Font, Microsoft fonts
# 11. Install mpv, peazip, libreoffice, jetbrains rider.
# 12. Install flatpak and flathub repo.
# 13. Install chrome, vs code native versions.
# 14. Install flatpaks qbitorrent, spotify, flatseal
# 15. Install zsh (set as default shell) and zinit plugin framework
# Configurations (yes or no basis user input):
# 1. Perform basic kitty configuration to use nerd font and size 12 and other modern settings.
# 2. Add micro as default editor in zshrc and init all the utilities in zshrc. Add modern and popular settings in zshrc for history etc.
# 3. Add separate aliases file and refer in zshrc. Include popular aliases for utilities, system operations, terminal ease of use and others.
# 4. Configure starship as a minimal modern prompt with support for common languages including dotnet.
# 5. Use mise or native to install latest java sdk, python, dotnet sdk 10 and nodejs.
# 6. Initialise required sdk environment variables in zshrc.
# 7. Enable ssh and generate public key for use in github.com
# 8. Initialise git with user and email (interactive)
# 9. If power-profile-daemon is installed, configure settings which are best for laptops.

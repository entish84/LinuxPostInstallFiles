# UPDATE AND UPGRADE
sudo pacman -Syu
yay -Syu

# INSTALL UTILITIES and SOFTWARE
sudo pacman -S micro direnv foliate git wget curl unzip tar clang cargo make gcc zoxide eza fd ripgrep bat yazi fzf starship just wl-clipboard fastfetch btop bash-completion flatpak qbittorrent toolbox distrobox libreoffice-fresh kitty inter-font ttf-firacode-nerd --noconfirm

# INSTALL ZSH
sudo pacman -S zsh
chsh -s $(which zsh)
# Reboot

# CODE
yay -S visual-studio-code-bin

# INSTALL ZINIT
bash -c "$(curl -fsSL https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"

# INSTALL NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
nvm --version

# INSTALL MISE
curl https://mise.run | sh

mise use --global dotnet@10
mise use --global java@lts
mise use --global node@latest

# AUTIN HISTORY
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh

# zinit light Aloxaf/fzf-tab

# GEMINI CLI
npm install -g @google/gemini-cli

# SSH
ssh-keygen -t ed25519 -C "entishthoughts@outlook.com"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub | wl-copy

ssh -T git@github.com
git config --global user.name "entish84"
git config --global user.email "entishthoughts@outlook.com"



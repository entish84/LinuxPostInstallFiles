sudo dnf copr enable lihaohong/yazi
sudo dnf copr enable jakjasie1/timeshift
sudo dnf copr enable alternateved/eza

sudo dnf install zoxide eza fzf bat yazi -y

git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

# Nerd font installer
# https://github.com/LionyxML/nerd-installer

# curl -fsSL https://raw.githubusercontent.com/getnf/getnf/main/install.sh | bash

sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
sudo dnf upgrade --refresh
sudo dnf install code
 
sudo dnf install kitty foliate

sudo dnf install timeshift

sudo dnf copr enable lukenukem/asus-linux
sudo dnf install asusctl supergfxctl
sudo systemctl enable --now supergfxd
supergfxctl -m Integrated



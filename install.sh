#!/bin/sh
# Update and Upgrade
sudo apt update && sudo apt upgrade

# Install codecs and microsoft fonts
sudo apt install ubuntu-restricted-extras

# Install essential softwares
sudo apt install git curl wget vlc unzip rar mc htop inxi flameshot transmission gdebi gthumb kitty

# Remove default softwares
sudo apt remove celluloid gnome-screenshot drawing hypnotix simple-scan pix mintchat rhythmbox

# Install Kate editor
flatpak install org.kde.kate -y

# Install fonts
sudo apt install fonts-inter fonts-jetbrains-mono fonts-cascadia-code

# Install jdk (17 because of MAUI otherwise latest)
sudo apt install openjdk-17-jdk -y

# Install zsh and oh-my-zsh
sudo apt install zsh -y
zsh --version
chsh -s $(which zsh)
echo $SHELL
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

#### 1. **Zsh Autosuggestions**
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
#### 2. **Zsh Syntax Highlighting**
git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
#### 3. **Zsh Autocomplete**
git clone --depth 1 https://github.com/marlonrichert/zsh-autocomplete ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete
#### 4. **Zsh History Substring Search (optional)**
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search

nano ~/.zshrc
plugins=(sudo themes aliases ubuntu git zsh-autosuggestions zsh-syntax-highlighting zsh-autocomplete z zsh-history-substring-search)
source ~/.zshrc

# Change Kitty Theme
kittens theme





#!/bin/sh
# Update and Upgrade
sudo apt update && sudo apt upgrade

# Install codecs and microsoft fonts
sudo apt install mint-meta-codecs

# Install ms fonts
sudo apt install ttf-mscorefonts-installer

# Install essential softwares
sudo apt install git gcc make curl wget unzip tar btop inxi clang cargo direnv micro kitty

# Remove default softwares
sudo apt remove celluloid gnome-screenshot drawing hypnotix simple-scan pix mintchat rhythmbox

# Install new softwares
sudo apt install vlc flameshot transmission gdebi gthumb xclip wl-clipboard

# Install fonts
sudo apt install fonts-inter-variable

# Nerd Fonts
curl -sSLo nerdfonts-installer https://github.com/fam007e/nerd_fonts_installer/releases/latest/download/nerdfonts-installer && chmod +x nerdfonts-installer && sudo mv nerdfonts-installer /usr/local/bin/
nerdfonts-installer

# install starship
curl -sS https://starship.rs/install.sh | sh

# INSTALL TUI
sudo apt install zoxide fzf eza yazi fd-find ripgrep bat tldr ffmpeg 7zip jq poppler-utils imagemagick

# MISE
curl https://mise.run/bash | sh
# Installs mise and adds activation to ~/.bashrc
mise use -g usage
mise use -g dotnet@10
mise use -g java@lts
mise use -g node@latest

# BLE.SH
# Quick INSTALL to BASHRC (If this doesn't work, please follow Sec 1.3)
git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git
make -C ble.sh install PREFIX=~/.local
#echo 'source -- ~/.local/share/blesh/ble.sh' >> ~/.bashrc
# Add this lines at the top of .bashrc:
[[ $- == *i* ]] && source -- /path/to/blesh/ble.sh --attach=none
# Add this line at the end of .bashrc:
[[ ! ${BLE_VERSION-} ]] || ble-attach


# GEMINI CLI
npm install -g @google/gemini-cli

# FZF
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
#EZA
sudo mkdir -p /etc/apt/keyrings
wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
sudo apt update
sudo apt install -y eza

# GIT CONFIGURATIONS
ls -al ~/.ssh
ssh-keygen -t ed25519 -C "entishthoughts@outlook.com"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
# Then, log in to GitHub, go to Settings > SSH and GPG keys, click New SSH key, provide a title, and paste the key
ssh -T git@github.com
git config --global user.name "Ranjit"
git config --global user.email "entishthoughts@outlook.com"


#DEBIAN ############
wget https://packages.microsoft.com/config/debian/13/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

sudo apt-get update && \
  sudo apt-get install -y dotnet-sdk-10.0

# OPTIONAL
sudo apt-get update && \
  sudo apt-get install -y aspnetcore-runtime-10.0

#UBUNTU ###############################
sudo apt install dotnet-sdk-10.0

# add to zshrc
eval "$(dotnet completions script zsh)"

# export DOTNET_ROOT="$HOME/.dotnet"
# export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools

## VSCODE #############
sudo apt-get install wget gpg &&
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg &&
sudo install -D -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg &&
rm -f microsoft.gpg

sudo micro /etc/apt/sources.list.d/vscode.sources
#PASTE BELOW
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg

#INSTALL CODE
sudo apt install apt-transport-https &&
sudo apt update &&
sudo apt install code




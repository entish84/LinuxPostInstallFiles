#!/bin/sh
# Update and Upgrade
sudo apt update && sudo apt upgrade

# Install codecs and microsoft fonts
sudo apt install mint-meta-codecs

# Install ms fonts
sudo apt install ttf-mscorefonts-installer

# Install essential softwares
sudo apt install git gcc make curl wget unzip unrar tar htop bpytop inxi neofetch clang cargo libc6-i386 libc6-x32 libu2f-udev samba-common-bin exfat-fuse linux-headers-$(uname -r) linux-headers-generic gstreamer1.0-vaapi ntfs-3g p7zip

# Remove default softwares
sudo apt remove celluloid gnome-screenshot drawing hypnotix simple-scan pix mintchat rhythmbox

# Install new softwares
sudo apt install vlc flameshot transmission gdebi gthumb xclip

# Install fonts
sudo apt install fonts-inter fonts-jetbrains-mono fonts-cascadia-code fonts-font-awesome

# goto https://www.nerdfonts.com/font-downloads
# install firacode-nerdfont
# install starship
curl -sS https://starship.rs/install.sh | sh

# Configure - add entry to end of ~/.bashrc
eval "$(starship init bash)"

# configure gruvbox preset
starship preset gruvbox-rainbow -o ~/.config/starship.toml
# Configure Powerline preset
starship preset catppuccin-powerline -o ~/.config/starship.toml

# Install jdk (17 because of MAUI otherwise latest)
sudo apt install openjdk-21-jdk -y

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

# Install Powerlevel10k terminal theme
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
ZSH_THEME = "powerlevel10k/powerlevel10k"

# Install Graphite Theme
cd Downloads
mkdir graphth
cd graphth
git clone https://github.com/vinceliuice/Graphite-gtk-theme.git
cd /home/rs/Downloads/graphth/Graphite-gtk-theme
./install.sh -t all -c dark -s compact --tweaks nord darker  # Other options rimless normal

# Install ulauncher
sudo add-apt-repository universe -y && sudo add-apt-repository ppa:agornostal/ulauncher -y && sudo apt update && sudo apt install ulauncher

# Install Android Studio
# Download tar file
tar -xvf <Filename>
sudo mv android-studio /opt/
cd /opt/android-studio/bin
./studio.sh

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

# Install dotnet via scripts
wget https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
chmod +x dotnet-install.sh
sudo ./dotnet-install.sh --channel 8.0 --install-dir ~/dotnet
echo 'export DOTNET_ROOT=~/dotnet' >> ~/.zshrc
echo 'export PATH=$PATH:~/dotnet:~/dotnet/tools' >> ~/.zshrc
source ~/.zshrc
dotnet --list-sdks
dotnet workload search
dotnet workload install maui-android
dotnet workload list
dotnet new maui -n MyMauiApp
cd MyMauiApp
dotnet build -t:Run -f net8.0-android

#goto android sdk cmdline-tools latest bin
#run
./sdkmanager "build-tools;34.0.0"
./sdkmanager "system-images;android-34;google_apis;x86_64"





#make all changes in ubuntu


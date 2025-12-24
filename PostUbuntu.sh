#!/bin/sh
# Update and Upgrade
sudo apt update && sudo apt upgrade

# install omakub
wget -qO- https://omakub.org/install | bash

# Install codecs and microsoft fonts
sudo apt install ubuntu-restricted-extras

# Install essential softwares
sudo apt install git curl wget vlc unzip rar transmission gdebi xclip cmake ninja-build libgtk-3-dev foliate

# Install fonts
sudo apt install fonts-inter fonts-jetbrains-mono fonts-cascadia-code fonts-font-awesome

# Install poweline fonts
git clone https://github.com/powerline/fonts.git --depth=1
cd fonts
./install.sh
cd ..
rm -rf fonts

# Install zsh and oh-my-zsh
sudo apt install zsh -y
zsh --version
chsh -s $(which zsh)
echo $SHELL
# Logout and login
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

#### 1. **Zsh Autosuggestions**
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
#### 2. **Zsh Syntax Highlighting**
git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
#### 3. **Zsh Autocomplete**
git clone --depth 1 https://github.com/marlonrichert/zsh-autocomplete ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete
#### 4. **Zsh History Substring Search (optional)**
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search

# Install powerling theme
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

# Add the plugins and default
nano ~/.zshrc
# At the beginning
DISABLE_AUTO_UPDATE="true"
DISABLE_MAGIC_FUNCTIONS="true"
DISABLE_COMPFIX="true"
# If you come from bash you might have to change your $PATH. UNCOMMENT
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH
# Set the theme
ZSH_THEME="powerlevel10k/powerlevel10k"
HYPHEN_INSENSITIVE="true" # UNCOMMENT
# Set the plugins
plugins=(sudo themes aliases ubuntu git vscode zsh-autosuggestions zsh-syntax-highlighting zsh-autocomplete z zsh-history-substring-search)
# Autosuggest settings
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE="20"
ZSH_AUTOSUGGEST_USE_ASYNC=1
# Example aliases
alias zshconfig="gedit ~/.zshrc"
alias ohmyzsh="gedit ~/.oh-my-zsh"

# PATH VARIABLES
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_AVD_HOME="~/.android/avd"
export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_AVD_HOME
typeset -U PATH

# Update config
source ~/.zshrc

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

# Install Android Studio
# Download tar file
tar -xvf <Filename>
sudo mv android-studio /opt/
cd /opt/android-studio/bin
./studio.sh
# After installation - Create Desktop entry from settings, using SDKManager install cmdlinetools, install flutter plugin.

# open VSCODE and Signin -> install flutter extension. New flutter project -> Choose to install flutterSDK in dev location.
# run flutter doctor.
# Accept Licenses.

#goto android sdk cmdline-tools latest bin
cd ~/Android/Sdk/cmdline-tools/latest/bin/
#run
./sdkmanager "build-tools;34.0.0"
./sdkmanager "system-images;android-34;google_apis;x86_64"

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







#make all changes in ubuntu

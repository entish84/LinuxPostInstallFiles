sudo dnf install gcc make cmake clang cargo meld p7zip tar ninja-build

sudo dnf copr enable lihaohong/yazi
sudo dnf copr enable jakjasie1/timeshift
sudo dnf copr enable alternateved/eza
sudo dnf copr enable atim/bottom -y

sudo dnf install zoxide eza fzf bat yazi -y

git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

# Nerd font installer
# https://github.com/LionyxML/nerd-installer

sudo dnf copr enable julicen/atkinson-hyperlegible-fonts -y
# 2. Enable the reliable repo for Inter and JetBrains
sudo dnf copr enable elxreno/jetbrains-mono-fonts -y
# 3. Install with the exact current package names
sudo dnf install -y \
    atkinson-hyperlegible-next-fonts \
    atkinson-hyperlegible-mono-fonts \
    rsms-inter-vf-fonts \
    google-roboto-fonts \
    jetbrains-mono-fonts-all
# 4. Refresh font cache
fc-cache -fv

sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
sudo dnf upgrade --refresh
sudo dnf install code
 
sudo dnf install kitty foliate micro haruna
sudo dnf install timeshift
sudo dnf install bottom -y

mkdir -p ~/.config/mpv/
nano ~/.config/mpv/mpv.conf
#Add this line: hwdec=auto-safe



sudo dnf copr enable lukenukem/asus-linux
sudo dnf install asusctl supergfxctl
sudo systemctl enable --now supergfxd
supergfxctl -m Integrated



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






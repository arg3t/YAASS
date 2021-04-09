#!/bin/bash

export NC='\033[0m'
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export ORANGE='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export LIGHTGRAY='\033[0;37m'
export DARKGRAY='\033[1;30m'
export LIGHTRED='\033[1;31m'
export LIGHTGREEN='\033[1;32m'
export YELLOW='\033[1;33m'
export LIGHTBLUE='\033[1;34m'
export LIGHTPURPLE='\033[1;35m'
export LIGHTCYAN='\033[1;36m'
export WHITE='\033[1;37m'

verbose=0

info(){
  printf "[\e[32mINFO\e[0m]:%s\n" "$1"
}

debug(){
  if [ $verbose ]; then
    printf "[\e[33mDEBUG\e[0m]:%s\n" "$1"
  fi
}

error(){
  printf "[\e[31mERROR\e[0m]:%s\n" "$1"
}

prompt(){
  printf "[\e[35mPROMPT\e[0m]: %s" "$1"
  read -r ans
  printf "%s" "$ans"
}

install_deps(){
	info "Installing dependencies"
	sudo pacman -Sy --needed --noconfirm git tmux 2> /dev/null > /dev/null
}

banner(){
		echo "${CYAN}
dP    dP  .d888888   .d888888  .d88888b  .d88888b
Y8.  .8P d8'    88  d8'    88  88.    \"' 88.    \"'
 Y8aa8P  88aaaaa88a 88aaaaa88a \`Y88888b. \`Y88888b.
	 88    88     88  88     88        \`8b       \`8b
	 88    88     88  88     88  d8'   .8P d8'   .8P
	 dP    88     88  88     88   Y88888P   Y88888P
		${NC}"
		echo "      ${PURPLE}Yeet's Automated Arch Setup Script${NC}"
}


clear

boot=$1
root=$2
swap=$3

if [ ! "$(wc -l /install/device)" = "3" ]; then
    home=$4
fi

ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime
hwclock --systohc
echo -e "en_US.UTF-8 UTF-8\ntr_TR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
if [ ! -f "/tmp/.blackarch" ]; then
    curl https://blackarch.org/strap.sh > /tmp/strap.sh
    chmod +x /tmp/strap.sh
    /tmp/strap.sh

    if [ -f "/install/artix" ]; then
        echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist-arch" >> /etc/pacman.conf
        echo -e "\n[lib32]\nInclude = /etc/pacman.d/mirrorlist\n\n[options]\nILoveCandy\nTotalDownload\nColor" >> /etc/pacman.conf
    else
        echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n\n[options]\nILoveCandy\nTotalDownload\nColor" >> /etc/pacman.conf
    fi


    echo -n "Are you going to use a flexo server?(y/N): "
    read flexo

    if [ "$flexo" = "y" ]; then
        echo -n "Please enter ip address of flexo server: "
        read flexo_ip
        echo -e "\nServer = http://$flexo_ip:7878/\$repo/os/\$arch\n" >> /etc/pacman.d/mirrorlist
    fi
    pacman -Syy

    echo -n "Did any errors occur?(y/N): "
    read errors

    if [ "$errors" = "y" ]; then
        echo "Dropping you into a shell so that you can fix them, once you quit the shell, the installation will continue from where you left off."
        bash
    fi
    touch /tmp/.blackarch
fi

clear

echo "Please enter hostname: "
read hostname
echo $hostname > /etc/hostname

echo "Set password for root: "
passwd root

echo "Please enter name for regular user:"
read username

useradd -m $username
echo "Set password for user $username: "
passwd $username
usermod -aG wheel $username


echo -e "127.0.0.1 localhost\n::1 localhost\n127.0.0.1 $hostname.localdomain $hostname" > /etc/hosts

if [ -f "/install/encrypted" ]; then
cat << EOF > /etc/initcpio/hooks/openswap
run_hook ()
{
    x=0;
    while [ ! -b /dev/mapper/root ] && [ \$x -le 10 ]; do
       x=$((x+1))
       sleep .2
    done
    mkdir crypto_key_device
    mount /dev/mapper/root crypto_key_device
    cryptsetup open --key-file crypto_key_device/root/.keys/swap-keyfile $swap swap
    umount crypto_key_device
}
EOF

cat << EOF > /etc/initcpio/install/openswap
build ()
{
   add_runscript
}
help ()
{
cat<<HELPEOF
  This opens the swap encrypted partition $swap in /dev/mapper/swap
HELPEOF
}
EOF

if [ ! "$home" = "" ]; then
cat << EOF > /etc/initcpio/hooks/openhome
run_hook ()
{
    x=0;
    while [ ! -b /dev/mapper/root ] && [ \$x -le 10 ]; do
       x=$((x+1))
       sleep .2
    done
    mkdir crypto_key_device
    mount /dev/mapper/root crypto_key_device
    cryptsetup open --key-file crypto_key_device/root/.keys/home-keyfile $home home
    umount crypto_key_device
}
EOF
cat << EOF > /etc/initcpio/install/openhome
build ()
{
   add_runscript
}
help ()
{
cat<<HELPEOF
  This opens the swap encrypted partition $home in /dev/mapper/home
HELPEOF
}
EOF
cat << EOF > /etc/mkinitcpio.conf
MODULES=(vfat i915)
BINARIES=()
FILES=()
HOOKS=(base udev plymouth autodetect keyboard keymap consolefont modconf block plymouth-encrypt openswap openhome resume filesystems fsck)
EOF
else
cat << EOF > /etc/mkinitcpio.conf
MODULES=(vfat i915)
BINARIES=()
FILES=()
HOOKS=(base udev plymouth autodetect keyboard keymap consolefont modconf block plymouth-encrypt openswap resume filesystems fsck)
EOF
fi
else
cat << EOF > /etc/mkinitcpio.conf
MODULES=(vfat i915)
BINARIES=()
FILES=()
HOOKS=(base udev plymouth autodetect keyboard keymap consolefont modconf block plymouth resume filesystems fsck)
EOF
fi

pacman -Syu --noconfirm $(cat /install/packages.base | xargs)

refind-install

if [ -f "/install/encrypted" ]; then
line=1

blkid | while IFS= read -r i; do
    echo "$line: $i"
    ((line=line+1))
done

echo -n "Please select the device you will save the LUKS key to: "
read keydev

uuid=$(blkid | sed -n 's/.*UUID=\"\([^\"]*\)\".*/\1/p'  | sed -n "$keydev"p)
cat << EOF > /boot/refind_linux.conf
"Boot with encryption"  "root=/dev/mapper/root resume=/dev/mapper/swap cryptdevice=UUID=$(blkid -s UUID -o value $root):root:allow-discards cryptkey=UUID=$uuid:vfat:key.yeet rw loglevel=3 quiet splash"
EOF
clear
else
cat << EOF > /boot/refind_linux.conf
"Boot without encryption"  "root=UUID=$(blkid -s UUID -o value $root) resume=UUID=$(blkid -s UUID -o value $swap) rw loglevel=3 quiet splash"
EOF
fi

mkdir -p /etc/sudoers.d
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/nopwd


sudo -u $username bash -c "git clone https://aur.archlinux.org/yay.git /tmp/yay"
sudo -u $username bash -c "(cd /tmp/yay; makepkg --noconfirm -si)"
sudo -u $username bash -c "yay --noconfirm -S plymouth"

if [ -f "/install/artix" ]; then
    sudo -u $username bash -c "yay --noconfirm -S plymouth-openrc-plugin"
fi
clear

echo -n "Would you like to automatically install my dotfiles?(y/N): "
read dotfiles

if [ "$dotfiles" = "y" ]; then
    pacman -R --noconfirm vim
    sudo -u $username bash -c "git clone --recurse-submodules https://github.com/theFr1nge/dotfiles.git ~/.dotfiles"
    sudo -u $username bash -c "(cd ~/.dotfiles; ./install.sh)"
    clear
fi
git clone https://github.com/adi1090x/plymouth-themes.git /tmp/pthemes
cat << EOF > /etc/plymouth/plymouthd.conf
[Daemon]
Theme=sphere
ShowDelay=0
DeviceTimeout=8
EOF
cp -r /tmp/pthemes/pack_4/sphere /usr/share/plymouth/themes
clear

echo -e "/boot/EFI/refind\n2\n2" | sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/bobafetthotmail/refind-theme-regular/master/install.sh)"

if [ -f "/install/artix" ]; then
    sudo rc-update add cronie
    sudo rc-update add acpi
    sudo rc-update add dbus
    sudo rc-update add connmand
    sudo rc-update add syslog-ng
else
    systemctl enable connman
    systemctl enable cronie
fi

clear

mkinitcpio -P

if [ -f "/install/encrypted" ]; then
    vim /etc/fstab
fi
pacman --noconfirm -R nano # uninstall nano, eww

clear

rm -rf /etc/sudoers.d/nopwd
echo "Defaults env_reset,pwfeedback" > /etc/sudoers.d/wheel
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers.d/wheel
echo "$username $hostname =NOPASSWD: /sbin/shutdown ,/sbin/halt,/sbin/reboot,/sbin/hibernate, /bin/pacman -Syyuw --noconfirm" >> /etc/sudoers.d/wheel

ln -sf /bin/dash /bin/sh

clear

echo "SETUP COMPLETE"
bash
rm -rf /install

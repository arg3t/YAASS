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

encryption=$1
root=$3
swap=$4
home=$5

zone=$(prompt "Please enter timezone: ")
while [ ! -f "/usr/share/zoneinfo/$zone" ]; do
    zone=$(prompt "Please enter timezone: ")
done
ln -sf "/usr/share/zoneinfo/$zone" /etc/localtime
hwclock --systohc

echo -e "en_US.UTF-8 UTF-8\ntr_TR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf

if [ ! -f "/tmp/.blackarch" ]; then
    curl https://blackarch.org/strap.sh > /tmp/strap.sh
    chmod +x /tmp/strap.sh
    /tmp/strap.sh

    printf "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist-arch" >> /etc/pacman.conf
    printf "\n[lib32]\nInclude = /etc/pacman.d/mirrorlist\n\n[options]\nILoveCandy\nTotalDownload\nColor" >> /etc/pacman.conf

    flexo=$(prompt "Are you going to use a flexo server?(y/N): ")

    if [ "$flexo" = "y" ]; then
        flexo_ip=$(prompt "Please enter ip address of flexo server: ")
        echo -e "\nServer = http://$flexo_ip:7878/\$repo/os/\$arch\n" >> /etc/pacman.d/mirrorlist
    fi
    pacman -Syy

    errors=$(prompt "Did any errors occur?(y/N): ")

    if [ "$errors" = "y" ]; then
        echo "Dropping you into a shell so that you can fix them, once you quit the shell, the installation will continue from where you left off."
        bash
    fi
    touch /tmp/.blackarch
fi

clear

hostname=$(prompt "Please enter hostname: ")
echo "$hostname" > /etc/hostname

info "Set password for root: "
passwd root

username=$(prompt "Please enter name for regular user: ")

useradd -m "$username"
info "Set password for user $username: "
passwd "$username"
usermod -aG wheel "$username"


echo -e "127.0.0.1 localhost\n::1 localhost\n127.0.0.1 $hostname.localdomain $hostname" > /etc/hosts

if [ "$encryption" = "1" ]; then
  cat << EOF > /etc/initcpio/hooks/openswap
run_hook ()
{
    x=0;
    while [ ! -b /dev/mapper/root ] && [ \$x -le 10 ]; do
       x=\$(( x+1 ))
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
       x=\$((x+1))
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

pacman -Syu --noconfirm "$(xargs < /install/pkg.list)"
refind-install
clear
if [ "$encryption" = "1" ]; then
  line=1

  blkid | while IFS= read -r i; do
      echo "$line: $i"
      ((line=line+1))
  done

  keydev=$(prompt "Please select the device you will save the LUKS key to: ")
  # TODO automatically copy key files and format device
  uuid=$(blkid | sed -n 's/.*UUID=\"\([^\"]*\)\".*/\1/p'  | sed -n "$keydev"p)
  cat << EOF > /boot/refind_linux.conf
"Boot with encryption"  "root=/dev/mapper/root resume=/dev/mapper/swap cryptdevice=UUID=$(blkid -s UUID -o value "$root"):root:allow-discards cryptkey=UUID=$uuid:vfat:key.yeet rw loglevel=3 quiet splash"
EOF
  clear
else
  cat << EOF > /boot/refind_linux.conf
"Boot without encryption"  "root=UUID=$(blkid -s UUID -o value "$root") resume=UUID=$(blkid -s UUID -o value "$swap") rw loglevel=3 quiet splash"
EOF
fi

mkdir -p /etc/sudoers.d
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/nopwd

info "Installing yay"
sudo -u "$username" bash -c "git clone https://aur.archlinux.org/yay.git /tmp/yay"
sudo -u "$username" bash -c "(cd /tmp/yay; makepkg --noconfirm -si)"
sudo -u "$username" bash -c "yay --noconfirm -S plymouth"

sudo -u "$username" bash -c "yay --noconfirm -S plymouth-openrc-plugin"
clear

dotfiles=$(prompt "Would you like to automatically install my dotfiles?(y/N): ")

if [ "$dotfiles" = "y" ]; then
    pacman -R --noconfirm vim
    sudo -u "$username" bash -c "git clone --recurse-submodules https://github.com/theFr1nge/dotfiles.git ~/.dotfiles"
    sudo -u "$username" bash -c "(cd ~/.dotfiles; ./install.sh)"
    clear
fi

info "Installing Plymouth theme"
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

sudo rc-update add cronie
sudo rc-update add acpi
sudo rc-update add dbus
sudo rc-update add connmand
sudo rc-update add syslog-ng

clear

info "Running mkinitcpio"
mkinitcpio -P

if [ "$encryption" = "$1" ]; then
    vim /etc/fstab
fi

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

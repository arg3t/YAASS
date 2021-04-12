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
  1>&2 printf "[\e[35mPROMPT\e[0m]: %s" "$1"
  read -r ans
  printf "%s" "$ans"
	printf "\n"
}

install_deps(){
	info "Installing dependencies"
	sudo pacman -Sy --needed --noconfirm git tmux 2> /dev/null > /dev/null
}

banner(){
	printf "${CYAN}"
	printf "dP    dP  .d888888   .d888888  .d88888b  .d88888b\n"
	printf "Y8.  .8P d8'    88  d8'    88  88.       88.    \n"
	printf " Y8aa8P  88aaaaa88 88aaaaa88a \`Y88888b. \`Y88888b.\n"
	printf "   88    88     88  88     88        \`8b       \`8b\n"
	printf "   88    88     88  88     88  d8'   .8P d8'   .8P\n"
	printf "   dP    88     88  88     88   Y88888P   Y88888P\n"
	printf "${NC}"
	printf "      ${PURPLE}Yeet's Automated Arch Setup Script${NC}"
}


help(){
		1>&2 printf"
${GREEN} Usage:${NC}\n
	-o Select the OS you are installing this on
	-v Run in verbose mode
${ORANGE}Author:${NC} Yigit Colakoglu aka. ${BLUE}<===8 Fr1nge 8===>${NC}\n"
		exit 0
}

os=""

banner

while [[ $# -gt 0 ]]
do
	key="$1"
	case $key in
		-o|--os)
			os="$(echo "$2" |  tr '[:upper:]' '[:lower:]')"
			shift 2
			;;
		-v|--verbose)
			verbose=1
			shift
			;;
		*)
			help
			;;
	esac
done

if [ "$os" = "" ]; then
	os=$(prompt "Please enter the OS you want to install on(Arch/Artix): " |  tr '[:upper:]' '[:lower:]')
fi

if [ ! "$os" = "arch" ] && [ ! "$os" = "artix" ]; then
	error "OS must be Arch or Artix"
	exit 1
fi

# Disk setup
lsblk

device=$(prompt "What is the install device: ")
info "Installing to $device... (Enter to continue)"
read -r _

clear

wipe=$(prompt "Would you like to wipe and re-partition the disk $device?(Y/n): ")

if [ ! "$wipe" = "n" ]; then
    # Disk wipe
		secure=$(prompt "Should I do a secure wipe?(y/N): ")
    if [ "$secure" = "y" ]; then
        info "Writing random data to disk, this might take a while if you have a large drive..."
        cryptsetup open -q --type plain -d /dev/urandom "$device" wipe
        dd if=/dev/zero of=/dev/mapper/wipe status=progress
        cryptsetup -q close wipe
    fi
    info "Wiping the partition table..."
    cryptsetup erase "$device"
    wipefs -a -f "$device"
    sleep 1
fi

clear
# Run cfdisk for manual partitioning
cfdisk "$device"
clear
sleep 2
[ ! "$(command -v partprobe)" = "" ] && partprobe
lsblk "$device"
satisfied=$(prompt "Are you satisfied with your partitions?(Y/n): ")

while [ "$satisfied" = "n" ]; do
    cfdisk "$device"
    clear
    [ ! "$(command -v partprobe)" = "" ] && partprobe
    lsblk "$device"
		satisfied=$(prompt "Are you satisfied with your partitions?(Y/n): ")
done
clear

lsblk "$device"
echo ""
echo "Now you will specify the partitions you have created"
echo "Please enter the suffix for each partition. For Ex:"
echo "1 if boot partition is /dev/sda1 or p1 if boot is on /dev/nvme0n1p1 and the disk is /dev/nvme0n1"
boot_p=$(prompt "Please enter boot partition suffix: ")
root_p=$(prompt "Please enter root partition suffix: ")
swap_p=$(prompt "Please enter swap partition suffix: ")
boot=$device$boot_p
root=$device$root_p
swap=$device$swap_p
if [ -z "$home_s" ]; then
	home_s=$(prompt "Did you create a home partition as well?(y/N): ")
fi
if [ "$home_s" = "y" ]; then
		home_p=$(prompt "Please enter home partition suffix: ")
    home=$device$home_p
fi

clear

# Create the boot partition
info "Formatting boot partition"
mkfs.fat -F32 "$boot"

encryption=$(prompt "Would you like to enrypt your disks?(y/N): ")

if [ "$encryption" = "y" ]; then
    clear
    info "Running benchmark"
    cryptsetup benchmark
		cipher=$(prompt "Please select the ciphering algorithm(aes-xts-plain64): ")
    if [ "$cipher" = "" ]; then
        cipher="aes-xts-plain64"
    fi
		iter=$("Please select the iter time(750): ")

    if [ "$iter" = "" ]; then
        iter="750"
    fi
		keysize=$("Please select the key size(512): ")
    if [ "$keysize" = "" ]; then
        keysize="512"
    fi
    # Create the swap partition
    mkdir /root/.keys
    dd if=/dev/urandom of=/root/.keys/swap-keyfile bs=1024 count=4
    chmod 600 /root/.keys/swap-keyfile
    cryptsetup --key-size "$keysize" --cipher "$cipher" --iter-time "$iter" -q luksFormat "$swap" < /root/.keys/swap-keyfile
    info "Keyfile saved to /root/.keys/swap-keyfile"
    cryptsetup open --key-file="/root/.keys/swap-keyfile" "$swap" swap
    mkswap /dev/mapper/swap
    swapon /dev/mapper/swap

    # Create the root partition
		root_pass="$(prompt "Enter password for root encryption")"

    echo "$root_pass" | cryptsetup --key-size "$keysize" --cipher "$cipher" --iter-time "$iter" -q luksFormat "$root"
    dd bs=512 count=4 if=/dev/random of=/root/.keys/root-keyfile iflag=fullblock
    chmod 600 /root/.keys/root-keyfile
    echo "$root_pass" | cryptsetup luksAddKey "$root" /root/.keys/root-keyfile
    echo "[INFO]: Keyfile saved to /root/.keys/root-keyfile"
    cryptsetup open --key-file="/root/.keys/root-keyfile" "$root" root
    mkfs.ext4 -F /dev/mapper/root

    mkdir /mnt/sys
    mount /dev/mapper/root /mnt/sys

    if [ "$home_s" = "y" ]; then
				home_pass="$(prompt "Enter password for home encryption")"
        echo "$home_pass" | cryptsetup --key-size "$keysize" --cipher "$cipher" --iter-time "$iter" -q luksFormat "$home"
        dd bs=512 count=4 if=/dev/random of=/root/.keys/home-keyfile iflag=fullblock
        chmod 600 /root/.keys/home-keyfile
        echo "$home_pass" | cryptsetup luksAddKey "$home" /root/.keys/home-keyfile
        echo "[INFO]: Keyfile saved to /root/.keys/home-keyfile"
        cryptsetup open --key-file="/root/.keys/home-keyfile" "$home" home
        mkfs.ext4 -F /dev/mapper/home
        mkdir /mnt/sys/home
        mount "/dev/mapper/home" /mnt/sys/home
    fi
else
    mkswap "$swap"
    swapon "$swap"
    mkfs.ext4 -F "$root"
    mkdir /mnt/sys
    mount "$root" /mnt/sys
    if [ "$home_s" = "y" ]; then
        mkfs.ext4 -F "$home"
        mkdir /mnt/sys/home
        mount "$home" /mnt/sys/home
    fi
fi

mkdir /mnt/sys/boot
mount "$boot" /mnt/sys/boot

clear

mkdir /mnt/sys/install
case $os in
	arch)
    pacstrap /mnt/sys base linux linux-firmware base-devel vi nano
    genfstab -U /mnt/sys >> /mnt/sys/etc/fstab
    curl https://raw.githubusercontent.com/theFr1nge/YAASS/main/arch/pkg.list > /mnt/sys/install/packages.base
		curl https://raw.githubusercontent.com/theFr1nge/YAASS/main/arch/stage2.sh > /mnt/sys/install/stage2.sh
		;;
	artix)
    basestrap /mnt/sys base linux linux-firmware base-devel vi nano openrc
    fstabgen -U /mnt/sys >> /mnt/sys/etc/fstab
    curl https://raw.githubusercontent.com/theFr1nge/YAASS/main/artix/pkg.list > /mnt/sys/install/packages.base
		curl https://raw.githubusercontent.com/theFr1nge/YAASS/main/artix/stage2.sh > /mnt/sys/install/stage2.sh
		;;
esac

chmod +x /mnt/sys/install/stage2.sh

tmpfs_ok=$(prompt "Would you like to use tmpfs (This can drastically improve performance)?(Y/n): ")

if [ ! "$tmpfs_ok" = "n" ]; then
		tmpfs_size=$("How big should the tmpfs be?(end with G or M): ")
    printf "\n#tmpfs\ntmpfs   /tmp         tmpfs   rw,nodev,nosuid,size=%s          0  0\n" "$tmpfs_size" >> /mnt/sys/etc/fstab
fi

clear


encryption_param="1"
if [ ! "$encryption" = "n" ]; then
  cp -r /root/.keys /mnt/sys/root
	encryption_param="0"
fi



if [ "$os" = "arch" ];then
    tmux new-session -s "arch-setup" "arch-chroot /mnt/sys /install/stage2.sh \"$encryption_param\" \"$boot\" \"$root\" \"$swap\" \"$home\"" || arch-chroot /mnt/sys /install/stage2.sh "$encryption_param" "$boot" "$root" "$swap" "$home"
else
    tmux new-session -s "artix-setup" "artix-chroot /mnt/sys /install/stage2.sh \"$encryption_param\" \"$boot\" \"$root\" \"$swap\" \"$home\"" || artix-chroot /mnt/sys /install/stage2.sh "$encryption_param" "$boot" "$root" "$swap" "$home"
fi


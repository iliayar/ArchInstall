ARCH_ROOT=/mnt/arch-root
MANUAL=0

chrun() {
    arch-chroot $ARCH_ROOT /bin/bash -c "$1"
}

internet() {

    while ! ping -c 1 ya.ru; do
        echo "   1. Retry"
        echo "   2. Use Wi-Fi"
        while true; do
            echo "Choose: "
            read test
            echo $test | grep -G -q "^[12]$" && break
        done
        if [[ $test -eq 2 ]]; then
            wifi-menu
        fi
    done

}


partition() {

    local dev_info=$(parted -s /dev/sda print)

    while read -r PART; do
        parted -s /dev/sda rm $PART >/dev/null 2>&1
    done <<< "$(awk '/^ [1-9][0-9]?/ {print $1}' <<< "$dev_info" | sort -r)"

    parted -s /dev/sda mklabel gpt
    parted -s /dev/sda mkpart ESP 1MiB 512MiB
    parted -s /dev/sda mkpart primary  513MiB 100%

}

fmt_enc_partition() {

    cryptsetup luksFormat /dev/sda2
    cryptsetup open /dev/sda2 cryptroot

    mkfs.btrfs -L archroot /dev/mapper/cryptroot
    mkfs.vfat -F32 /dev/sda1

}

mount_partition() {

    mkdir /mnt/{subvolumes,arch-root}
    mount /dev/mapper/cryptroot /mnt/subvolumes
    btrfs subvolume create /mnt/subvolumes/home
    btrfs subvolume create /mnt/subvolumes/root

    mount -o subvol=root /dev/mapper/cryptroot $ARCH_ROOT
    mkdir $ARCH_ROOT/{home,boot}
    mount -o subvol=home /dev/mapper/cryptroot $ARCH_ROOT/home
    mount /dev/sda1 $ARCH_ROOT/boot
    
}

install_pkgs() {

    pacstrap $ARCH_ROOT base base-devel intel-ucode refind-efi dialog btrfs-progs sudo networkmanager git wget yajl xorg-server xorg-apps sddm i3 termite vim zsh reflector

}

make_swap() {
    arch-chroot $ARCH_ROOT /bin/bash <<EOF
    truncate -s 0 /swapfile
    chattr +C /swapfile
    btrfs property set /swapfile compression none
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    echo "/swapfile none swap defaults 0 0" >> /etc/fstab
EOF

}

localization() {

    sed -i "s/#en_US.UTF-8/en_US.UTF-8/g" $ARCH_ROOT/etc/locale.gen
    sed -i "s/#ru_RU.UTF-8/ru_RU.UTF-8/g" $ARCH_ROOT/etc/locale.gen
    chrun locale-gen
    chrun 'echo "LANG=en_US.UTF-8" > /etc/locale.conf'

}

install_refind() {

    chrun refind-install
    arch-chroot $ARCH_ROOT /bin/bash <<EOF
    cd /boot/EFI
    mkdir boot
    cp refind/refind_x64.efi boot/bootx64.efi
EOF
    uuid=$(ls -l /dev/disk/by-uuid/ | grep sda2 | awk '{print $9}')
    cat > $ARCH_ROOT/boot/EFI/refind/refind.conf <<EOF
timeout 10

menuentry "Arch Linux" {
    icon     /EFI/refind/icons/os_arch.png
    volume   "ESP"
    loader   /vmlinuz-linux
    initrd   /intel-ucode.img
    initrd   /initramfs-linux.img
    options  "cryptdevice=UUID=$uuid:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=root rw add_efi_memmap"
    submenuentry "Boot to terminal" {
        add_options "systemd.unit=multi-user.target"
    }
    enabled
}
EOF
echo "cryptroot UUID=$uuid none" >> $ARCH_ROOT/etc/crypttab
}

add_user() {

    chrun 'useradd -m -G video,audio,input,wheel,users -s /bin/bash iliayar'
    chrun 'passwd iliayar'
    sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g" $ARCH_ROOT/etc/sudoers

}

extras() {
    chrun 'echo "mkdir /home/iliayar/Documents; cd /home/iliayar/Documents; git clone https://github.com/iliayar/dotfiles; cd dotfiles; ./install.sh" >> /home/iliayar/.bashrc'
    chrun 'reflector --latest 100 --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist'
    chrun 'systemctl enable sddm'
    chrun 'systemctl enable NetworkManager'
}

main() {

echo "Automatic Partitioning: "
echo "    1. No"
echo "    2. Yes"
echo "Choose: "
read MANUAL

if [[ MANUAL -eq 1 ]]; then
	echo "Enter Arch root path: "
	read ARCH_ROOT
fi

echo "1. Connect to the Internet"
internet
clear

echo "2. Update System clock"
timedatectl set-ntp true
clear

echo "3. Partition the disks"
[[ MANUAL -eq 2 ]] && partition || /bin/bash
clear

echo "4. Format And Encrypt partitions"
[[ MANUAL -eq 2 ]] && fmt_enc_partition || /bin/bash
clear

echo "5. Mount partitions to /mnt"
[[ MANUAL -eq 2 ]] && mount_partition || /bin/bash
clear

echo "6. Installing base packages"
install_pkgs
clear

echo "7. Fstab"
genfstab -U $ARCH_ROOT >> $ARCH_ROOT/etc/fstab
clear

echo "8. Swapfile"
make_swap
clear

echo "9. Time zone"
chrun 'ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime'
chrun 'hwclock --systohc'
clear

echo "10. Localization"
localization
clear

echo "11. Network"
chrun 'echo "ArchLaptop" > /etc/hostname'
chrun 'echo "127.0.0.1 localhost" >> /etc/hosts'
clear

echo "12. Initramfs"
[[ MANUAL -eq 2 ]] && sed -i 's/block filesystems/block encrypt filesystems/g' $ARCH_ROOT/etc/mkinitcpio.conf || /bin/bash
chrun 'mkinitcpio -p linux'
clear

echo "13. Root password"
chrun passwd
clear

echo "14. Bootloader"
[[ MANUAL -eq 2 ]] && install_refind || /bin/bash
clear

echo "15. Add user"
add_user
clear

echo "16. Extras installing"
extras
clear

}

main


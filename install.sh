chrun() {
    arch-chroot /mnt/arch-root /bin/bash -c "$1"
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

    parted -s /dev/sda mktabel gpt
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

    mount -o subvol=root /dev/mapper/cryptroot /mnt/arch-root
    mkdir /mnt/arch-chroot/{home,boot}
    mount -o subvol=home /dev/mapper/cryptroot /mnt/arch-root/home
    mount /dev/sda1 /mnt/arch-root/boot
    
}

install_pkgs() {

    pacstrap /mnt base base-devel intel-ucode refind-efi dialog btrfs-progs sudo networkmanager git wget yajl xorg-server xorg-apps sddm plasma i3 termite vim zsh

}

make_swap() {
    arch-chroot /mnt/arch-root -c /bin/bash <<EOF
    fallocate -l 4096M /swapfile
     chmod 600 /swapfile
    mkswap /swapfile
    chrun echo "/swapfile none swap defaults 0 0" >> /etc/fstab
EOF

}

localization() {

    sed -i "s/#en_US.UTF-8/en_US.UTF-8/g" /mnt/arch-root/etc/locale.gen
    chrun locale-gen
    chrun 'echo "LANG=en_US.UTF-8" > /etc/locale.conf'

}

install_refind() {

    chrun refind-install
    arch-chroot /mnt/arch-root /bin/bash <<EOF
    cd /boot/EFI
    mkdir boot
    cp refind/refind_x64.efi boot/bootx64.efi
EOF
    uuid=$(ls -l /dev/disk/by-uuid/ | grep sda2 | awk '{print $9}')
    cat > /mnt/arch-root/boot/EFI/refind/refind.conf <<EOF
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
echo "cryptroot UUID=$uuid none" >> /mnt/arch-root/etc/crypttab
}

add_user() {

    chrun 'useradd -m -H video,audio,input,whell,users -s /bin/zsh iliayar'
    chrun 'passwd iliayar'
    sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g" /mnt/arch-root/etc/sudoers

}

extras() {
    HOME=/home/iliayar
    arch-chroot /mnt/arch-root /bin/bash <<EOF
    su iliayar
    mkdir $HOME/builds
    cd $HOME/builds; git clone https://aur.archlinux.org/package-query.git
    cd $HOME/builds/package-query/; makepkg -si
    cd $HOME/builds; git clone https://aur.archlinux.org/yaourt.git
    cd $HOME/builds/yaourt/; makepkg -si
    rm -Rf $HOME/builds
EOF
    HOME=/root
    chrun 'systemctl enable sddm'
    chrun 'enable NetworkManager'
}

main() {

echo "1. Connect to the Internet"
internet
clear

echo "2. Update System clock"
timedatectl set-ntp true
clear

echo "3. Partition the disks"
partition
clear

echo "4. Format And Encrypt partitions"
fmt_enc_partition
clear

echo "5. Mount partitions to /mnt"
mount_partition
clear

echo "6. Installing base packages"
install_pkgs
clear

echo "7. Fstab"
genfstab -U /mnt/arch-root >> /mnt/arch-root/etc/fstab
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
sed -i 's/block filesystems/block encrypt filesystems/g' /mnt/arch-root/etc/mkinitcpio.conf
chrun 'mkinitcpio -p linux'
clear

echo "13. Root password"
chrun passwd
clear

echo "14. Bootloader"
install_refind
clear

echo "15. Add user"
add_user
clear

echo "16. Extras installing"
extras
clear

}

main


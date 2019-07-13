chrun() {
    arch-chroot /mnt /bin/bash -c "$1"
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

    cryptsetup -y -v luksFormat /dev/sda2
    cryptsetup open /dev/sda2 cryptroot

    mkfs.btrfs -L root /dev/mapper/cryptroot
    mkfs.vfat -F32 /dev/sda1

}

mount_partition() {

    mount /dev/mapper/cryptroot /mnt
    mkdir /mnt/boot
    mount /dev/sda1 /boot

}

install_pkgs() {

    pacstrap /mnt base base-devel intel-ucode refind-efi dialog networkmanager git wget yajl xorg-server xorg-apps sddm plasma i3 termite vim zsh

}

make_swap() {

    chrun fallocate -l 2048M /swapfile
    chrun chmod 600 /swapfile
    chrun mkswap /swapfile
    chrun swapon /swapfile
    chrun echo "/swapfile none swap defaults 0 0" >> /etc/fstab

}

localization() {

    chrun vim /etc/locale.gen
    chrun locale-gen
    chrun echo "LANG=en_US.UTF-8" > /etc/locale.conf

}

install_refind() {

    chrun refind-install
    chrun uuid=$(cat /etc/fstab | grep "ext4")
    chrun echo "\"Boot using default options\"     \"root=UUID=${uuid:5:36} rw add_efi_memmap init    rd=/boot/intel-ucode.img initrd=/boot/initramfs-linux.img\"" > /boot/refind_linux.conf

}

add_user() {

    chrun useradd -m -H video,audio,input,whell,users -s /bin/zsh iliayar
    chrun passwd iliayar
    chrun visudo

}

extras() {
    chrun mkdir /builds
    chrun cd /builds; git clone https://aur.archlinux.org/package-query.git
    chrun cd /builds/package-query/; makepkg -si
    chrun cd /builds; git clone https://aur.archlinux.org/yaourt.git
    chrun cd /builds/yaourt/; makepkg -si
    chrun rm -Rf /builds

    chrun systemctl enable sddm
    chrun enable NetworkManager
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
genfstab -U /mnt >> /mnt/etc/fstab
clear

echo "8. Swapfile"
make_swap
clear

echo "9. Time zone"
chrun ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
chrun hwclock --systohc
clear

echo "10. Localization"
localization
clear

echo "11. Network"
chrun vim /etc/hostname
chrun vim /etc/hosts
clear

echo "12. Initramfs"
sed -i 's/base autodetect/base udev autodetect/g' /mnt/etc/mkinitcpio.conf
sed -i 's/autodetect consolefont/autodetect keyboard consolefont/g' /mnt/etc/mkinitcpio.conf
sed -i 's/block filesystems/block encrypt filesystems/g' /mnt/etc/mkinitcpio.conf
chrun mkinitcpio -p linux
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

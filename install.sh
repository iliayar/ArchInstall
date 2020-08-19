ARCH_ROOT=/mnt
MANUAL=0

MOUNT_POINT=()
DEVICE=()
LABEL=()

DEVICE_COUNT=0

get_uuid() {
    ls -l /dev/disk/by-uuid/ | grep $1 | awk '{print $9}'
}


chrun() {
    artools-chroot $ARCH_ROOT /bin/bash -c "$1"
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
	    # TODO: connman
	fi
    done

}


partition() {

    echo "   Partitioning"
    /bin/bash # TODO: fdisk
    echo "Leave empty for skip"


    for device in $(lsblk | grep "─" | awk '{print $1}'); do
	printf "${device:2} > "; read mount_point

	[[ -z $mount_point ]] && continue

	DEVICE+=(/dev/${device:2})
	MOUNT_POINT+=($mount_point)

	DEVICE_COUNT=$((DEVICE_COUNT+1))
    done

}

fmt_enc_partition() {
    

    for i in $(seq 0 $((DEVICE_COUNT)) ); do
	if [[ ${MOUNT_POINT[$i]} == "/" ]]; then
	    cryptsetup luksFormat --force-password ${DEVICE[$i]}
	    cryptsetup open ${DEVICE[$i]} cryptroot

	    mkfs.btrfs -L archroot /dev/mapper/cryptroot

	    mount /dev/mapper/cryptroot $ARCH_ROOT/

	    LABEL+=(_)

	    continue
	fi
    done

    mkdir $ARCH_ROOT/etc
    mkdir $ARCH_ROOT/etc/keyfiles

    #TODO sorting by depth

    for i in $(seq 0 $((DEVICE_COUNT-1)) ); do
	[[ ${MOUNT_POINT[$i]} = "/" ]] && continue
	if [[ ${MOUNT_POINT[$i]} = "/boot" ]]; then
	    mkfs.vfat -F32 ${DEVICE[$i]}
	    
	    LABEL+=(_)
	    
	    continue
	fi

	LABEL+=(crypt$(echo ${MOUNT_POINT[$i]} | sed -e "s/\///g"))

	dd bs=512 count=4 if=/dev/random of=$ARCH_ROOT/etc/keyfiles/${LABEL[$i]} iflag=fullblock
	chmod 600 $ARCH_ROOT/etc/keyfiles/${LABEL[$i]}

	cryptsetup luksFormat --force-password ${DEVICE[$i]} $ARCH_ROOT/etc/keyfiles/${LABEL[$i]}
	cryptsetup open ${DEVICE[$i]} ${LABEL[$i]} --key-file $ARCH_ROOT/etc/keyfiles/${LABEL[$i]}

	mkfs.btrfs  /dev/mapper/${LABEL[$i]}

    done

    for i in $(seq 0 $((DEVICE_COUNT-1))); do
	[[ ${MOUNT_POINT[$i]} == "/" ]] && continue
	[[ ${MOUNT_POINT[$i]} == "/boot" ]] && mkdir $ARCH_ROOT/boot; mount ${DEVICE[$i]} $ARCH_ROOT/boot; continue
	mkdir -p $ARCH_ROOT${MOUNT_POINT[$i]}
	mount /dev/mapper/${LABEL[$i]} $ARCH_ROOT${MOUNT_POINT[$i]}
    done

}

install_pkgs() {

    basestrap $ARCH_ROOT base base-devel intel-ucode refind-efi dialog btrfs-progs sudo networkmanager git wget yajl xorg-server xorg-apps vim reflector linux linux-firmware mkinitcpio

}

make_swap() {
    artools-chroot $ARCH_ROOT /bin/bash <<EOF
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
    artools-chroot $ARCH_ROOT /bin/bash <<EOF
    cd /boot/EFI
    mkdir boot
    cp refind/refind_x64.efi boot/bootx64.efi
EOF
    for i in $(seq 0 $((DEVICE_COUNT-1)) ); do
	if [[ ${MOUNT_POINT[$i]} == "/" ]]; then
	    uuid=$(get_uuid ${DEVICE[$i]:5})
	fi
    done
    cat > $ARCH_ROOT/boot/EFI/refind/refind.conf <<EOF
timeout 10

menuentry "Arch Linux" {
    icon     /EFI/refind/icons/os_arch.png
    volume   "ESP"
    loader   /vmlinuz-linux
    initrd   /intel-ucode.img
    initrd   /initramfs-linux.img
    options  "cryptdevice=UUID=$uuid:cryptroot root=/dev/mapper/cryptroot rw add_efi_memmap"
    submenuentry "Boot to terminal" {
	add_options "systemd.unit=multi-user.target"
    }
    enabled
}
EOF
    echo "cryptroot UUID=$uuid none" >> $ARCH_ROOT/etc/crypttab
    for i in $(seq 0 $((DEVICE_COUNT-1)) ); do
	[[ ${MOUNT_POINT[$i]} == "/" ]] && continue
	[[ ${MOUNT_POINT[$i]} == "/boot" ]] && continue
	echo "${LABEL[$i]} UUID=$(get_uuid ${DEVICE[$i]:5}) /etc/keyfiles/${LABEL[$i]} luks" >> $ARCH_ROOT/etc/crypttab
    done
}

add_user() {

    chrun 'useradd -m -G video,audio,input,wheel,users -s /bin/bash iliayar'
    chrun 'passwd iliayar'
    sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g" $ARCH_ROOT/etc/sudoers

}

extras() {
    chrun 'reflector --latest 100 --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist'
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
    sudo ntpd -qg
    sudo hwclock -w
    clear

    echo "3. Partition the disks"
    [[ MANUAL -eq 2 ]] && partition || /bin/bash
    clear

    echo "4. Format And Encrypt partitions"
    [[ MANUAL -eq 2 ]] && fmt_enc_partition || /bin/bash
    clear

    echo "5. Installing base packages"
    install_pkgs
    clear

    echo "6. Fstab"
    sudo bash -c "fstabgen -U $ARCH_ROOT >> $ARCH_ROOT/etc/fstab"
    clear

    echo "7. Swapfile"
    make_swap
    clear

    echo "8. Time zone"
    chrun 'ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime'
    chrun 'hwclock --systohc'
    clear

    echo "9. Localization"
    localization
    clear

    echo "10. Network"
    chrun 'echo "ArchLaptop" > /etc/hostname'
    chrun 'echo "127.0.0.1 localhost" >> /etc/hosts'
    clear

    echo "11. Initramfs"
    [[ MANUAL -eq 2 ]] && sed -i 's/block filesystems/block encrypt filesystems/g' $ARCH_ROOT/etc/mkinitcpio.conf || /bin/bash
    chrun 'mkinitcpio -p linux'
    clear

    echo "12. Root password"
    chrun passwd
    clear

    echo "13. Bootloader"
    [[ MANUAL -eq 2 ]] && install_refind || /bin/bash
    clear

    echo "14. Add user"
    add_user
    clear

    echo "15. Extras installing"
    extras
    clear

}

main


ARCH_ROOT=/mnt
MANUAL=0

MOUNT_POINT=()
DEVICE=()
LABEL=()

DEVICE_COUNT=0

get_uuid() {
    ls -l /dev/disk/by-uuid/ | grep $1 | awk '{print $9}'
}

partition() {

    echo "   Partitioning"
    cfdisk
    parted -l
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

    # TODO: sorting by depth
    # NOTE: Just sort is OK

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
install_refind() {

    chrun refind-install
    arch-chroot $ARCH_ROOT /bin/bash <<EOF
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

main() {

    echo "1. Partition the disks"
    partition
    clear

    echo "2. Format And Encrypt partitions"
    fmt_enc_partition
    clear

}

main


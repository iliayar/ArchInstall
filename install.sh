echo "After completing press Ctrl-D"
echo "1. Connect to the Internet"
/bin/bash
echo "2. Update System clock"
timedatectl set-ntp true
echo "3. Partition the disks"
echo "   Boot partition is 256-512 MiB"
fdisk -l
/bin/bash
echo "4. Format partitions"
echo "   Boot partition: mkfs.fat -F32 /dev/sdxY"
echo "   Linux partition: mkfs.ext4 /dev/sdxY"
fdisk -l
/bin/bash
echo "5. Mount partitions to /mnt"
/bin/bash
echo "6. Installing base packages"
pacstrap /mnt base base-devel intel-ucode refind-efi dialog networkmanager
echo "7. Fstab"
genfstab -U /mnt >> /mnt/etc/fstab
echo "8. Chroot and swapfile"
arch-chroot /mnt
fallocate -l 2048M /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab
echo "9. Time zone"
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc
echo "10. Localization"
vi /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "11. Network"
vi /etc/hostname
vi /etc/hosts
echo "12. Initramfs"
mkinitcpio -p linux
echo "13. Root password"
passwd
echo "14. Bootloader"
echo "    Edit /boot/refind_linux.conf like:"
echo '    "Boot using default options"     "root=UUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX rw add_efi_memmap initrd=/boot/intel-ucode.img initrd=/boot/initramfs-%v.img"'
refind-install
echo "15. Rebooting"
exit
umount -R /mnt
echo "You can reboot now"

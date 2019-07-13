echo "After completing press Ctrl-D"
echo "1. Connect to the Internet"
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

echo "2. Update System clock"
timedatectl set-ntp true
echo "3. Partition the disks"
echo "   Boot partition is 256-512 MiB"
echo "   1. Automatic with boot partiotion"
echo "   2. Automatic without boot partition"
echo "   3. Manual"
while true; do
	echo "Choose: "
	read test
	echo $test | grep -G -q "^[123]$" && break
done
if [[ $test -eq 1 ]]; then
	echo "Enter device: "
	read device
	fdisk $device <<EOF
n


+512M
t

1
n



w
EOF
	fdisk -l
elif [[ $test -eq 2 ]]; then
	echo "Enter device: "
	read $device
	fdisk $device <<EOF
n



EOF
	fdisk -l
elif [[ $test -eq 3 ]]; then
	/bin/bash
fi

echo "4. Format partitions"
echo "   Boot partition: mkfs.fat -F32 /dev/sdxY"
echo "   Linux partition: mkfs.ext4 /dev/sdxY"
echo "5. Mount partitions to /mnt"

echo "   1. Automatic with boot partiotion"
echo "   2. Automatic without boot partition"
echo "   3. Manual"
while true; do
	echo "Choose: "
	read test
	echo $test | grep -G -q "^[123]$" && break
done
if [[ $test -eq 1 ]]; then
	echo "Enter boot device: "
	read $boot_device
	echo "Enter device: "
	read $device
	mkfs.fat -F32 $boot_device
	mkfs.ext4 $device
elif [[ $test -eq 2 ]]; then
	echo "Enter device: "
	read $device
	mkfs.ext4 $device
elif [[ $test -eq 3 ]]; then
	/bin/bash
fi

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
uuid=$(cat /etc/fstab | grep "ext4")
echo "\"Boot using default options\"     \"root=UUID=${uuid:5:36} rw add_efi_memmap init    rd=/boot/intel-ucode.img initrd=/boot/initramfs-linux.img\"" > /boot/refind_linux.conf
echo "15. Rebooting"
exit
umount -R /mnt
echo "You can reboot now"

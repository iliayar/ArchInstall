echo "1. Connect to Internet"
/bin/bash
echo "2. Add user"
useradd -m -H video,audio,input,wheel,users -s /bin/bash iliayar
passwd iliayar
visudo
su iliayar
cd
echo "3. AUR"
sudo pacman -S --needed base-devel git wget yajl
git clone https://aur.archlinux.org/package-query.git
cd package-query/
makepkg -si
cd ../
git clone https://aur.archlinux.org/yaourt.git
cd yaourt/
makepkg -si
cd ../
sudo rm -dR yaourt/ package-query/
echo "4. GUI"
sudo pacman -S xorg-server xorg-apps sddm plasma i3 termite
sudo systemctl enable sddm
sudo systemctl enable NetorkManager
echo "Reboot"


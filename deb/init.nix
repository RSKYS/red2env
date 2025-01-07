# Debian optimized installer for VM, Cloud, etc.

# Copyright 2025 Pouria Rezaei <Pouria.rz@outlook.com>
# All rights reserved.

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License at <http://www.gnu.org/licenses/> for
# more details.

{ pkgs ? import <nixpkgs> {} }:

let
  Mirror="http://mirror.ox.ac.uk";      # mirror' url
  Port="22";                            # ssh's port
in

# BTW, genfstab doesn't exist around officially so, commented for now.
pkgs.mkShell {
  name = "isolated-environment";
  buildInputs = [
    #pkgs.git
    #pkgs.python3Packages.pip
    pkgs.debootstrap
    pkgs.util-linux
    pkgs.bash
  ];

  shellHook = ''

if [ $(id -u) != "0" ]; then
	echo "Script needs to run under superuser."
	exit 1
fi

ch_exec() {
	chroot '/mnt' /bin/bash -c "$*"
}

export MIRROR="${toString Mirror}"
export PORT="${toString Port}"

echo 'y' | mkfs.fat -F 32 /dev/sda1
echo 'y' | mkfs.ext4 /dev/sda2
mkswap /dev/sda3

mount /dev/sda2 /mnt
mkdir -p /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi

mkdir -p /mnt/etc/ssh/sshd_config.d
cat > "/mnt/etc/ssh/sshd_config.d/50-Debian.conf" <<SSH
Port $PORT
PermitRootLogin yes
PasswordAuthentication yes

SSH

debootstrap --arch amd64 \
    --include=sudo,bash,dbus,locales,vim,wget,ca-certificates,curl,systemd-timesyncd,neofetch,zstd,parted,cron,dosfstools,git,openssh-server,build-essential,python3-venv,python3-pip,grub-efi-amd64,open-vm-tools \
        bookworm /mnt $MIRROR/debian

mount --rbind /dev /mnt/dev
mount --rbind /sys /mnt/sys
mount --rbind /proc /mnt/proc
mount --rbind /tmp /mnt/tmp
swapon /dev/sda3

#genfstab -U /mnt > /mnt/etc/fstab
cp -rf /etc/network/interfaces /mnt/etc/network/
echo "\nneofetch\n" >> /mnt/etc/profile

cat > /mnt/etc/default/locale <<LCL
LANG=en_US.UTF-8

LCL

cat > /mnt/etc/locale.gen <<LCL
en_GB.UTF-8 UTF-8
en_US.UTF-8 UTF-8

LCL

cat > /mnt/etc/apt/sources.list <<MGM
deb $MIRROR/debian/ bookworm contrib main non-free non-free-firmware

deb $MIRROR/debian/ bookworm-updates contrib main non-free non-free-firmware

deb $MIRROR/debian/ bookworm-proposed-updates contrib main non-free non-free-firmware

deb $MIRROR/debian/ bookworm-backports contrib main non-free non-free-firmware

deb http://security.debian.org/debian-security/ bookworm-security contrib main non-free non-free-firmware

MGM

ch_exec "DEBIAN_FRONTEND=noninteractive \
        dpkg-reconfigure locales; \
    apt update && \
    apt dist-upgrade --autoremove -y && \
    apt install -y linux-image-amd64 linux-headers-amd64 firmware-linux"

ch_exec "sed -i '/etc/default/grub' -e 's/=5/=0/'; \
    grub-install --force --removable && \
    grub-mkconfig -o /boot/grub/grub.cfg"

ch_exec "passwd"

'';
}

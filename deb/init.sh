#!/bin/bash

# Debian optimized installer for VM, Cloud, etc.

# Copyright 2025 Pouria Rezaei <Pouria.rz@outlook.com>
# All rights reserved.
#
# Redistribution and use of this script, with or without modification, is
# permitted provided that the following conditions are met:
#
# 1. Redistributions of this script must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
#  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO
#  EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
#  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
#  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
#  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# General Variables
MIRROR="http://mirror.ox.ac.uk"
Port="22"

#Check user privilege
if [[ $(id -u) != "0" ]]; then
	echo "Script needs to run under superuser."
	exit 1
fi

ch_exec() {
	chroot '/mnt' /bin/bash -c "$*"
}

#dhclient
apt update
apt install dosfstools debootstrap arch-install-scripts -y

set -e

echo 'y' | mkfs.fat -F 32 /dev/sda1
#echo 'y' | mkswap -L /dev/sda2
echo 'y' | mkfs.ext4 /dev/sda3

mount /dev/sda3 /mnt
mkdir -p /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi
  
# wget $(python3 -c "import requests, re; \
#         url = 'http://archive.debian.org/debian/pool/main/d/debootstrap/'; \
#         response = requests.get(url); \
#         match = re.search(r'href=\"(debootstrap_[^\"]+\.deb)\"', response.text); \
#         print(url + match.group(1))")

# dpkg -i debootstrap*.deb
# rm -rf debootstrap*.deb

mkdir -p /mnt/etc/ssh/sshd_config.d
cat > "/mnt/etc/ssh/sshd_config.d/50-Debian.conf" <<SSH
Port $PORT
PermitRootLogin yes
PasswordAuthentication yes
SSH

debootstrap --arch amd64 \
    --include=sudo,locales,vim,wget,ca-certificates,curl,systemd-timesyncd,neofetch,zstd,parted,cron,dosfstools,git,openssh-server,build-essential,python3-venv,python3-pip,linux-image-amd64,linux-headers-amd64,grub-efi-amd64,open-vm-tools \
        bookworm /mnt $MIRROR/debian

swapon /dev/sda2
mount --rbind /dev /mnt/dev
mount --rbind /sys /mnt/sys
mount --rbind /proc /mnt/proc
mount --rbind /tmp /mnt/tmp

genfstab -U /mnt > /mnt/etc/fstab
cp -rf /etc/network/interfaces /mnt/etc/network/
echo -e "\nneofetch\n" >> /mnt/etc/profile

cat >> /mnt/etc/default/locale <<LCL
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
LCL

cat > /mnt/etc/apt/sources.list <<MGM
deb $MIRROR/debian/ bookworm contrib main non-free non-free-firmware

deb $MIRROR/debian/ bookworm-updates contrib main non-free non-free-firmware

deb $MIRROR/debian/ bookworm-proposed-updates contrib main non-free non-free-firmware

deb $MIRROR/debian/ bookworm-backports contrib main non-free non-free-firmware

deb http://security.debian.org/debian-security/ bookworm-security contrib main non-free non-free-firmware

MGM

ch_exec "apt update && \
    locale-gen && \
    apt dist-upgrade --autoremove -y"

ch_exec "grub-install --force --removable && \
    sed -i '/etc/default/grub' -e 's/=5/=0/' && \
    grub-mkconfig -o /boot/grub/grub.cfg"

ch_exec "passwd"

#!/bin/bash

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

# WARNING: The script destroys existing data on the chosen drive.
# This script only supports EFI.

MIRROR="http://mirror.rackspace.com"
PORT=${PORT:-22}
VERSION=${VERSION:-bookworm}

#Check user privilege
if [ $(id -u) != "0" ]; then
	echo "Script needs to run under superuser."
	exit 1
fi

ch_exec() {
	chroot '/mnt' /bin/bash -c "$*"
}

apt update
apt install arch-install-scripts debootstrap dosfstools gdisk parted -y

set -euo pipefail

err() { printf '%s\n' "$*" >&2; }

# Messing with disk here.. fuuuck.

for cmd in parted blockdev; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "$cmd not found. Were you connected to internet?"
    exit 1
  fi
done

read -r -p "Enter target disk (e.g /dev/sdX, /dev/nvme0n1): " DISK

if [ -z "$DISK" ]; then
  err "No disk drive provided.. Exiting."
  exit 1
fi

if [ ! -b "$DISK" ]; then
  err "Device '$DISK' does not exist or not a block device."
  exit 1
fi

TOTAL_BYTES=$(blockdev --getsize64 "$DISK")
TOTAL_MIB=$(( TOTAL_BYTES / 1024 / 1024 ))

if [ "$TOTAL_MIB" -lt 10240 ]; then
  err "Drive size appears extremely small.. Aborting."
  exit 1
fi

DISK1_START=1
DISK1_END=257

LEAVE_END="${LEAVE_END:-1024}"
read -r -p "Enter size for SWAP in MB [default 1024]: " LEAVE_END

DISK2_START=$DISK1_END
DISK2_END=$(( TOTAL_MIB - LEAVE_END ))
DISK3_START=$DISK2_END
unset LEAVE_END

# Final sanity checks
if [ "$DISK2_END" -le "$DISK2_START" ]; then
  err "Computed ${DISK}2 end ($DISK2_END MiB) is <= ${DISK}disk2 start ($DISK2_START MiB). Aborting."
  exit 1
fi

while true; do
    read -r -p "Shall I proceed? (y/N): " CONFIRM
    CONFIRM=$(printf '%s' "$CONFIRM" | tr '[:upper:]' '[:lower:]')

    if [ -z "$CONFIRM" ]; then
        CONFIRM="n"
    fi

    case "$CONFIRM" in
    y|yes)
        echo "Proceeding..."
        unset CONFIRM
        break
        ;;
    n|no)
        echo "Aborted by user."
        exit 0
        ;;
    *)
        echo "Invalid input. y/N?"
        ;;
    esac
done


unset CONFIRM
echo "Writing GPT and creating partitions..."

MOUNTED=$(lsblk -nr -o NAME,MOUNTPOINT "$DISK" | awk '$2!="" {print $1}')
if [ -n "$MOUNTED" ]; then
  echo "Attempting to unmount the in use drive..."
  for DPART in $MOUNTED; do
    [ -z "$DPART" ] && continue
    sudo umount -l "/dev/$DPART" || {
      echo -e "Failed to unmount /dev/$DPART..\n\
You probably need to do it manually."
      unset MOUNTED DPART
      exit 1
    }
  done
  unset DPART
fi
unset MOUNTED

parted -s "$DISK" mklabel gpt
parted -s "$DISK" unit mib mkpart primary ${DISK1_START} ${DISK1_END}
sgdisk --typecode=1:EF00 "$DISK"
unset DISK1_START DISK1_END

parted -s "$DISK" unit mib mkpart primary ${DISK2_START} ${DISK2_END}
sgdisk --typecode=2:8300 "$DISK"
unset DISK2_START DISK2_END

parted -s "$DISK" unit mib mkpart primary ${DISK3_START} 100%
sgdisk --typecode=3:8200 "$DISK"
unset DISK3_START

echo 'y' | mkfs.fat -F 32 "${DISK}1"
echo 'y' | mkfs.ext4 "${DISK}2"
mkswap "${DISK}3"

mount "${DISK}2" /mnt
mkdir -p /mnt/boot/efi
mount "${DISK}1" /mnt/boot/efi

mkdir -p /mnt/etc/ssh/sshd_config.d
cat > "/mnt/etc/ssh/sshd_config.d/50-Debian.conf" <<SSH
Port $PORT
PermitRootLogin yes
PasswordAuthentication yes

SSH
unset DISK PORT

debootstrap --arch amd64 \
    --include=sudo,bash,dbus,locales,vim,wget,ca-certificates,curl,systemd-timesyncd,neofetch,zstd,parted,cron,dosfstools,git,openssh-server,build-essential,python3-venv,python3-pip,grub-efi-amd64,open-vm-tools \
        $VERSION /mnt $MIRROR/debian

mount --rbind /dev /mnt/dev
mount --rbind /sys /mnt/sys
mount --rbind /proc /mnt/proc
mount --rbind /tmp /mnt/tmp
swapon /dev/sda3

genfstab -U /mnt > /mnt/etc/fstab
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
deb $MIRROR/debian/ ${VERSION} contrib main non-free non-free-firmware

deb $MIRROR/debian/ ${VERSION}-updates contrib main non-free non-free-firmware

deb $MIRROR/debian/ ${VERSION}-proposed-updates contrib main non-free non-free-firmware

deb $MIRROR/debian/ ${VERSION}-backports contrib main non-free non-free-firmware

deb $MIRROR/debian-security/ ${VERSION}-security contrib main non-free non-free-firmware

MGM
unset MIRROR VERSION

ch_exec "DEBIAN_FRONTEND=noninteractive \
        dpkg-reconfigure locales; \
    apt update && \
    apt dist-upgrade --auto-remove -y && \
    apt install -y linux-image-amd64 linux-headers-amd64 firmware-linux"

ch_exec "sed -i '/etc/default/grub' -e 's/=5/=0/'; \
    grub-install --force --removable \
      --target=x86_64-efi \
      --efi-directory=/boot/efi && \
    grub-mkconfig -o /boot/grub/grub.cfg"

ch_exec "passwd"

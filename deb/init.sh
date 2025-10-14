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

# Prompt and calculate:

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

# Begin the actual disk terraforming:

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
    --include=sudo,bash,dbus,locales,vim,wget,ca-certificates,curl,systemd-timesyncd,zstd,parted,cron,dosfstools,git,openssh-server,build-essential,python3-venv,python3-pip,grub-efi-amd64,open-vm-tools \
        $VERSION /mnt $MIRROR/debian

mount --rbind /dev /mnt/dev
mount --rbind /sys /mnt/sys
mount --rbind /proc /mnt/proc
mount --rbind /tmp /mnt/tmp
swapon /dev/sda3

genfstab -U /mnt > /mnt/etc/fstab
cp -rf /etc/network/interfaces /mnt/etc/network/

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

# Who said you couldn't replace Ubuntu..?
ch_exec "DEBIAN_FRONTEND=noninteractive \
        apt install -y --no-install-recommends --no-install-suggests \
    adwaita-icon-theme appstream apt-file at-spi2-core bash-completion bc \
    bcache-tools bolt btrfs-progs byobu command-not-found console-setup \
    cryptsetup cryptsetup-initramfs dbus-user-session dconf-gsettings-backend \
    distro-info e2fsprogs-l10n eatmydata ed efibootmgr eject ethtool exfatprogs \
    file fonts-dejavu-core friendly-recovery ftp gdisk gir1.2-packagekitglib-1.0 \
    gnome-keyring gnome-keyring-pkcs11 gnupg-l10n gpg-wks-client gpg-wks-server \
    gtk-update-icon-cache hdparm hicolor-icon-theme htop inetutils-telnet info \
    iptables iputils-tracepath irqbalance jq krb5-locales libaio1 libappstream4 \
    libarchive13 libatasmart4 libatk-bridge2.0-0 libatk1.0-0 libatm1 libatspi2.0-0 \
    libavahi-client3 libavahi-common-data libblockdev-crypto2 libblockdev-fs2 \
    libblockdev-loop2 libblockdev-part-err2 libblockdev-part2 libblockdev-swap2 \
    libblockdev-utils2 libblockdev2 libcolord2 libcups2 libduktape207 libdw1 \
    libepoxy0 libevent-2.1-7 libevent-core-2.1-7 libfile-find-rule-perl \
    libflashrom1 libfstrm0 libfwupd2 libgcab-1.0-0 libgcr-ui-3-1 \
    libgdk-pixbuf2.0-bin libglib2.0-bin libgnutls-dane0 libgpg-error-l10n \
    libgstreamer1.0-0 libgtk-3-0 libgtk-3-bin libgtk-3-common libgusb2 \
    libidn12 libintl-xs-perl libisns0 libjaylink0 libjemalloc2 libjim0.81 \
    libjpeg62-turbo libldap-common liblockfile1 liblognorm5 liblvm2cmd2.03 \
    libmagic-mgc libmagic1 libmbim-utils libmodule-find-perl \
    libmodule-scandeps-perl libnetplan0 libnpth0 libntfs-3g89 libopeniscsiusr \
    libpam-cap libpam-gnome-keyring libparted-fs-resize0 libpcap0.8 \
    libpolkit-agent-1-0 libproc-processtable-perl libprotobuf-c1 libpython3.11 \
    libqmi-utils librsvg2-2 librsvg2-common libsasl2-modules libsmbios-c2 \
    libsort-naturally-perl libssh-4 libstemmer0d libterm-readkey-perl \
    libtss2-esys-3.0.2-0 libtss2-mu0 libtss2-sys1 libtss2-tcti-cmd0 \
    libtss2-tcti-device0 libtss2-tcti-mssim0 libtss2-tcti-swtpm0 \
    libudisks2-0 libunbound8 liburcu8 libuv1 libvolume-key1 libwayland-cursor0 \
    libwayland-egl1 libxcomposite1 libxcursor1 libxdamage1 libxi6 libxinerama1 \
    libxmlb2 libxrandr2 lshw lsof lvm2 man-db manpages mdadm modemmanager mokutil \
    mtr-tiny multipath-tools ncurses-term netcat-openbsd networkd-dispatcher \
    ntfs-3g open-iscsi os-prober overlayroot p11-kit packagekit-tools pastebinit \
    pinentry-curses pinentry-gnome3 plymouth pollinate powermgmt-base psmisc \
    publicsuffix python3-automat python3-babel python3-bcrypt python3-cffi-backend \
    python3-charset-normalizer python3-click python3-constantly python3-debian \
    python3-gdbm python3-hamcrest python3-hyperlink python3-incremental \
    python3-jaraco.classes python3-keyring python3-lazr.restfulclient \
    python3-openssl python3-rfc3987 python3-rich python3-secretstorage \
    python3-service-identity python3-six python3-software-properties \
    python3-systemd python3-twisted python3-uritemplate python3-webcolors \
    python3-zipp python3-zope.interface rsync rsyslog sbsigntool screen sg3-utils \
    software-properties-common sosreport squashfs-tools ssh-import-id strace tcpdump \
    telnet thermald thin-provisioning-tools time tpm-udev udisks2 upower \
    usb-modeswitch usb.ids usbutils usrmerge uuid-runtime wireless-regdb xauth \
    xdg-user-dirs xfsprogs xml-core zerofree"

# A bit of finishing touch
ch_exec "DEBIAN_FRONTEND=noninteractive \
        dpkg-reconfigure locales; \
    apt update && \
    apt dist-upgrade --auto-remove -y && \
    apt install -y linux-image-amd64 linux-headers-amd64 firmware-linux"

if [ "$(cat /mnt/etc/debian_version)" -ge 13 ]; then
  ch_exec "apt install -y fastfetch"
  echo "\nfastfetch\n" >> /mnt/etc/profile
else
  ch_exec "apt install -y neofetch"
  echo "\nneofetch\n" >> /mnt/etc/profile
fi

ch_exec "sed -i '/etc/default/grub' -e 's/=5/=0/'; \
    grub-install --force --removable \
      --target=x86_64-efi \
      --efi-directory=/boot/efi && \
    grub-mkconfig -o /boot/grub/grub.cfg"

ch_exec "passwd"

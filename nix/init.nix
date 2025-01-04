# NixOS optimized installer for VM, Cloud, etc.

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

pkgs.writeShellScriptBin "init-nixos" ''

  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as superuser."
    exit 1
  fi

  set -e

  echo 'y' | mkfs.fat -F 32 /dev/sda1
  echo 'y' | mkfs.ext4 /dev/sda3
  mkswap /dev/sda2

  mount /dev/sda3 /mnt
  mkdir -p /mnt/boot/efi
  mount /dev/sda1 /mnt/boot/efi
  swapon /dev/sda2

  nixos-generate-config --root /mnt

  curl https://raw.githubusercontent.com/RSKYS/red2env/master/nix/configuration.nix \
        > /mnt/etc/nixos/configuration.nix

  nixos-install
  
''

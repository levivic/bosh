#!/usr/bin/env bash
#
# Copyright (c) 2009-2012 VMware, Inc.

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash

disk_image=${work}/${stemcell_image_name}
image_mount_point=${work}/mnt

sudo apt-get install -y initramfs-tools s390-tools dmsetup

kpartx -dv ${disk_image}

# Map partition in image to loopback
device=$(losetup --show --find ${disk_image})
add_on_exit "losetup --verbose --detach ${device}"

device_partition=$(kpartx -av ${device} | grep "^add" | cut -d" " -f3)
add_on_exit "kpartx -dv ${device}"

loopback_dev="/dev/mapper/${device_partition}"

# Mount partition
image_mount_point=${work}/mnt
mkdir -p ${image_mount_point}

mount ${loopback_dev} ${image_mount_point}
add_on_exit "umount ${image_mount_point}"

touch ${image_mount_point}${device}
mount --bind ${device} ${image_mount_point}${device}
add_on_exit "umount ${image_mount_point}${device}"

mkdir -p `dirname ${image_mount_point}${loopback_dev}`
touch ${image_mount_point}${loopback_dev}
mount --bind ${loopback_dev} ${image_mount_point}${loopback_dev}
add_on_exit "umount ${image_mount_point}${loopback_dev}"

# GRUB 2 needs /sys and /proc to do its job
mount -t proc none ${image_mount_point}/proc
add_on_exit "umount ${image_mount_point}/proc"
mount -t sysfs none ${image_mount_point}/sys
add_on_exit "umount ${image_mount_point}/sys"

# Figure out uuid of partition
uuid=$(blkid -c /dev/null -sUUID -ovalue ${loopback_dev})

# create /etc/zipl.conf

cat > ${image_mount_point}/etc/zipl.conf << EOF 
[defaultboot]
defaultmenu = menu

:menu
target = /boot
1 = ubuntu
2 = old
default = 1
prompt = 1
timeout = 10

[ubuntu]
target = /boot
image = /boot/vmlinuz-4.4.0-22-generic
ramdisk = /boot/initrd.img-4.4.0-22-generic
parameters = "root=UUID=${uuid} console=ttyS0 console=ttyS1"

[old]
target = /boot
image = /boot/vmlinuz.old
ramdisk = /boot/initrd.img.old
parameters = root=/dev/disk/by-path/ccw-0.0.0250-part1 crashkernel=128M
optional = 1
EOF

if [ -f ${image_mount_point}/etc/zipl.conf ];then
  echo ${image_mount_point}/etc/zipl.conf
  chown -fLR root:root ${image_mount_point}/etc/zipl.conf
  chmod 755 ${image_mount_point}/etc/zipl.conf
  #zipl -c ${image_mount_point}/etc/zipl.conf
  run_in_chroot ${image_mount_point} "zipl -c /etc/zipl.conf"
fi


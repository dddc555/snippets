#!/bin/bash
set -euo pipefail

read -rp "First disk (e.g. /dev/sda): " DISK1
read -rp "Second disk (e.g. /dev/sdb): " DISK2

for DISK in "$DISK1" "$DISK2"; do
    if [ ! -b "$DISK" ]; then
        echo "ERROR: $DISK is not a block device"
        exit 1
    fi
done

echo
echo "WARNING: ALL DATA ON:"
echo "  $DISK1"
echo "  $DISK2"
echo "WILL BE DESTROYED."
echo

read -rp "Type YES to continue: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

echo "Removing existing signatures..."
wipefs -af "$DISK1"
wipefs -af "$DISK2"

echo "Creating RAID1..."
mdadm --create /dev/md0 \
    --level=1 \
    --raid-devices=2 \
    "$DISK1" "$DISK2"

udevadm settle

echo "Saving mdadm config..."
mkdir -p /etc/mdadm
grep -q "/dev/md0" /etc/mdadm/mdadm.conf 2>/dev/null || \
    mdadm --detail --scan >> /etc/mdadm/mdadm.conf

update-initramfs -u

echo "Creating LVM..."
pvcreate /dev/md0
vgcreate vgraid /dev/md0

echo "Creating thin pool (95% of VG)..."
lvcreate -l 95%VG -T vgraid/thinpool

echo "Adding storage to Proxmox..."
if ! grep -q '^lvmthin: raid1$' /etc/pve/storage.cfg 2>/dev/null; then
cat >> /etc/pve/storage.cfg <<EOF

lvmthin: raid1
        vgname vgraid
        thinpool thinpool
        content images,rootdir
EOF
fi

echo
echo "Completed."
echo
pvesm status

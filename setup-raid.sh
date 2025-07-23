#!/bin/bash

# Wait for a few seconds to ensure SSD devices are available.
sleep 10

# Define RAID device and mount point.
RAID_DEVICE="/dev/md0"
MOUNT_POINT="/mnt/raid0"

# Dynamically detect all unmounted ~375G NVMe devices.
DEVICES=$(lsblk -d -n -o NAME,SIZE,MOUNTPOINT | awk '$2=="375G" && $3=="" {print "/dev/" $1}' | sort | xargs)

# Dynamically calculate the number of RAID devices
NUM_DEVICES=$(echo $DEVICES | wc -w)

echo "Detected $NUM_DEVICES unmounted 375G NVMe devices:"
echo "$DEVICES"

# Wait for all devices to become available
echo "Waiting for devices to be ready..."
for dev in $DEVICES; do
    for i in {1..10}; do
        if [ -b "$dev" ]; then
            break
        else
            echo "  $dev not ready yet... ($i)"
            sleep 1
        fi
    done
    if [ ! -b "$dev" ]; then
        echo "ERROR: $dev did not appear after waiting. Aborting."
        exit 1
    fi
done

# Unmount any mounted partitions on these devices (if needed).
for d in $DEVICES; do
    sudo umount $d 2>/dev/null
done

# Remove any existing RAID (if necessary).
if [ -e "$RAID_DEVICE" ]; then
    echo "RAID device $RAID_DEVICE already exists. Stopping it..."
    sudo mdadm --stop "$RAID_DEVICE"
fi

echo "Wiping old RAID superblocks if any..."
for d in $DEVICES; do
    sudo mdadm --zero-superblock $d 2>/dev/null || true
done

# Create the RAID 0 array over the listed devices
if [ ! -e "$RAID_DEVICE" ]; then
    echo "Creating RAID 0 array on $DEVICES"
    sudo mdadm --create "$RAID_DEVICE" --level=0 --raid-devices=$NUM_DEVICES $DEVICES --assume-clean --force
fi

# Verify RAID device was created
if [ ! -b "$RAID_DEVICE" ]; then
    echo "ERROR: RAID device $RAID_DEVICE was not created. Aborting."
    exit 1
fi

# Check if the RAID device already has a filesystem.
fs_type=$(sudo blkid -o value -s TYPE "$RAID_DEVICE")
if [ -z "$fs_type" ]; then
    echo "No filesystem detected on $RAID_DEVICE. Formatting with ext4..."
    sudo mkfs.ext4 -F "$RAID_DEVICE"
else
    echo "Detected filesystem of type $fs_type on $RAID_DEVICE; skipping format."
fi

# Create the mount point if it doesn't exist.
sudo mkdir -p "$MOUNT_POINT"

# Mount the RAID device.
sudo mount "$RAID_DEVICE" "$MOUNT_POINT" || {
    echo "ERROR: Failed to mount $RAID_DEVICE at $MOUNT_POINT"
    exit 1
}

# Optionally, adjust permissions so your application user can write.
sudo chown ted_willke:ted_willke "$MOUNT_POINT"

echo "RAID volume $RAID_DEVICE mounted at $MOUNT_POINT"

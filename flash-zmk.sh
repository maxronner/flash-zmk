#!/bin/bash

# ZMK Split Keyboard Flasher - Enhanced Version
# Supports configuration file and better device detection

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default configuration
CONFIG_FILE="${HOME}/.config/zmk-flasher.conf"
FIRMWARE_ZIP=""
MOUNT_POINT="/mnt"
LEFT_PATTERN="*left*.uf2"
RIGHT_PATTERN="*right*.uf2"
AUTO_DETECT=true
DRY_RUN=false
FLASH_LEFT=true
FLASH_RIGHT=true
EXPLICIT_LEFT=false
EXPLICIT_RIGHT=false
DEVICE_OVERRIDE=""
WORK_DIR=""
MOUNTED_DEVICE=""

# Load config file if it exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--firmware)
            FIRMWARE_ZIP="$2"
            shift 2
            ;;
        -m|--mount-point)
            MOUNT_POINT="$2"
            shift 2
            ;;
        --no-auto-detect)
            AUTO_DETECT=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --left)
            EXPLICIT_LEFT=true
            shift
            ;;
        --right)
            EXPLICIT_RIGHT=true
            shift
            ;;
        --device)
            DEVICE_OVERRIDE="$2"
            shift 2
            ;;
        -h|--help)
            echo "ZMK Split Keyboard Flasher"
            echo ""
            echo "Usage: $0 [OPTIONS] <firmware.zip>"
            echo ""
            echo "Options:"
            echo "  -f, --firmware FILE     Firmware zip file (required)"
            echo "  -m, --mount-point DIR   Mount point (default: /mnt)"
            echo "  --no-auto-detect        Disable automatic device detection"
            echo "  --dry-run               Simulate flashing without mounting or copying"
            echo "  --left                  Flash left half only"
            echo "  --right                 Flash right half only"
            echo "  --device PATH           Use this device path for flashing"
            echo "  -h, --help              Show this help message"
            echo ""
            echo "Configuration file: $CONFIG_FILE"
            exit 0
            ;;
        *)
            FIRMWARE_ZIP="$1"
            shift
            ;;
    esac
done

# If user selected specific halves, honor it
if [ "$EXPLICIT_LEFT" = true ] || [ "$EXPLICIT_RIGHT" = true ]; then
    FLASH_LEFT="$EXPLICIT_LEFT"
    FLASH_RIGHT="$EXPLICIT_RIGHT"
fi

if [ "$FLASH_LEFT" = false ] && [ "$FLASH_RIGHT" = false ]; then
    echo -e "${RED}Error: No halves selected (use --left and/or --right)${NC}"
    exit 1
fi

# If no firmware specified, require it as an argument
if [ -z "$FIRMWARE_ZIP" ]; then
    echo -e "${RED}Error: Firmware zip is required${NC}"
    echo "Specify with: $0 -f /path/to/firmware.zip"
    exit 1
fi

cleanup() {
    # Best-effort cleanup; don't mask original errors
    if [ -n "$MOUNTED_DEVICE" ] && [ "$DRY_RUN" = false ]; then
        sudo umount "$MOUNT_POINT" 2>/dev/null || true
        MOUNTED_DEVICE=""
    fi
    if [ -n "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR" 2>/dev/null || true
        WORK_DIR=""
    fi
}

on_interrupt() {
    echo -e "\n${YELLOW}Interrupted, cleaning up...${NC}"
    cleanup
    exit 130
}

trap 'cleanup' EXIT
trap 'on_interrupt' INT TERM

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ZMK Split Keyboard Flasher Enhanced   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

# Step 1: Extract firmware
echo -e "${YELLOW}➤ Extracting firmware from: $(basename "$FIRMWARE_ZIP")${NC}"
if [ ! -f "$FIRMWARE_ZIP" ]; then
    echo -e "${RED}  ✗ Error: $FIRMWARE_ZIP not found${NC}"
    exit 1
fi

WORK_DIR="$(mktemp -d)"
unzip -o -q "$FIRMWARE_ZIP" -d "$WORK_DIR"
echo -e "${GREEN}  ✓ Firmware extracted${NC}\n"

# Find the UF2 files
LEFT_FILE=$(ls "$WORK_DIR"/$LEFT_PATTERN 2>/dev/null | head -n1)
RIGHT_FILE=$(ls "$WORK_DIR"/$RIGHT_PATTERN 2>/dev/null | head -n1)

if [ -z "$LEFT_FILE" ] || [ -z "$RIGHT_FILE" ]; then
    echo -e "${RED}  ✗ Error: Could not find left and right firmware files${NC}"
    echo "    Looking for patterns: $LEFT_PATTERN and $RIGHT_PATTERN"
    exit 1
fi

echo -e "${GREEN}Found firmware files:${NC}"
echo -e "  Left:  ${BLUE}$LEFT_FILE${NC}"
echo -e "  Right: ${BLUE}$RIGHT_FILE${NC}\n"

# Function to detect bootloader device
detect_device() {
    local timeout=30
    local elapsed=0

    echo -e "${YELLOW}  Scanning for bootloader device...${NC}" >&2

    list_candidates() {
        # NAME SIZE TYPE RM TRAN
        lsblk -b -ndo NAME,SIZE,TYPE,RM,TRAN 2>/dev/null | awk '
            $2>10000000 && $2<100000000 && ($3=="disk" || $3=="part") && ($4==1 || $5=="usb" || $1 ~ /^sd/) {
                print "/dev/"$1
            }'
    }

    # If device is already connected, use it directly if unambiguous
    local existing_candidates
    existing_candidates=$(list_candidates)
    if [ -n "$existing_candidates" ]; then
        local candidate_count
        candidate_count=$(echo "$existing_candidates" | wc -l | tr -d ' ')
        if [ "$candidate_count" -eq 1 ]; then
            echo -e "${GREEN}  ✓ Found bootloader (already connected): $existing_candidates${NC}" >&2
            echo "$existing_candidates"
            return 0
        fi

        echo -e "${YELLOW}  ⚠ Multiple candidate devices already present:${NC}" >&2
        echo "$existing_candidates" >&2
        return 1
    fi

    # Get list of current block devices
    local old_candidates
    old_candidates=$(list_candidates | sed 's|/dev/||')

    while [ $elapsed -lt $timeout ]; do
        local new_candidates
        new_candidates=$(list_candidates | sed 's|/dev/||')

        # Find newly appeared devices
        for dev in $new_candidates; do
            if ! echo "$old_candidates" | grep -qx "$dev"; then
                echo -e "${GREEN}  ✓ Found bootloader: /dev/$dev${NC}" >&2
                echo "/dev/$dev"
                return 0
            fi
        done

        sleep 1
        ((elapsed++))
        echo -ne "\r${YELLOW}  Waiting... ${elapsed}s${NC}" >&2
    done

    echo -e "\n${YELLOW}  ⚠ Auto-detection timed out${NC}" >&2
    return 1
}

# Ensure sudo is available before asking to enter bootloader
ensure_sudo_access() {
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi

    if sudo -n true 2>/dev/null; then
        return 0
    fi

    echo -e "${YELLOW}➤ Checking sudo access${NC}"
    if ! sudo -v; then
        echo -e "${RED}  ✗ Sudo access required to mount and copy firmware${NC}"
        return 1
    fi
    echo -e "${GREEN}  ✓ Sudo access confirmed${NC}\n"
}

# Function to flash a half
flash_half() {
    local half_name=$1
    local firmware_file=$2

    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        Flashing $half_name Half          ${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"

    echo -e "${YELLOW}➤ Please connect the $half_name half in bootloader mode${NC}"
    echo -e "  (Double-tap reset button on nice!nano)"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}  [dry-run] Waiting for device...${NC}"
        sleep 1
        echo -e "${YELLOW}  [dry-run] Would mount device to $MOUNT_POINT${NC}"
        sleep 1
        echo -e "${YELLOW}  [dry-run] Would copy: $firmware_file${NC}"
        sleep 1
        echo -e "${YELLOW}  [dry-run] Would sync and unmount${NC}"
        sleep 1
        echo -e "${GREEN}  ✓ [dry-run] $half_name half simulated successfully!${NC}\n"
        return 0
    fi

    DEVICE=""

    if [ -n "$DEVICE_OVERRIDE" ]; then
        DEVICE="$DEVICE_OVERRIDE"
    elif [ "$AUTO_DETECT" = true ]; then
        echo -e "Press Enter when ready, or type a device path directly:"
        read -r -t 2 user_device 2>/dev/null || true

        if [ -n "$user_device" ]; then
            DEVICE="$user_device"
        else
            DEVICE=$(detect_device)
        fi
    fi

    if [ -z "$DEVICE" ]; then
        echo -e "\nEnter device path (e.g., /dev/sdl):"
        read DEVICE
    fi

    if [ ! -b "$DEVICE" ]; then
        echo -e "${RED}  ✗ Error: $DEVICE is not a valid block device${NC}"
        return 1
    fi

    echo -e "${YELLOW}  Mounting $DEVICE to $MOUNT_POINT...${NC}"
    sudo mount "$DEVICE" "$MOUNT_POINT" || {
        echo -e "${RED}  ✗ Failed to mount device${NC}"
        return 1
    }
    MOUNTED_DEVICE="$DEVICE"

    echo -e "${YELLOW}  Copying firmware...${NC}"
    sudo cp "$firmware_file" "$MOUNT_POINT/" || {
        sudo umount "$MOUNT_POINT"
        MOUNTED_DEVICE=""
        echo -e "${RED}  ✗ Failed to copy firmware${NC}"
        return 1
    }

    echo -e "${YELLOW}  Syncing and unmounting...${NC}"
    sudo sync
    sleep 1
    sudo umount "$MOUNT_POINT" || {
        echo -e "${YELLOW}  ⚠ Device may have auto-ejected (this is normal)${NC}"
    }
    MOUNTED_DEVICE=""

    echo -e "${GREEN}  ✓ $half_name half flashed successfully!${NC}\n"

    sleep 2
}

# Flash selected halves
if [ "$FLASH_LEFT" = true ]; then
    ensure_sudo_access || exit 1
    flash_half "LEFT" "$LEFT_FILE" || exit 1
fi
if [ "$FLASH_RIGHT" = true ]; then
    ensure_sudo_access || exit 1
    flash_half "RIGHT" "$RIGHT_FILE" || exit 1
fi

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     All Done! Keyboard Ready to Use    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}\n"

# Cleanup
echo -e "${YELLOW}Cleaning up...${NC}"
cleanup
echo -e "${GREEN}✓ Temporary files removed${NC}\n"

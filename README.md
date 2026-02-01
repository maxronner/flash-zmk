# ZMK Keyboard Flasher Scripts

Automate flashing firmware to split ZMK keyboards (like Corne, Lily58, etc.) with nice!nano controllers.

## Quick Start

### Enhanced Version (`flash-zmk.sh`)
Automation with auto-detection and configuration support:

```bash
# Make executable
chmod +x flash-zmk.sh

# Run with a firmware zip
./flash-zmk.sh /path/to/firmware.zip

# Simulate without flashing
./flash-zmk.sh --dry-run /path/to/firmware.zip

# Flash only one half
./flash-zmk.sh --left /path/to/firmware.zip
./flash-zmk.sh --right /path/to/firmware.zip
```

## Features

### Script
- Extracts the provided firmware zip to a temp directory
- Prompts for each half sequentially
- Handles mounting and copying
- Color-coded output
- **Auto-detection** of bootloader device when connected
- Configuration file support (`~/.config/zmk-flasher.conf`)
- Command-line options for flexibility
- Better error handling
- Prettier UI with progress indicators

## Setup

### One-Time Setup

1. **Copy script to your PATH:**
   ```bash
   sudo cp flash-zmk.sh /usr/local/bin/flash-zmk
   sudo chmod +x /usr/local/bin/flash-zmk
   ```

2. **Create config file (optional):**
   ```bash
   mkdir -p ~/.config
   # Create and edit with your preferences
   nano ~/.config/zmk-flasher.conf
   ```

3. **Set up sudo without password for mount (optional but recommended):**
   ```bash
   sudo visudo
   # Add this line (replace 'max' with your username):
   max ALL=(ALL) NOPASSWD: /bin/mount, /bin/umount, /bin/cp, /bin/sync
   ```

## Usage Workflow

### Manual Steps (can't be automated):
1. Download firmware.zip from GitHub Actions
2. Connect left half and put in bootloader mode (double-tap reset)
3. Connect right half and put in bootloader mode (double-tap reset)

### Automated Steps:
- Extract firmware.zip ✓
- Find correct .uf2 files ✓
- Detect bootloader device ✓
- Mount device ✓
- Copy firmware ✓
- Unmount device ✓
- Repeat for second half ✓

## Advanced Usage

### Create an alias
Add to your `~/.bashrc` or `~/.zshrc`:

```bash
alias flash='flash-zmk'
alias flashleft='flash-zmk /path/to/firmware.zip'  # If you want to flash left only
```

### Integration with GitHub Actions

Create a script that downloads latest firmware:

```bash
#!/bin/bash
# download-firmware.sh

REPO="yourusername/zmk-config"
cd ~/Downloads

# Get latest successful workflow run
gh run download --repo "$REPO" -n firmware

# Flash it
flash-zmk ~/Downloads/firmware.zip
```

### Udev Rules (Advanced)

Create automatic mounting when bootloader is connected:

```bash
# /etc/udev/rules.d/50-nice-nano.rules
SUBSYSTEM=="block", ATTRS{idVendor}=="239a", ATTRS{idProduct}=="0029", ACTION=="add", RUN+="/usr/local/bin/auto-flash.sh"
```

## Troubleshooting

### Device not detected
- Make sure you double-tap the reset button quickly
- Try unplugging and replugging the USB cable
- Check `lsblk` to see if device appears
- Manually specify device with `/dev/sdX`

### Permission denied
- Run with `sudo` if needed
- Or set up passwordless sudo (see Setup section)

### Wrong device mounted
- Disable auto-detection: `--no-auto-detect`
- Always verify the device before flashing

### Firmware files not found
- Check that firmware.zip contains files matching `*left*.uf2` and `*right*.uf2`
- Adjust patterns in config file if needed

## Customization

Edit the config file to customize:
- Mount point
- Firmware filename patterns
- Auto-detection behavior

## Safety Features

- Only flashes to small block devices (<100MB) to avoid accidentally flashing to wrong drive
- Prompts for confirmation on ambiguous devices
- Syncs before unmounting to ensure write completion
- Color-coded warnings and errors

## Tips

1. **Keep both halves disconnected** until script prompts for each one
2. **Use auto-detection** for fastest workflow
3. **Set up passwordless sudo** for mount/umount for smoothest experience
4. **Create an alias** for even faster access

## Example Session

```
$ flash-zmk ~/Downloads/firmware.zip

╔════════════════════════════════════════╗
║  ZMK Split Keyboard Flasher Enhanced  ║
╚════════════════════════════════════════╝

➤ Extracting firmware from: firmware.zip
  ✓ Firmware extracted

Found firmware files:
  Left:  corne_left-nice_nano_v2-zmk.uf2
  Right: corne_right-nice_nano_v2-zmk.uf2

╔════════════════════════════════════════╗
║        Flashing LEFT Half              ║
╚════════════════════════════════════════╝
➤ Please connect the LEFT half in bootloader mode
  (Double-tap reset button on nice!nano)

Press Enter when ready, or type a device path directly:
  Scanning for bootloader device...
  ✓ Found bootloader: /dev/sdl
  Mounting /dev/sdl to /mnt...
  Copying firmware...
  Syncing and unmounting...
  ✓ LEFT half flashed successfully!

[... repeats for RIGHT half ...]

╔════════════════════════════════════════╗
║     All Done! Keyboard Ready to Use   ║
╚════════════════════════════════════════╝
```

## License

MIT - Feel free to modify and share!

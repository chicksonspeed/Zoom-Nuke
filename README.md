# 🔥 Screw 1132 Overkill - macOS Zoom Nuke & Reinstall Tool

> **"Ben from IT" approved Zoom cleanup and reinstallation script for macOS**

## 📋 Overview

`Screw1132_Overkill.sh` is a comprehensive macOS script designed to completely remove Zoom and all associated data, clear hardware fingerprints, spoof network identifiers, and perform a fresh installation. This tool is particularly useful for:

- **Privacy-conscious users** who want to remove all Zoom tracking data
- **IT professionals** performing system cleanup
- **Users experiencing Zoom issues** requiring a complete reset
- **Security researchers** testing Zoom's data persistence

## 🚀 Features

### Core Functionality
- **Complete Zoom Removal**: Kills all processes and removes app + all user data
- **Hardware Fingerprint Clearing**: Removes system identifiers and caches
- **MAC Address Spoofing**: Attempts to change network interface MAC addresses
- **Network Cache Flushing**: Clears DNS and network-related caches
- **Fresh Installation**: Downloads and installs latest Zoom from official source

### Advanced Features
- **Deep Clean Mode**: Additional hardware fingerprint removal
- **Hardware Protection Script**: Creates a script for launching Zoom with protection
- **Comprehensive Logging**: Detailed logging of all operations
- **Backup Creation**: Backs up removed data before deletion
- **Network Connectivity Testing**: Ensures internet access before download
- **Package Integrity Verification**: Checks downloaded Zoom package

### Safety Features
- **Confirmation Prompts**: User confirmation before destructive operations
- **Error Handling**: Comprehensive error checking and recovery
- **System Requirements**: Validates macOS and required tools
- **Disk Space Checking**: Ensures sufficient space for operations
- **Graceful Failures**: Continues with partial success when possible

## 🛠️ Requirements

### System Requirements
- **macOS**: Any recent version (script checks compatibility)
- **Disk Space**: Minimum 500MB available space
- **Network**: Internet connection for Zoom download
- **Permissions**: Administrator privileges (sudo access)

### Required Tools
The script automatically checks for these system tools:
- `sudo` - Administrative privileges
- `curl` - Download manager
- `openssl` - Cryptographic operations
- `networksetup` - Network configuration
- `pkgutil` - Package management
- `system_profiler` - System information

## 📖 Usage

### Non-Technical Quick Start (Recommended)

1. Open the latest GitHub release for this project.
2. Download the file named `Zoom-Nuke-macOS-<version>.zip`.
3. Open the zip, then double-click `Zoom Nuke.app`.
4. Choose `Standard Clean` or `Deep Clean`.
5. Click `Start` (or `Cancel` to back out).
6. Terminal opens automatically and runs the script.
7. Enter your Mac password when asked.
8. If macOS blocks it the first time, right-click `Zoom Nuke.app` → **Open** → **Open**.

> The app is the easiest path. A `.command` launcher is still included as a fallback.

### Basic Usage

```bash
# Run with confirmation prompts
./Screw1132_Overkill.sh

# Force run without prompts
./Screw1132_Overkill.sh --force

# Enable deep hardware fingerprint removal
./Screw1132_Overkill.sh --deep-clean

# Combine options
./Screw1132_Overkill.sh --force --deep-clean
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `-f, --force` | Skip confirmation prompts |
| `-d, --deep-clean` | Enable deep hardware fingerprint removal |
| `-v, --version` | Show script version |
| `-h, --help` | Show usage information |

### Execution Flow

1. **System Validation** - Checks macOS, tools, and disk space
2. **Hardware Analysis** - Captures current hardware fingerprint
3. **User Confirmation** - Prompts for confirmation (unless --force)
4. **Process Termination** - Kills all Zoom processes
5. **Data Removal** - Removes Zoom app and all user data
6. **MAC Spoofing** - Attempts to change network interface MAC
7. **Cache Clearing** - Removes system caches and fingerprints
8. **Network Reset** - Flushes DNS and restarts network services
9. **Fresh Download** - Downloads latest Zoom from official source
10. **Installation** - Installs Zoom with verification
11. **Protection Setup** - Creates hardware protection script
12. **Cleanup** - Removes temporary files and logs results

## 📁 Files and Directories

### Created/Modified Files

| Path | Purpose |
|------|---------|
| `$HOME/zoom_fix.log` | Detailed execution log |
| `$HOME/.zoom_backup_YYYYMMDD_HHMMSS/` | Backup of removed data |
| `$HOME/.orig_mac_backup` | Original MAC address backup |
| `$HOME/.zoom_protection.sh` | Hardware protection script |
| `$HOME/Downloads/Zoom.pkg` | Downloaded Zoom installer |

### Removed Data

The script removes these Zoom-related items:

**Application:**
- `/Applications/zoom.us.app`

**User Data:**
- `~/Library/Application Support/zoom.us/`
- `~/Library/Caches/us.zoom.xos/`
- `~/Library/Preferences/us.zoom.xos.plist`
- `~/Library/Logs/zoom.us/`
- `~/Library/LaunchAgents/us.zoom.xos.plist`
- `~/Library/Containers/us.zoom.xos/`
- `~/Library/Saved Application State/us.zoom.xos.savedState/`

**System Data:**
- Package receipts
- Homebrew installations (if present)
- Various system caches

## 🔧 Technical Details

### MAC Address Spoofing

The script attempts MAC spoofing using multiple methods:

1. **Standard Method**: `ifconfig interface ether new_mac`
2. **Alternative Method**: `ifconfig interface lladdr new_mac`
3. **Restart Method**: Interface down → change MAC → interface up

**Note**: MAC spoofing may fail on modern macOS due to:
- Private Wi-Fi Address enabled
- System Integrity Protection (SIP)
- Network interface restrictions

### Hardware Fingerprint Removal

**Standard Clean:**
- System caches
- Browser caches
- Network identifiers
- Application caches

**Deep Clean (--deep-clean):**
- Additional system caches
- Spotlight index
- System logs
- Analytics data
- DHCP leases

### Network Reset Process

1. Flush DNS cache
2. Restart mDNSResponder
3. Clear network caches
4. Restart primary network service
5. Test connectivity

## 🛡️ Security Considerations

### What This Script Does
- Removes all Zoom tracking data
- Clears system fingerprints
- Attempts MAC address spoofing
- Creates protection mechanisms

### What This Script Does NOT Do
- Guarantee complete anonymity
- Bypass all tracking methods
- Work against advanced fingerprinting
- Provide legal protection

### Privacy Limitations
- Hardware fingerprinting is complex
- Some identifiers may persist
- Network-level tracking may continue
- Corporate/enterprise tracking may remain

## 🚨 Warnings

### ⚠️ Important Disclaimers

1. **Data Loss**: This script permanently removes Zoom data
2. **System Changes**: Modifies network and system settings
3. **Administrator Access**: Requires sudo privileges
4. **Network Disruption**: May temporarily disconnect network
5. **No Guarantees**: Cannot guarantee complete privacy/anonymity

### ⚠️ Legal Considerations

- Use only on systems you own or have permission to modify
- Respect applicable laws and regulations
- Consider corporate policies and terms of service
- This tool is for educational and legitimate use only

## 🔍 Troubleshooting

### Common Issues

**MAC Spoofing Fails:**
- Normal on modern macOS with SIP enabled
- Script continues with other cleanup methods
- Check if Private Wi-Fi Address is enabled

**Network Connectivity Issues:**
- Script waits and retries automatically
- Check firewall settings
- Verify internet connection

**Installation Fails:**
- Check disk space
- Verify package download integrity
- Ensure administrator privileges

**Permission Denied:**
- Ensure script is executable: `chmod +x Screw1132_Overkill.sh`
- Run with sudo if needed
- Check SIP status

### Log Analysis

Check the log file for detailed information:
```bash
cat ~/zoom_fix.log
```

### Recovery

If you need to restore data:
1. Check backup directory: `~/.zoom_backup_YYYYMMDD_HHMMSS/`
2. Restore original MAC: `cat ~/.orig_mac_backup`
3. Reinstall Zoom manually if needed

## 📝 Version History

- **v3.0.0**: Current version with enhanced features
- **v2.x**: Previous versions with basic functionality
- **v1.x**: Initial releases

## 🤝 Contributing

This script is part of a larger toolkit. For improvements or bug reports:

1. Test thoroughly on your system
2. Document any changes
3. Consider backward compatibility
4. Follow security best practices

## 📦 Release Packaging (Maintainers)

To make releases easier for non-technical users, this repo can generate a ready-to-run zip bundle:

```bash
./tools/build_release_bundle.sh v3.0.0
```

This creates `dist/Zoom-Nuke-macOS-v3.0.0.zip` with:
- `Zoom Nuke.app` (button-based launcher)
- `Start Zoom Nuke.command` (double-click launcher)
- `Screw1132_Overkill.sh` (main script)
- `README.md`
- `START_HERE.txt`

You can also build only the app:

```bash
./tools/build_macos_app.sh
```

There is also a GitHub Actions workflow that auto-builds and uploads this zip when a release is published.

## 📄 License

This script is provided as-is for educational and legitimate use. Use responsibly and in accordance with applicable laws and policies.

## 🙏 Acknowledgments

- **Ben from IT** - Inspiration and approval
- **macOS Community** - Technical insights
- **Privacy Researchers** - Fingerprinting knowledge
- **Open Source Community** - Tools and methodologies

---

**⚠️ Use responsibly and only on systems you own or have permission to modify.** 

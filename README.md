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

### Build Requirements (for creating app bundle)
- `bash` - For running the build script
- `chmod` - For setting executable permissions
- `mkdir` - For creating directory structure
- `cp` - For copying files

## 📖 Usage

### macOS App Bundle

For easy GUI access, you can create a macOS app bundle that can be launched from Finder:

```bash
# Build the macOS app bundle
./build_app_bundle.sh

# Launch the app bundle (equivalent to double-clicking in Finder)
open Screw1132_Overkill.app

# Or run the executable directly
./Screw1132_Overkill.app/Contents/MacOS/Screw1132_Overkill --help
```

The app bundle provides the same functionality as the command-line script but can be:
- **Double-clicked in Finder** to launch with default settings
- **Dragged to Applications folder** for easy access
- **Added to Dock** for quick launching
- **Run from Spotlight** by searching for "Screw 1132 Overkill"

### Basic Command-Line Usage

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

**Command-Line Script (`Screw1132_Overkill.sh`):**
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

**App Bundle Creation (`build_app_bundle.sh`):**
1. **Validation** - Checks source script exists and is readable
2. **Cleanup** - Removes any existing app bundle
3. **Structure Creation** - Creates proper macOS app bundle directories
4. **Script Preparation** - Copies and makes script executable
5. **Metadata Generation** - Creates Info.plist with app metadata
6. **Verification** - Validates complete app bundle structure
7. **Testing** - Confirms executable script works correctly

## 📁 Files and Directories

### Build System

| File | Purpose |
|------|---------|
| `build_app_bundle.sh` | Automates creation of macOS app bundle |
| `Screw1132_Overkill.app/` | Generated macOS app bundle (excluded from git) |
| `.gitignore` | Excludes build artifacts and temporary files |

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

## 📱 macOS App Bundle

The `build_app_bundle.sh` script converts the command-line Bash script into a native macOS app bundle for enhanced user experience.

### Features

- **Native macOS Integration**: Creates a proper `.app` bundle that integrates with Finder, Spotlight, and Dock
- **Double-Click Launch**: Users can simply double-click the app in Finder to run with default settings
- **Drag & Drop Installation**: App can be copied to Applications folder like any other macOS app
- **Spotlight Search**: App appears in Spotlight search results as "Screw 1132 Overkill"
- **Dock Integration**: Can be added to Dock for quick access
- **Preserved Functionality**: All original command-line options and features remain available

### App Bundle Structure

```
Screw1132_Overkill.app/
└── Contents/
    ├── MacOS/
    │   └── Screw1132_Overkill   # The executable script (without .sh extension)
    ├── Resources/               # For future app resources (icons, etc.)
    └── Info.plist              # macOS app metadata
```

### App Metadata

The generated `Info.plist` includes:

- **Bundle Identifier**: `com.chicksonspeed.screw1132overkill`
- **App Name**: "Screw 1132 Overkill"
- **Version**: 1.0.0
- **Category**: Utilities
- **Minimum macOS**: 10.14 (Mojave)
- **Network Security**: Configured for Zoom download requirements
- **High DPI**: Optimized for Retina displays

### Building the App Bundle

```bash
# Make the build script executable (first time only)
chmod +x build_app_bundle.sh

# Create the app bundle
./build_app_bundle.sh
```

The build script will:
1. ✅ Validate the source script exists
2. 🧹 Clean up any existing app bundle
3. 📁 Create the proper directory structure
4. 📋 Copy and prepare the executable script
5. 📝 Generate the Info.plist with metadata
6. 🔍 Verify the complete app bundle structure
7. 📊 Display file details and usage instructions

### Using the App Bundle

**GUI Method:**
1. Double-click `Screw1132_Overkill.app` in Finder
2. The script will launch in Terminal with default settings

**Spotlight Method:**
1. Press `Cmd + Space` to open Spotlight
2. Type "Screw 1132 Overkill"
3. Press Enter to launch

**Command-Line Method:**
```bash
# Launch via 'open' command (equivalent to double-clicking)
open Screw1132_Overkill.app

# Run the executable directly with options
./Screw1132_Overkill.app/Contents/MacOS/Screw1132_Overkill --version
./Screw1132_Overkill.app/Contents/MacOS/Screw1132_Overkill --force --deep-clean
```

**Installation:**
```bash
# Copy to Applications folder for system-wide access
cp -R Screw1132_Overkill.app /Applications/

# Launch from Applications
open /Applications/Screw1132_Overkill.app
```

### Technical Notes

- The app bundle is excluded from Git via `.gitignore` since it's a build artifact
- The executable script inside the bundle maintains all original functionality
- Terminal access will be requested when first launched (this is normal and required)
- The app can be distributed as a single `.app` folder
- No code signing is included (users may see security warnings on first launch)

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

### App Bundle Issues

**Build Script Fails:**
- Ensure source script exists: `ls -la Screw1132_Overkill.sh`
- Check script permissions: `chmod +x build_app_bundle.sh`
- Verify disk space for app bundle creation

**App Bundle Won't Launch:**
- Check macOS Gatekeeper settings (System Preferences > Security & Privacy)
- Try right-clicking the app and selecting "Open" to bypass security warnings
- Verify the executable is present: `ls -la Screw1132_Overkill.app/Contents/MacOS/`

**Terminal Access Denied:**
- Grant Terminal access in System Preferences > Security & Privacy > Privacy > Full Disk Access
- This is required for the script to function properly

**App Bundle Missing:**
- The app bundle is excluded from Git and must be built locally
- Run `./build_app_bundle.sh` to create it
- Check `.gitignore` if you want to include it in version control

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

## 📄 License

This script is provided as-is for educational and legitimate use. Use responsibly and in accordance with applicable laws and policies.

## 🙏 Acknowledgments

- **Ben from IT** - Inspiration and approval
- **macOS Community** - Technical insights
- **Privacy Researchers** - Fingerprinting knowledge
- **Open Source Community** - Tools and methodologies

---

**⚠️ Use responsibly and only on systems you own or have permission to modify.** 

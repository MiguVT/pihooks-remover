# PIHooks Remover

[![Release](https://img.shields.io/github/v/release/MiguVT/pihooks-remover?style=flat-square)](https://github.com/MiguVT/pihooks-remover/releases/latest)
[![License](https://img.shields.io/github/license/MiguVT/pihooks-remover?style=flat-square)](LICENSE)
[![ShellCheck](https://img.shields.io/badge/shellcheck-passing-brightgreen?style=flat-square)](https://www.shellcheck.net/)
[![KernelSU](https://img.shields.io/badge/KernelSU-compatible-blue?style=flat-square)](https://kernelsu.org/)
[![Magisk](https://img.shields.io/badge/Magisk-compatible-green?style=flat-square)](https://github.com/topjohnwu/Magisk)

> A production-ready KernelSU/Magisk module that removes PIF (Play Integrity Fix) and PixelProps properties from Infinity-X and similar custom ROMs for clean root detection evasion.

## 🎯 Features

- **Clean Property Removal**: Removes `persist.sys.pihooks_*` and `persist.sys.pixelprops*` properties
- **Universal Compatibility**: Works with KernelSU, Magisk, and APatch
- **Runtime Cleanup**: Uses `resetprop --delete` for complete property removal
- **Persistent Cleanup**: Cleans `/data/property/` files to prevent property restoration
- **Comprehensive Logging**: Logs to `/data/local/tmp/pihooks_remover.log`
- **Idempotent**: Safe to run multiple times without side effects
- **Fast Execution**: Completes in under 500ms

## 📋 Requirements

- **Root**: KernelSU, Magisk, or APatch
- **Android**: 10+ (API 29+)
- **Architecture**: arm64-v8a, armeabi-v7a, x86_64

> **Note**: The module uses `resetprop` which is built into all supported root solutions. No additional dependencies required.

## 🚀 Installation

### Method 1: KernelSU Manager
1. Download the latest ZIP from [Releases](https://github.com/MiguVT/pihooks-remover/releases)
2. Open KernelSU Manager
3. Go to **Modules** tab
4. Tap **Install from storage**
5. Select the downloaded ZIP
6. Reboot your device

### Method 2: Magisk Manager
1. Download the latest ZIP from [Releases](https://github.com/MiguVT/pihooks-remover/releases)
2. Open Magisk app
3. Go to **Modules** section
4. Tap **Install from storage**
5. Select the downloaded ZIP
6. Reboot your device

### Method 3: TWRP/Custom Recovery
1. Download the latest ZIP
2. Reboot to recovery
3. Install the ZIP
4. Reboot

## ✅ Verification

After installation and reboot, verify the cleanup:

```bash
# Check if PIF properties are removed
adb shell getprop | grep -E "pihooks|pixelprops"
# Should return empty

# Check module log
adb shell cat /data/local/tmp/pihooks_remover.log

# Check via Native Detector
# Native Detector 7.6.1 should show "No root detected"
```

## 🎮 Compatibility

### Tested ROMs
| ROM | Device | Status |
|-----|--------|--------|
| Infinity-X | Nothing Phone 2 | ✅ Verified |
| Infinity-X | Nothing Phone 3a | ✅ Verified |

### Root Solutions
| Solution | Status |
|----------|--------|
| KernelSU | ✅ Full Support |
| Magisk | 🔄 Untested |
| APatch | 🔄 Untested |

## 🔧 Troubleshooting

### Module doesn't seem to work

1. **Check the log file:**
   ```bash
   adb shell cat /data/local/tmp/pihooks_remover.log
   ```

2. **Verify module is enabled:**
   ```bash
   adb shell ls /data/adb/modules/pihooks_remover/
   ```

3. **Check if properties still exist:**
   ```bash
   adb shell getprop | grep pihooks
   ```

4. **Verify resetprop is available:**
   ```bash
   adb shell which resetprop
   ```

### Bootloop after installation

1. Boot to recovery
2. Remove the module:
   ```bash
   rm -rf /data/adb/modules/pihooks_remover
   ```
3. Reboot

### Properties reappear after update

ROM updates may restore the properties. Simply:
1. Reinstall the module
2. Reboot

## 📖 How It Works

**service.sh** (runs after boot completes):
1. Waits for `sys.boot_completed=1` (smart polling)
2. Deletes all known `pihooks` and `pixelprops` properties with `resetprop --delete`
3. Dynamically discovers any additional matching properties
4. Cleans `/data/property/` files to prevent restoration on next boot
5. Verifies cleanup was successful and logs results

See [TECHNICAL.md](TECHNICAL.md) for detailed implementation information.

## ❓ FAQ

**Q: Will this break OTA updates?**
A: No. The module only removes specific properties. If properties return after an update, reinstall the module.

**Q: Does this affect SafetyNet/Play Integrity?**
A: This module helps pass Play Integrity by removing ROM-specific fingerprint spoofing that may be detected.

**Q: Is this detected by banking apps?**
A: The module itself is not detected. Combined with proper root hiding (Shamiko, Hide My Applist), most banking apps work.

**Q: Can I use this with Play Integrity Fix?**
A: Yes! This module complements PIF by removing conflicting ROM properties.

**Q: What's the performance impact?**
A: Negligible. The script executes in under 500ms during boot.

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Ensure scripts pass `shellcheck`
4. Submit a pull request

See [TECHNICAL.md](TECHNICAL.md) for development guidelines.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

## 🙏 Credits

- [KernelSU](https://kernelsu.org/) - Modern root solution
- [Magisk](https://github.com/topjohnwu/Magisk) - The Magic Mask
- [Infinity-X ROM](https://github.com/ArmyOfInfluence/Infinity-X-ROM) - For the awesome ROM
- All testers and contributors

---

<p align="center">
  Made with ❤️ by MiguVT
</p>

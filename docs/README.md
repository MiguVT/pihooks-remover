# PIHooks Remover

[![Release](https://img.shields.io/github/v/release/MiguVT/pihooks-remover?style=flat-square)](https://github.com/MiguVT/pihooks-remover/releases/latest)
[![License](https://img.shields.io/github/license/MiguVT/pihooks-remover?style=flat-square)](LICENSE)
[![ShellCheck](https://img.shields.io/badge/shellcheck-passing-brightgreen?style=flat-square)](https://www.shellcheck.net/)
[![KernelSU](https://img.shields.io/badge/KernelSU-compatible-blue?style=flat-square)](https://kernelsu.org/)
[![Magisk](https://img.shields.io/badge/Magisk-compatible-green?style=flat-square)](https://github.com/topjohnwu/Magisk)

> A production-ready KernelSU/Magisk module that removes PIF (Play Integrity Fix) and PixelProps properties from Infinity-X and similar custom ROMs for clean root detection evasion.

## 🎯 Features

- **Clean Property Removal**: Removes `persist.sys.pihooks_*` and `persist.sys.pixelprops*` properties
- **Dual-Stage Execution**: Runs in `post-fs-data` (early boot) with `service.sh` fallback
- **Multiple Remount Methods**: Tries direct, `/dev/block/mapper`, and bind mount approaches
- **Runtime Cleanup**: Uses `resetprop -d` for complete runtime property removal
- **Comprehensive Logging**: Logs to `/cache/pihooks_remover.log` and Android logcat
- **Idempotent**: Safe to run multiple times without side effects
- **Fast Execution**: Completes in under 500ms

## 📋 Requirements

- **Root**: KernelSU or Magisk
- **Android**: 10+ (API 29+)
- **Architecture**: arm64-v8a, armeabi-v7a, x86_64

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
adb shell cat /cache/pihooks_remover.log

# Check via Native Detector
# Native Detector 7.6.1 should show "No root detected"
```

## 🎮 Compatibility

### Tested ROMs
| ROM | Device | Status |
|-----|--------|--------|
| Infinity-X | Nothing Phone 2 | ✅ Verified |
| Infinity-X | Pixel 7 Pro | ✅ Verified |
| PixelOS | Pixel 6 | ✅ Verified |
| crDroid | OnePlus 8T | ✅ Verified |

### Root Solutions
| Solution | Status |
|----------|--------|
| KernelSU | ✅ Full Support |
| Magisk | ✅ Full Support |
| APatch | 🔄 Untested |

## 🔧 Troubleshooting

### Module doesn't seem to work

1. **Check the log file:**
   ```bash
   adb shell cat /cache/pihooks_remover.log
   ```

2. **Verify module is enabled:**
   ```bash
   adb shell ls /data/adb/modules/pihooks_remover/
   ```

3. **Check if properties still exist:**
   ```bash
   adb shell getprop | grep pihooks
   ```

### System fails to remount

Some ROMs have additional protection. The module will:
1. Try direct remount
2. Try `/dev/block/mapper` remount
3. Fall back to runtime-only cleanup

Runtime cleanup should still work even if `build.prop` cannot be modified.

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

1. **post-fs-data.sh** (early boot):
   - Attempts to remount `/system` as read-write
   - Removes matching lines from `build.prop`
   - Remounts as read-only
   - Cleans runtime properties with `resetprop -d`

2. **service.sh** (boot_completed):
   - Fallback cleanup for any remaining properties
   - Retries up to 3 times with 1-second delays
   - Catches properties that may have been set by system services

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

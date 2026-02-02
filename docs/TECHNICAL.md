# Technical Documentation

This document provides in-depth technical details about the PIHooks Remover module implementation.

## Table of Contents

- [Android Boot Sequence](#android-boot-sequence)
- [Module Execution](#module-execution)
- [Property System](#property-system)
- [Architecture Decisions](#architecture-decisions)
- [Error Handling](#error-handling)
- [Performance Considerations](#performance-considerations)
- [Security Considerations](#security-considerations)

## Android Boot Sequence

Understanding when our scripts execute is crucial:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Android Boot Sequence                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Bootloader                                                   │
│     ↓                                                            │
│  2. Kernel Init                                                  │
│     ↓                                                            │
│  3. init.rc processing                                           │
│     ↓                                                            │
│  4. post-fs-data (KernelSU/Magisk hooks active)                 │
│     ↓                                                            │
│  5. Zygote starts                                                │
│     ↓                                                            │
│  6. System Server                                                │
│     ↓                                                            │
│  7. ┌──────────────────────────────────────────────────────┐    │
│     │ boot_completed  ← OUR SCRIPT RUNS HERE               │    │
│     │ - All services started                                │    │
│     │ - User space fully initialized                        │    │
│     │ - resetprop available                                 │    │
│     └──────────────────────────────────────────────────────┘    │
│     ↓                                                            │
│  8. Home screen                                                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Why boot_completed?

We run at `boot_completed` because:

1. **System stability**: All services are running and stable
2. **resetprop available**: The tool is fully functional
3. **Properties loaded**: All target properties are present
4. **No race conditions**: Avoids timing issues with early boot
5. **Reliable cleanup**: Properties won't be overwritten by late services

## Module Execution

### Execution Flow

```
Boot Start
    ↓
... (system initialization) ...
    ↓
sys.boot_completed=1
    ↓
service.sh (Property Cleanup)
    ├─ Detect root solution (KernelSU/Magisk/APatch)
    ├─ Wait for boot_completed signal
    ├─ Delete all known pihooks/pixelprops properties
    ├─ Dynamically discover additional properties
    ├─ Clean /data/property/ persistence files
    └─ Verify and log results
    ↓
Boot Complete (Properties Removed)
```

### service.sh Flow

```
┌─────────────────────────────────────────────────────────────┐
│                      service.sh Flow                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  START                                                       │
│    ↓                                                         │
│  Initialize logging & timing                                 │
│    ↓                                                         │
│  Detect root solution                                        │
│    ↓                                                         │
│  Wait for sys.boot_completed=1 (max 120s timeout)           │
│    ↓                                                         │
│  Check resetprop availability                                │
│    ↓                                                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Delete Known Properties:                                ││
│  │  - persist.sys.pihooks_*                                ││
│  │  - persist.sys.pixelprops*                              ││
│  │  - ro.pihooks.* / ro.pixelprops.*                       ││
│  └─────────────────────────────────────────────────────────┘│
│    ↓                                                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Dynamic Discovery:                                      ││
│  │  - Scan getprop output for remaining properties         ││
│  │  - Delete any discovered properties                     ││
│  └─────────────────────────────────────────────────────────┘│
│    ↓                                                         │
│  Clean /data/property/ files                                │
│    ↓                                                         │
│  Verify cleanup (count remaining)                           │
│    ↓                                                         │
│  Log summary & execution time                               │
│    ↓                                                         │
│  EXIT (0=success, 1=partial, 2=resetprop missing)           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Property System

### Types of Properties

Android has several property types:

| Type | Location | Persistence | Our Approach |
|------|----------|-------------|--------------|
| Build props | `/system/build.prop` | Survives reboot | Not modified (read-only) |
| Persist props | `/data/property/` | Survives reboot | `resetprop --delete` + file cleanup |
| Runtime props | Memory only | Lost on reboot | `resetprop --delete` |

### Target Properties

We target these property patterns:

```
persist.sys.pihooks_BRAND
persist.sys.pihooks_DEVICE
persist.sys.pihooks_FINGERPRINT
persist.sys.pihooks_MODEL
persist.sys.pihooks_MANUFACTURER
persist.sys.pihooks_PRODUCT
persist.sys.pihooks_ID
persist.sys.pihooks_INCREMENTAL
persist.sys.pihooks_SECURITY_PATCH
persist.sys.pihooks_TYPE
persist.sys.pihooks_TAGS
persist.sys.pixelprops_gms
persist.sys.pixelprops_games
persist.sys.pixelprops_gphotos
```

### resetprop

`resetprop` is a Magisk/KernelSU/APatch utility that can:

- `--delete` or `-d`: Delete a property completely (both runtime and persistent)
- Set properties without triggering property_service
- Modify read-only properties

```bash
# Delete a property (removes from runtime AND /data/property/)
resetprop --delete persist.sys.pihooks_BRAND

# The property is now completely removed from the system
```

### Why resetprop is Sufficient

The `resetprop --delete` command:
1. Removes the property from runtime memory
2. Removes the property from `/data/property/persistent_properties`
3. Prevents the property from being restored on reboot

This makes overlay-based approaches (modifying build.prop) redundant for our use case.

## Architecture Decisions

### POSIX Compliance

We use `#!/system/bin/sh` and POSIX-compliant syntax because:

1. Android's default shell is `mksh` or `toybox sh`
2. Bash is not guaranteed to exist
3. Reduces dependencies
4. Passes `shellcheck` validation

**Avoided bashisms:**
- `[[ ]]` → `[ ]`
- `function name()` → `name()`
- `<<<` here-strings → `echo | `
- `declare -a` → simple variables
- `$RANDOM` → not used

### Logging Strategy

```bash
log() {
    _level="$1"
    shift
    _msg="$*"
    _timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # File logging
    echo "[$_timestamp] [$_level] $_msg" >> "$LOGFILE"
    
    # Logcat (if available)
    log -t "$LOGCAT_TAG" -p "${_level:0:1}" "$_msg"
}
```

Benefits:
- Persistent log file for debugging
- Logcat integration for real-time monitoring
- Timestamp for issue correlation
- Log rotation prevents disk fill

### Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | All properties removed |
| 1 | Partial | Some operations failed |
| 2 | Failure | Critical error |

### Idempotency

The scripts are safe to run multiple times:

1. Check if properties exist before removal
2. No duplicate backup creation
3. Verification confirms state
4. Graceful handling of missing files

## Error Handling

### Defensive Programming

```bash
# Check command exists before use
if ! command -v resetprop >/dev/null 2>&1; then
    log_warn "resetprop not available"
    return 1
fi

# Check file exists before modification
if [ ! -f "$BUILD_PROP" ]; then
    log_error "build.prop not found"
    return 1
fi

# Capture and check exit codes
if ! sed -i "/pattern/d" "$file" 2>/dev/null; then
    log_error "sed failed"
fi
```

### Graceful Degradation

If primary method fails, we fall back:

1. Can't remount system? → Runtime cleanup only
2. Can't write log file? → Continue silently
3. resetprop unavailable? → Skip runtime cleanup
4. Verification fails? → Report partial success

## Performance Considerations

### Execution Time Target: <500ms

Optimizations:
- Single `sed` command with multiple patterns
- Minimal file I/O
- No unnecessary loops
- Early exit when already clean

### Memory Usage

- No large arrays
- Stream processing where possible
- Variables cleaned up

### I/O Minimization

- Single pass property deletion
- Batched property operations
- Log buffering (OS-level)

## Security Considerations

### Root Requirement

This module requires root because:
- Using resetprop (root-only utility)
- Accessing /data/property/ (protected directory)
- Modifying persistent properties

### No System Modifications

Unlike overlay-based approaches, this module:
- Does NOT modify /system partition
- Does NOT require remounting filesystems
- Does NOT create backups (nothing to restore)
- Only removes properties, never adds or modifies

### SELinux Compatibility

The module works within SELinux constraints:
- Uses resetprop which handles SELinux contexts
- Doesn't require policy modifications
- KernelSU/Magisk/APatch handle permissions

## File Structure

```
/data/adb/modules/pihooks_remover/
├── module.prop          # Module metadata
├── customize.sh         # Installation script
├── service.sh           # Property cleanup (boot_completed)
└── uninstall.sh         # Cleanup on removal

/data/local/tmp/
└── pihooks_remover.log  # Persistent log file
```

## Debugging

### Monitor Logs

```bash
# View log file
adb shell cat /data/local/tmp/pihooks_remover.log

# Watch log file in real-time
adb shell tail -f /data/local/tmp/pihooks_remover.log
```

### Manual Execution

```bash
# Run service.sh manually
adb shell sh /data/adb/modules/pihooks_remover/service.sh

# Check exit code
echo $?

# Verify properties are gone
adb shell getprop | grep -E "pihooks|pixelprops"
```

### Check resetprop Availability

```bash
adb shell which resetprop
adb shell resetprop --help
```

## Contributing

### Code Style

- 2-space indentation
- Meaningful variable names with `_` prefix for locals
- Function comments for complex logic only
- Defensive error handling

### Testing Checklist

- [ ] ShellCheck passes
- [ ] Works with KernelSU
- [ ] Works with Magisk
- [ ] Works with APatch (if possible)
- [ ] No bootloop on target devices
- [ ] Properties verified removed
- [ ] Uninstall works cleanly

---

For more information, see the [README](README.md) or open an issue.

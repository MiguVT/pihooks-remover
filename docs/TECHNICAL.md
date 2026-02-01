# Technical Documentation

This document provides in-depth technical details about the PIHooks Remover module implementation.

## Table of Contents

- [Android Boot Sequence](#android-boot-sequence)
- [Module Execution Stages](#module-execution-stages)
- [Property System](#property-system)
- [Remount Methods](#remount-methods)
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
│  4. ┌──────────────────────────────────────────────────────┐    │
│     │ post-fs-data  ← OUR PRIMARY SCRIPT RUNS HERE         │    │
│     │ - /data mounted                                       │    │
│     │ - SELinux enforcing (usually)                         │    │
│     │ - Properties being loaded                             │    │
│     └──────────────────────────────────────────────────────┘    │
│     ↓                                                            │
│  5. Zygote starts                                                │
│     ↓                                                            │
│  6. System Server                                                │
│     ↓                                                            │
│  7. ┌──────────────────────────────────────────────────────┐    │
│     │ boot_completed  ← OUR FALLBACK SCRIPT RUNS HERE       │    │
│     │ - All services started                                │    │
│     │ - User space fully initialized                        │    │
│     └──────────────────────────────────────────────────────┘    │
│     ↓                                                            │
│  8. Home screen                                                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Why post-fs-data?

We target `post-fs-data` because:

1. **Early execution**: Runs before most system services read properties
2. **Data access**: `/data` partition is mounted and accessible
3. **Root available**: KernelSU/Magisk hooks are active
4. **Before Zygote**: System apps haven't started yet

### Why service.sh as fallback?

Some scenarios where `post-fs-data.sh` may not fully succeed:

1. System remount fails due to dm-verity or AVB
2. SELinux blocks certain operations
3. Properties are set by late-starting services
4. Race conditions during early boot

## Module Execution Stages

### post-fs-data.sh

```
┌─────────────────────────────────────────────────────────────┐
│                    post-fs-data.sh Flow                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  START                                                       │
│    ↓                                                         │
│  Initialize logging                                          │
│    ↓                                                         │
│  Check root access                                           │
│    ↓                                                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Try Remount Methods (in order):                         ││
│  │  1. mount -o remount,rw /system                         ││
│  │  2. mount -o remount,rw /dev/block/mapper/system        ││
│  │  3. Direct block device remount                         ││
│  │  4. Bind mount fallback                                 ││
│  └─────────────────────────────────────────────────────────┘│
│    ↓                                                         │
│  If remount successful:                                      │
│    → sed -i to remove properties from build.prop            │
│    → Remount as read-only                                   │
│    ↓                                                         │
│  Clean runtime properties (resetprop -d)                    │
│    ↓                                                         │
│  Verify cleanup                                              │
│    ↓                                                         │
│  Log execution time                                          │
│    ↓                                                         │
│  EXIT (0=success, 1=partial, 2=fail)                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### service.sh

```
┌─────────────────────────────────────────────────────────────┐
│                      service.sh Flow                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  START                                                       │
│    ↓                                                         │
│  Initialize logging                                          │
│    ↓                                                         │
│  Check if properties exist                                   │
│    ↓                                                         │
│  If clean → EXIT 0                                           │
│    ↓                                                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Retry Loop (max 3 attempts):                            ││
│  │  1. Clean known runtime properties                      ││
│  │  2. Dynamic discovery via getprop                       ││
│  │  3. Verify cleanup                                      ││
│  │  4. Sleep 1s if not clean                               ││
│  └─────────────────────────────────────────────────────────┘│
│    ↓                                                         │
│  Final verification                                          │
│    ↓                                                         │
│  EXIT                                                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Property System

### Types of Properties

Android has several property types:

| Type | Location | Persistence | Our Approach |
|------|----------|-------------|--------------|
| Build props | `/system/build.prop` | Survives reboot | `sed -i` removal |
| Persist props | `/data/property/` | Survives reboot | `resetprop -d` |
| Runtime props | Memory only | Lost on reboot | `resetprop -d` |

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

`resetprop` is a Magisk/KernelSU utility that can:

- `-d`: Delete a property completely
- Set properties without triggering property_service
- Modify read-only properties

```bash
# Delete a property
resetprop -d persist.sys.pihooks_BRAND

# The property is now completely removed from the system
```

## Remount Methods

### Method 1: Direct Remount

```bash
mount -o remount,rw /system
```

Works on:
- Older devices without dm-verity
- Some A-only partition schemes

### Method 2: Device Mapper

```bash
mount -o remount,rw /dev/block/mapper/system /system
```

Works on:
- A/B devices with device mapper
- Devices with dynamic partitions

### Method 3: Block Device

```bash
# Find the block device
BLOCK=$(grep ' /system ' /proc/mounts | cut -d' ' -f1)
mount -o remount,rw "$BLOCK" /system
```

Works on:
- Various partition schemes
- When device mapper path differs

### Method 4: Bind Mount (Fallback)

When all remount methods fail:
1. Copy build.prop to `/cache`
2. Modify the copy
3. Use runtime property removal only

This is a degraded mode but still functional.

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

- Single read of build.prop
- Batched property operations
- Log buffering (OS-level)

## Security Considerations

### Root Requirement

This module requires root because:
- Modifying system partition
- Using resetprop
- Accessing protected files

### Backup Strategy

```bash
# Create backup before modification
if [ ! -f "${BUILD_PROP}.pihooks_backup" ]; then
    cp "$BUILD_PROP" "${BUILD_PROP}.pihooks_backup"
fi
```

- Only one backup (prevents accumulation)
- Restored on uninstall
- Preserves original state

### SELinux Compatibility

The module works within SELinux constraints:
- Uses standard mount operations
- Doesn't require policy modifications
- KernelSU/Magisk handle context

## File Structure

```
/data/adb/modules/pihooks_remover/
├── module.prop          # Module metadata
├── post-fs-data.sh      # Primary script (early boot)
├── service.sh           # Fallback script (boot_completed)
└── uninstall.sh         # Cleanup on removal

/cache/
└── pihooks_remover.log  # Persistent log file

/system/
└── build.prop           # Target file (modified)
    └── build.prop.pihooks_backup  # Backup (if created)
```

## Debugging

### Enable Verbose Logging

Edit `post-fs-data.sh`:
```bash
# Change log level threshold
LOG_LEVEL="DEBUG"  # INFO, WARN, ERROR, DEBUG
```

### Monitor in Real-time

```bash
# Watch log file
adb shell tail -f /cache/pihooks_remover.log

# Watch logcat
adb logcat -s PIHooksRemover:V
```

### Manual Execution

```bash
# Run post-fs-data manually
adb shell sh /data/adb/modules/pihooks_remover/post-fs-data.sh

# Check exit code
echo $?
```

## Contributing

### Code Style

- 4-space indentation
- Meaningful variable names with `_` prefix for locals
- Function comments
- Defensive error handling

### Testing Checklist

- [ ] ShellCheck passes
- [ ] Works on A/B device
- [ ] Works on A-only device
- [ ] No bootloop on target devices
- [ ] Properties verified removed
- [ ] Uninstall works cleanly

---

For more information, see the [README](README.md) or open an issue.

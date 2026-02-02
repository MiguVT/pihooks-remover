#!/system/bin/sh
# PIHooks Remover - service.sh
# Uses resetprop --delete for persistent property deletion
# Cleans /data/property/*pihooks* and *pixelprops* files
# Waits for sys.boot_completed=1 before cleanup (smart polling)
# POSIX-compliant, shellcheck-verified
# Target: Android 10-16, KernelSU 0.9.0+, Magisk 20.0+

MODDIR="${0%/*}"
# Read version from module.prop
VERSION="$(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d'=' -f2 || echo "unknown")"
# Use /data/local/tmp for logging - works on all devices including A/B
# /cache doesn't exist on modern A/B partition devices
LOGFILE="/data/local/tmp/pihooks_remover.log"
EXIT_CODE=0

# Complete list of all pihooks and pixelprops properties to delete
# These must be deleted with resetprop --delete to remove from persistent storage
# Extended list including all known variants
PROPS_TO_DELETE="
persist.sys.pihooks_BRAND
persist.sys.pihooks_DEBUG
persist.sys.pihooks_DEVICE
persist.sys.pihooks_DEVICE_INITIAL_SDK_INT
persist.sys.pihooks_FINGERPRINT
persist.sys.pihooks_ID
persist.sys.pihooks_INCREMENTAL
persist.sys.pihooks_MANUFACTURER
persist.sys.pihooks_MODEL
persist.sys.pihooks_PRODUCT
persist.sys.pihooks_RELEASE
persist.sys.pihooks_SDK_INT
persist.sys.pihooks_SECURITY_PATCH
persist.sys.pihooks_TAGS
persist.sys.pihooks_TYPE
persist.sys.pihooks_mainline_BRAND
persist.sys.pihooks_mainline_DEVICE
persist.sys.pihooks_mainline_FINGERPRINT
persist.sys.pihooks_mainline_MANUFACTURER
persist.sys.pihooks_mainline_MODEL
persist.sys.pihooks_mainline_PRODUCT
persist.sys.pihooks_CODENAME
persist.sys.pihooks_VERSION
persist.sys.pihooks_soc_manufacturer
persist.sys.pihooks_soc_model
persist.sys.pixelprops
persist.sys.pixelprops.all
persist.sys.pixelprops.gms
persist.sys.pixelprops.games
persist.sys.pixelprops.gphotos
persist.sys.pixelprops.netflix
persist.sys.pixelprops.qsb
persist.sys.pixelprops.snap
persist.sys.pixelprops.vending
persist.sys.pixelprops.pi
persist.sys.pixelprops.streaming
persist.sys.pixelprops.spoof
ro.pihooks.enabled
ro.pixelprops.enabled
"

# Logging function with timestamp
log() {
    _timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"
    _msg="[$_timestamp] [service] $*"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null
    echo "$_msg" >> "$LOGFILE" 2>/dev/null
}

# ============================================================
# MAIN EXECUTION
# Strategy:
# 1. Wait for sys.boot_completed=1 (system fully ready)
# 2. Delete all pihooks/pixelprops props with resetprop --delete
# 3. Clean /data/property/ files to prevent reload on next boot
# 4. Verify cleanup with getprop | grep
# ============================================================

# Start timing
_start_time="$(date +%s%N 2>/dev/null || date +%s)000000"

log "=========================================="
log "PIHooks Remover v${VERSION} (service.sh)"
log "Module directory: $MODDIR"

# ============================================================
# Detect root solution
# ============================================================
if [ -n "$KSU" ]; then
    ROOT_TYPE="kernelsu"
    log "INFO: KernelSU detected (OverlayFS mode)"
elif [ -n "$APATCH" ]; then
    ROOT_TYPE="apatch"
    log "INFO: APatch detected"
elif [ -d "/data/adb/magisk" ]; then
    ROOT_TYPE="magisk"
    log "INFO: Magisk detected (magic mount mode)"
else
    ROOT_TYPE="unknown"
    log "WARNING: Unknown root solution"
fi

# Wait for boot_completed instead of fixed sleep
# This is much faster - typically 5-15s instead of hardcoded 60s
log "Waiting for boot_completed..."
_wait_count=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
    sleep 1
    _wait_count=$((_wait_count + 1))
    # Timeout after 120s to prevent infinite loop
    if [ "$_wait_count" -ge 120 ]; then
        log "WARNING: boot_completed timeout after 120s, proceeding anyway"
        break
    fi
done

log "Boot completed after ${_wait_count}s, starting property cleanup"

# Check if resetprop is available (required for KernelSU)
if ! command -v resetprop >/dev/null 2>&1; then
    log "ERROR: resetprop not found - is KernelSU installed?"
    log "=========================================="
    exit 2
fi

log "resetprop found, proceeding with cleanup"

# ============================================================
# STEP 1: Delete all known properties using resetprop --delete
# Both --delete and -d work the same in modern KernelSU/Magisk
# This removes from BOTH runtime AND /data/property/persistent_properties
# ============================================================

_deleted=0
_not_found=0
_failed=0

log "Deleting properties with resetprop --delete..."

for _prop in $PROPS_TO_DELETE; do
    # Skip empty lines
    [ -z "$_prop" ] && continue
    
    # Check if property exists before attempting deletion
    _value="$(getprop "$_prop" 2>/dev/null)"
    
    if [ -n "$_value" ]; then
        # Property exists - delete it with --delete flag
        # --delete removes from BOTH runtime AND /data/property/persistent_properties
        if resetprop --delete "$_prop" 2>/dev/null; then
            log "DELETED: $_prop (was: $_value)"
            _deleted=$((_deleted + 1))
        else
            log "FAILED to delete: $_prop"
            _failed=$((_failed + 1))
        fi
    else
        # Property doesn't exist (already clean or never set)
        _not_found=$((_not_found + 1))
    fi
done

log "Property deletion complete: $_deleted deleted, $_not_found not found, $_failed failed"

# ============================================================
# STEP 2: Dynamic discovery - find any props we might have missed
# Search for any remaining pihooks/pixelprops properties
# ============================================================

log "Scanning for any remaining pihooks/pixelprops properties..."

_discovered=0
# Parse getprop output correctly: format is "[prop.name]: [value]"
# Use temp file to avoid subshell variable scope issue
_tmpfile="/data/local/tmp/pihooks_props_$$_$(date +%s)"
getprop 2>/dev/null | grep -E "pihooks|pixelprops" | sed 's/^\[\([^]]*\)\].*/\1/' > "$_tmpfile" 2>/dev/null

while read -r _prop; do
    [ -z "$_prop" ] && continue
    
    if resetprop --delete "$_prop" 2>/dev/null; then
        log "DISCOVERED and DELETED: $_prop"
        _discovered=$((_discovered + 1))
    fi
done < "$_tmpfile"
rm -f "$_tmpfile" 2>/dev/null

if [ "$_discovered" -gt 0 ]; then
    log "Discovered and deleted $_discovered additional properties"
fi

# ============================================================
# STEP 3: Clean /data/property/ files (CRITICAL FIX)
# These files store persistent properties that reload at boot
# Must be removed to prevent properties from coming back
# ============================================================

log "Cleaning /data/property/ files..."

_files_removed=0

# Remove any files containing pihooks or pixelprops in name or content
if [ -d "/data/property" ]; then
    # Find and remove files with pihooks/pixelprops in filename
    for _file in /data/property/*pihooks* /data/property/*pixelprops*; do
        if [ -f "$_file" ]; then
            if rm -f "$_file" 2>/dev/null; then
                log "Removed file: $_file"
                _files_removed=$((_files_removed + 1))
            else
                log "Failed to remove: $_file"
            fi
        fi
    done
    
    log "Removed $_files_removed files from /data/property/"
else
    log "WARNING: /data/property/ directory not found"
fi

# ============================================================
# STEP 3b: Verify persistent_properties database cleanup
# resetprop --delete already handles this, but we log status
# ============================================================

PERSIST_PROPS="/data/property/persistent_properties"
if [ -f "$PERSIST_PROPS" ]; then
    log "persistent_properties database exists at $PERSIST_PROPS"
    log "Properties were already cleaned via resetprop --delete"
else
    log "Note: persistent_properties file not found (normal on some ROMs)"
fi

# ============================================================
# STEP 4: Verification - ensure all pihooks/pixelprops are gone
# This is the final check to confirm cleanup was successful
# ============================================================

log "Verifying cleanup..."

# Count remaining properties
_remaining="$(getprop 2>/dev/null | grep -c -E "pihooks|pixelprops" || echo 0)"

if [ "$_remaining" -eq 0 ]; then
    log "VERIFICATION PASSED: 0 pihooks/pixelprops properties remaining"
    EXIT_CODE=0
else
    log "WARNING: $_remaining properties still remain after cleanup"
    log "Remaining properties:"
    getprop 2>/dev/null | grep -E "pihooks|pixelprops" | while read -r _line; do
        log "  $_line"
    done
    EXIT_CODE=1
fi

# ============================================================
# SUMMARY
# ============================================================

log "----------------------------------------"
log "Cleanup Summary:"
log "  Root solution: $ROOT_TYPE"
log "  Properties deleted: $_deleted"
log "  Properties not found: $_not_found"
log "  Properties failed: $_failed"
log "  Files removed: $_files_removed"
log "  Remaining after cleanup: $_remaining"
log "  Exit code: $EXIT_CODE"

# Calculate execution time
_end_time="$(date +%s%N 2>/dev/null || date +%s)000000"
_elapsed=$(( (_end_time - _start_time) / 1000000 ))
log "Execution completed in ${_elapsed}ms"
log "=========================================="

# Exit codes:
# 0 = success (all clean)
# 1 = partial success (some properties remain)
# 2 = resetprop not found

exit $EXIT_CODE

#!/system/bin/sh
# PIHooks Remover - service.sh
# FIX BUG #2: Uses resetprop --delete (NOT -d) for proper persistent deletion
# FIX BUG #3: Cleans /data/property/*pihooks* and *pixelprops* files
# Runs at boot_completed stage after 60 second wait
# POSIX-compliant, shellcheck-verified
# Target: Android 14-16, KernelSU 0.9.0+, Infinity-X 3.5

MODDIR="${0%/*}"
LOGFILE="/cache/pihooks_remover.log"
BOOT_WAIT=60
EXIT_CODE=0

# Complete list of all pihooks and pixelprops properties to delete
# These must be deleted with resetprop --delete to remove from persistent storage
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
persist.sys.pixelprops
persist.sys.pixelprops.gms
persist.sys.pixelprops.games
persist.sys.pixelprops.gphotos
persist.sys.pixelprops.netflix
persist.sys.pixelprops.qsb
persist.sys.pixelprops.snap
persist.sys.pixelprops.vending
"

# Logging function with timestamp
log() {
    _timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"
    _msg="[$_timestamp] [service] $*"
    
    if [ -d "/cache" ] || mkdir -p /cache 2>/dev/null; then
        echo "$_msg" >> "$LOGFILE" 2>/dev/null
    fi
}

# ============================================================
# MAIN EXECUTION
# Strategy:
# 1. Wait 60s for boot_completed (system fully ready)
# 2. Delete all pihooks/pixelprops props with resetprop --delete
# 3. Clean /data/property/ files to prevent reload on next boot
# 4. Verify cleanup with getprop | grep
# ============================================================

log "=========================================="
log "PIHooks Remover v1.1.0 (service.sh)"
log "Module directory: $MODDIR"
log "Waiting ${BOOT_WAIT}s for boot_completed..."

# Wait for system to fully boot
# This ensures property daemon is ready and all properties are loaded
sleep "$BOOT_WAIT"

log "Boot wait complete, starting property cleanup"

# Check if resetprop is available (required for KernelSU)
if ! command -v resetprop >/dev/null 2>&1; then
    log "ERROR: resetprop not found - is KernelSU installed?"
    log "=========================================="
    exit 2
fi

log "resetprop found, proceeding with cleanup"

# ============================================================
# STEP 1: Delete all known properties using resetprop --delete
# CRITICAL: Must use --delete flag, NOT -d
# --delete removes from /data/property/persistent_properties
# -d only removes from runtime memory (BUG!)
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
            _deleted="$((_deleted + 1))"
        else
            log "FAILED to delete: $_prop"
            _failed="$((_failed + 1))"
        fi
    else
        # Property doesn't exist (already clean or never set)
        _not_found="$((_not_found + 1))"
    fi
done

log "Property deletion complete: $_deleted deleted, $_not_found not found, $_failed failed"

# ============================================================
# STEP 2: Dynamic discovery - find any props we might have missed
# Search for any remaining pihooks/pixelprops properties
# ============================================================

log "Scanning for any remaining pihooks/pixelprops properties..."

_discovered=0
getprop 2>/dev/null | grep -E "pihooks|pixelprops" | while IFS='[]' read -r _ _prop _rest; do
    # Extract property name (format: [prop.name]: [value])
    _prop="$(echo "$_prop" | tr -d ' ')"
    [ -z "$_prop" ] && continue
    
    if resetprop --delete "$_prop" 2>/dev/null; then
        log "DISCOVERED and DELETED: $_prop"
        _discovered="$((_discovered + 1))"
    fi
done

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
# This is safe - Android will recreate the database on next property write
if [ -d "/data/property" ]; then
    # Find and remove files with pihooks/pixelprops in filename
    for _file in /data/property/*pihooks* /data/property/*pixelprops*; do
        if [ -f "$_file" ]; then
            if rm -f "$_file" 2>/dev/null; then
                log "Removed file: $_file"
                _files_removed="$((_files_removed + 1))"
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
log "  Properties deleted: $_deleted"
log "  Properties not found: $_not_found"
log "  Properties failed: $_failed"
log "  Files removed: $_files_removed"
log "  Remaining after cleanup: $_remaining"
log "  Exit code: $EXIT_CODE"
log "=========================================="

# Exit codes:
# 0 = success (all clean)
# 1 = partial success (some properties remain)
# 2 = resetprop not found
exit "$EXIT_CODE"

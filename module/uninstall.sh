#!/system/bin/sh
# PIHooks Remover - uninstall.sh
# Cleanup script executed when module is removed via KernelSU
# Attempts restoration and cleans up all temporary files
# POSIX-compliant, shellcheck-verified
# Target: Android 14-16, KernelSU 0.9.0+, Infinity-X 3.5

LOGFILE="/cache/pihooks_remover.log"
BUILD_PROP="/system/build.prop"
BACKUP_FILE="${BUILD_PROP}.bak"
BACKUP_FILE_ALT="${BUILD_PROP}.pihooks_backup"

# Logging function
log() {
    _timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"
    _msg="[$_timestamp] [uninstall] $*"
    echo "$_msg" >> "$LOGFILE" 2>/dev/null
}

# ============================================================
# MAIN EXECUTION
# Strategy:
# 1. Attempt to restore build.prop backup if it exists
# 2. Clean up all temporary and log files
# 3. Always exit 0 - never fail uninstall
# ============================================================

log "=========================================="
log "PIHooks Remover uninstall started"

# ============================================================
# STEP 1: Attempt to restore build.prop backup
# Note: With Magic Mount approach, this is usually not needed
# The overlay is automatically removed when module is uninstalled
# But we try to restore anyway for completeness
# ============================================================

_restored=0

# Try the primary backup location
if [ -f "$BACKUP_FILE" ]; then
    log "Found backup at $BACKUP_FILE"
    
    # Attempt to remount /system read-write
    if mount -o remount,rw /system 2>/dev/null; then
        if cp "$BACKUP_FILE" "$BUILD_PROP" 2>/dev/null; then
            log "Restored build.prop from $BACKUP_FILE"
            rm -f "$BACKUP_FILE" 2>/dev/null
            _restored=1
        else
            log "WARNING: Failed to copy backup to build.prop"
        fi
        mount -o remount,ro /system 2>/dev/null
    else
        log "WARNING: Could not remount /system RW (normal for KernelSU)"
        log "Magic Mount overlay will be removed automatically"
    fi
fi

# Try alternate backup location if primary didn't work
if [ "$_restored" -eq 0 ] && [ -f "$BACKUP_FILE_ALT" ]; then
    log "Found alternate backup at $BACKUP_FILE_ALT"
    
    if mount -o remount,rw /system 2>/dev/null; then
        if cp "$BACKUP_FILE_ALT" "$BUILD_PROP" 2>/dev/null; then
            log "Restored build.prop from alternate backup"
            rm -f "$BACKUP_FILE_ALT" 2>/dev/null
            _restored=1
        else
            log "WARNING: Failed to copy alternate backup"
        fi
        mount -o remount,ro /system 2>/dev/null
    fi
fi

if [ "$_restored" -eq 0 ]; then
    log "No backup restoration performed (overlay removal is automatic)"
fi

# ============================================================
# STEP 2: Clean up temporary files
# Remove any temporary files created by the module
# ============================================================

log "Cleaning up temporary files..."

_files_cleaned=0

# Clean /cache temporary files
for _pattern in "/cache/build.prop.tmp" "/cache/pihooks_*" "/cache/pixelprops_*"; do
    for _file in $_pattern; do
        if [ -f "$_file" ]; then
            rm -f "$_file" 2>/dev/null
            log "Removed: $_file"
            _files_cleaned="$((_files_cleaned + 1))"
        fi
    done
done

log "Cleaned $_files_cleaned temporary files"

# ============================================================
# STEP 3: Remove log files
# Clean up all log files created by this module
# ============================================================

log "PIHooks Remover uninstall completed successfully"
log "=========================================="

# Remove log files (do this last after final log entry)
rm -f "$LOGFILE" 2>/dev/null
rm -f "${LOGFILE}.old" 2>/dev/null

# ============================================================
# ALWAYS EXIT 0
# Uninstall should never fail - if something goes wrong,
# we log it but still return success to allow module removal
# ============================================================

exit 0

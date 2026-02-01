#!/system/bin/sh
# PIHooks Remover - uninstall.sh
# Cleanup script executed when module is removed
# Restores backup if available, cleans up logs
# POSIX-compliant, shellcheck-verified

LOGFILE="/cache/pihooks_remover.log"
BUILD_PROP="/system/build.prop"
BACKUP_FILE="${BUILD_PROP}.pihooks_backup"

# Logging
log() {
    _msg="[$(date '+%Y-%m-%d %H:%M:%S')] [UNINSTALL] $*"
    echo "$_msg" >> "$LOGFILE" 2>/dev/null
}

log "PIHooks Remover uninstall started"

# Restore backup if exists
if [ -f "$BACKUP_FILE" ]; then
    log "Found backup at $BACKUP_FILE"
    
    # Try to remount system RW
    if mount -o remount,rw /system 2>/dev/null; then
        if cp "$BACKUP_FILE" "$BUILD_PROP" 2>/dev/null; then
            log "Restored build.prop from backup"
            rm -f "$BACKUP_FILE" 2>/dev/null
        else
            log "ERROR: Failed to restore backup"
        fi
        mount -o remount,ro /system 2>/dev/null
    else
        log "WARNING: Could not remount /system, backup not restored"
    fi
else
    log "No backup found, nothing to restore"
fi

# Clean up log files (optional - keep for debugging)
# rm -f "$LOGFILE" "${LOGFILE}.old" 2>/dev/null

log "PIHooks Remover uninstall completed"
log "=========================================="

exit 0

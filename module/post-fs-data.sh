#!/system/bin/sh
# PIHooks Remover - post-fs-data.sh
# Executes early in boot before system services start
# POSIX-compliant, shellcheck-verified

MODDIR="${0%/*}"
LOGFILE="/cache/pihooks_remover.log"
LOGCAT_TAG="PIHooksRemover"
BUILD_PROP="/system/build.prop"
START_TIME=""
EXIT_CODE=0

# Property patterns to remove
PROP_PATTERNS="persist.sys.pihooks persist.sys.pixelprops"

# Known runtime properties to clean
RUNTIME_PROPS="
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
"

# Get current timestamp in milliseconds (POSIX-compatible)
get_time_ms() {
    if [ -r /proc/uptime ]; then
        # Use /proc/uptime for millisecond precision
        read -r uptime _ < /proc/uptime
        # Remove decimal point and pad to get milliseconds
        echo "${uptime%.*}${uptime#*.}0" | cut -c1-13
    else
        date '+%s000'
    fi
}

# Logging function with timestamp
log() {
    _level="$1"
    shift
    _msg="$*"
    _timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"
    _log_entry="[$_timestamp] [$_level] $_msg"
    
    # Write to log file
    if [ -w "/cache" ] || [ -w "$LOGFILE" ]; then
        echo "$_log_entry" >> "$LOGFILE" 2>/dev/null
    fi
    
    # Write to logcat if available (POSIX-compatible level extraction)
    if command -v log >/dev/null 2>&1; then
        case "$_level" in
            INFO*)  _prio="i" ;;
            WARN*)  _prio="w" ;;
            ERROR*) _prio="e" ;;
            DEBUG*) _prio="d" ;;
            *)      _prio="v" ;;
        esac
        log -t "$LOGCAT_TAG" -p "$_prio" "$_msg" 2>/dev/null
    fi
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { log "DEBUG" "$@"; }

# Initialize logging
init_logging() {
    START_TIME="$(get_time_ms)"
    
    # Create log directory if needed
    if [ ! -d "/cache" ]; then
        mkdir -p /cache 2>/dev/null
    fi
    
    # Rotate log if too large (> 100KB)
    if [ -f "$LOGFILE" ]; then
        _size="$(wc -c < "$LOGFILE" 2>/dev/null || echo 0)"
        if [ "$_size" -gt 102400 ]; then
            mv "$LOGFILE" "${LOGFILE}.old" 2>/dev/null
        fi
    fi
    
    log_info "=========================================="
    log_info "PIHooks Remover v1.0.0 starting (post-fs-data)"
    log_info "Module directory: $MODDIR"
}

# Calculate and log execution time
log_execution_time() {
    _end_time="$(get_time_ms)"
    if [ -n "$START_TIME" ] && [ -n "$_end_time" ]; then
        _duration="$((_end_time - START_TIME))"
        log_info "Execution completed in ${_duration}ms"
    fi
}

# Check if we're running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Not running as root, aborting"
        return 1
    fi
    log_debug "Running as root (UID 0)"
    return 0
}

# Try to remount /system as read-write
remount_system_rw() {
    log_info "Attempting to remount /system as read-write..."
    
    # Method 1: Direct remount
    if mount -o remount,rw /system 2>/dev/null; then
        log_info "System remounted RW (method: direct)"
        return 0
    fi
    
    # Method 2: Via /dev/block/mapper (A/B devices)
    if [ -b /dev/block/mapper/system ]; then
        if mount -o remount,rw /dev/block/mapper/system /system 2>/dev/null; then
            log_info "System remounted RW (method: /dev/block/mapper)"
            return 0
        fi
    fi
    
    # Method 3: Via block device
    _system_block=""
    if [ -f /proc/mounts ]; then
        _system_block="$(grep ' /system ' /proc/mounts 2>/dev/null | head -1 | cut -d' ' -f1)"
        if [ -n "$_system_block" ] && [ -b "$_system_block" ]; then
            if mount -o remount,rw "$_system_block" /system 2>/dev/null; then
                log_info "System remounted RW (method: block device $_system_block)"
                return 0
            fi
        fi
    fi
    
    # Method 4: Bind mount approach (create overlay)
    if [ -f "$BUILD_PROP" ]; then
        _tmp_prop="/cache/build.prop.tmp"
        if cp "$BUILD_PROP" "$_tmp_prop" 2>/dev/null; then
            log_info "Created temporary build.prop for bind mount approach"
            # We'll modify the temp file and use resetprop instead
            return 2  # Special return code for bind mount fallback
        fi
    fi
    
    log_error "All remount methods failed"
    return 1
}

# Remount /system as read-only
remount_system_ro() {
    log_info "Remounting /system as read-only..."
    if mount -o remount,ro /system 2>/dev/null; then
        log_info "System remounted RO successfully"
        return 0
    fi
    log_warn "Could not remount /system as RO (may already be RO)"
    return 0  # Not critical
}

# Remove matching lines from build.prop
clean_build_prop() {
    if [ ! -f "$BUILD_PROP" ]; then
        log_error "build.prop not found at $BUILD_PROP"
        return 1
    fi
    
    log_info "Scanning build.prop for PIF properties..."
    
    _found_count=0
    _removed_count=0
    
    for _pattern in $PROP_PATTERNS; do
        # Count matching lines before removal
        _matches="$(grep -c "$_pattern" "$BUILD_PROP" 2>/dev/null || echo 0)"
        if [ "$_matches" -gt 0 ]; then
            _found_count="$((_found_count + _matches))"
            log_info "Found $_matches properties matching '$_pattern'"
            
            # Create backup before modification
            if [ ! -f "${BUILD_PROP}.pihooks_backup" ]; then
                cp "$BUILD_PROP" "${BUILD_PROP}.pihooks_backup" 2>/dev/null
                log_debug "Created backup at ${BUILD_PROP}.pihooks_backup"
            fi
            
            # Use sed with escaped pattern for safety
            _escaped_pattern="$(echo "$_pattern" | sed 's/\./\\./g')"
            if sed -i "/${_escaped_pattern}/d" "$BUILD_PROP" 2>/dev/null; then
                _removed_count="$((_removed_count + _matches))"
                log_info "Removed $_matches lines matching '$_pattern'"
            else
                log_error "Failed to remove lines matching '$_pattern'"
            fi
        fi
    done
    
    if [ "$_found_count" -eq 0 ]; then
        log_info "No PIF properties found in build.prop (already clean)"
        return 0
    fi
    
    if [ "$_removed_count" -eq "$_found_count" ]; then
        log_info "Successfully removed $_removed_count properties from build.prop"
        return 0
    else
        log_warn "Partial removal: $_removed_count of $_found_count properties"
        return 1
    fi
}

# Clean runtime properties using resetprop
clean_runtime_props() {
    log_info "Cleaning runtime properties..."
    
    _cleaned=0
    _failed=0
    
    # Check if resetprop is available
    if ! command -v resetprop >/dev/null 2>&1; then
        log_warn "resetprop not available, skipping runtime cleanup"
        return 1
    fi
    
    # Clean known properties
    for _prop in $RUNTIME_PROPS; do
        # Skip empty lines
        [ -z "$_prop" ] && continue
        
        # Check if property exists
        _value="$(getprop "$_prop" 2>/dev/null)"
        if [ -n "$_value" ]; then
            if resetprop -d "$_prop" 2>/dev/null; then
                log_debug "Removed runtime property: $_prop"
                _cleaned="$((_cleaned + 1))"
            else
                log_warn "Failed to remove: $_prop"
                _failed="$((_failed + 1))"
            fi
        fi
    done
    
    # Dynamic discovery: find any remaining pihooks/pixelprops properties
    if command -v getprop >/dev/null 2>&1; then
        for _pattern in pihooks pixelprops; do
            getprop 2>/dev/null | grep "$_pattern" | while IFS='[]:' read -r _ _prop _; do
                # Clean up the property name
                _prop="$(echo "$_prop" | tr -d '[] ')"
                [ -z "$_prop" ] && continue
                
                if resetprop -d "$_prop" 2>/dev/null; then
                    log_debug "Discovered and removed: $_prop"
                    # Can't increment counter in subshell, but log is sufficient
                fi
            done
        done
    fi
    
    log_info "Runtime cleanup: $_cleaned properties removed, $_failed failed"
    
    if [ "$_failed" -gt 0 ]; then
        return 1
    fi
    return 0
}

# Verify cleanup was successful
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    _issues=0
    
    # Check build.prop
    if [ -f "$BUILD_PROP" ]; then
        for _pattern in $PROP_PATTERNS; do
            if grep -q "$_pattern" "$BUILD_PROP" 2>/dev/null; then
                log_error "Verification failed: '$_pattern' still in build.prop"
                _issues="$((_issues + 1))"
            fi
        done
    fi
    
    # Check runtime properties
    if command -v getprop >/dev/null 2>&1; then
        _remaining="$(getprop 2>/dev/null | grep -c -E 'pihooks|pixelprops' || echo 0)"
        if [ "$_remaining" -gt 0 ]; then
            log_warn "Verification: $_remaining PIF properties still in runtime"
            _issues="$((_issues + 1))"
        fi
    fi
    
    if [ "$_issues" -eq 0 ]; then
        log_info "Verification passed: system is clean"
        return 0
    else
        log_warn "Verification found $_issues issues"
        return 1
    fi
}

# Main execution
main() {
    init_logging
    
    # Sanity checks
    if ! check_root; then
        EXIT_CODE=2
        log_execution_time
        exit $EXIT_CODE
    fi
    
    # Attempt to remount system
    _remount_status=0
    remount_system_rw
    _remount_status=$?
    
    if [ "$_remount_status" -eq 0 ]; then
        # Direct modification path
        clean_build_prop
        _prop_status=$?
        
        remount_system_ro
        
        if [ "$_prop_status" -ne 0 ]; then
            EXIT_CODE=1
        fi
    elif [ "$_remount_status" -eq 2 ]; then
        # Bind mount fallback - skip build.prop modification
        log_warn "Using fallback mode (runtime-only cleanup)"
        EXIT_CODE=1
    else
        log_error "Cannot modify system partition"
        EXIT_CODE=2
    fi
    
    # Always attempt runtime cleanup
    if ! clean_runtime_props; then
        [ "$EXIT_CODE" -eq 0 ] && EXIT_CODE=1
    fi
    
    # Verify
    if ! verify_cleanup; then
        [ "$EXIT_CODE" -eq 0 ] && EXIT_CODE=1
    fi
    
    # Final status
    case $EXIT_CODE in
        0) log_info "PIHooks removal completed successfully" ;;
        1) log_warn "PIHooks removal completed with warnings" ;;
        *) log_error "PIHooks removal failed" ;;
    esac
    
    log_execution_time
    log_info "=========================================="
    
    exit $EXIT_CODE
}

# Execute main function
main "$@"

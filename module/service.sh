#!/system/bin/sh
# PIHooks Remover - service.sh
# Fallback script that runs at boot_completed stage
# Ensures runtime properties are cleaned even if post-fs-data fails
# POSIX-compliant, shellcheck-verified

MODDIR="${0%/*}"
LOGFILE="/cache/pihooks_remover.log"
LOGCAT_TAG="PIHooksRemover"
START_TIME=""
RETRY_COUNT=3
RETRY_DELAY=1

# Property patterns for discovery
PROP_PATTERNS="pihooks pixelprops"

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

# Get current timestamp in milliseconds
get_time_ms() {
    if [ -r /proc/uptime ]; then
        read -r uptime _ < /proc/uptime
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
    _log_entry="[$_timestamp] [$_level] [service] $_msg"
    
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

# Initialize
init() {
    START_TIME="$(get_time_ms)"
    log_info "=========================================="
    log_info "PIHooks Remover v1.0.0 (service.sh - boot_completed)"
    log_info "Module directory: $MODDIR"
}

# Log execution time
log_execution_time() {
    _end_time="$(get_time_ms)"
    if [ -n "$START_TIME" ] && [ -n "$_end_time" ]; then
        _duration="$((_end_time - START_TIME))"
        log_info "Service script completed in ${_duration}ms"
    fi
}

# Check if properties still exist
check_props_exist() {
    _count=0
    
    if command -v getprop >/dev/null 2>&1; then
        for _pattern in $PROP_PATTERNS; do
            _matches="$(getprop 2>/dev/null | grep -c "$_pattern" || echo 0)"
            _count="$((_count + _matches))"
        done
    fi
    
    return "$_count"
}

# Clean runtime properties
clean_runtime_props() {
    log_info "Cleaning runtime properties..."
    
    _cleaned=0
    _failed=0
    
    # Check if resetprop is available
    if ! command -v resetprop >/dev/null 2>&1; then
        log_error "resetprop not available"
        return 1
    fi
    
    # Clean known properties
    for _prop in $RUNTIME_PROPS; do
        [ -z "$_prop" ] && continue
        
        _value="$(getprop "$_prop" 2>/dev/null)"
        if [ -n "$_value" ]; then
            if resetprop -d "$_prop" 2>/dev/null; then
                log_debug "Removed: $_prop"
                _cleaned="$((_cleaned + 1))"
            else
                log_warn "Failed to remove: $_prop"
                _failed="$((_failed + 1))"
            fi
        fi
    done
    
    # Dynamic discovery
    for _pattern in $PROP_PATTERNS; do
        getprop 2>/dev/null | grep "$_pattern" | while IFS='[]:' read -r _ _prop _; do
            _prop="$(echo "$_prop" | tr -d '[] ')"
            [ -z "$_prop" ] && continue
            
            if resetprop -d "$_prop" 2>/dev/null; then
                log_debug "Discovered and removed: $_prop"
            fi
        done
    done
    
    log_info "Cleaned $_cleaned properties, $_failed failed"
    
    [ "$_failed" -eq 0 ]
}

# Persistent property cleanup via settings delete
clean_persist_props() {
    log_info "Attempting persistent property cleanup..."
    
    # Try to delete from /data/property/persistent_properties
    _persist_file="/data/property/persistent_properties"
    if [ -f "$_persist_file" ]; then
        log_debug "Found persistent properties file"
        # Note: Direct modification not recommended, resetprop -d handles this
    fi
    
    return 0
}

# Main execution with retry logic
main() {
    init
    
    _attempt=1
    _success=0
    
    while [ "$_attempt" -le "$RETRY_COUNT" ]; do
        log_info "Cleanup attempt $_attempt of $RETRY_COUNT"
        
        # Check if already clean
        if ! check_props_exist; then
            log_info "System already clean, no PIF properties found"
            _success=1
            break
        fi
        
        # Attempt cleanup
        if clean_runtime_props; then
            # Verify
            if ! check_props_exist; then
                log_info "Cleanup successful on attempt $_attempt"
                _success=1
                break
            fi
        fi
        
        # Wait before retry
        if [ "$_attempt" -lt "$RETRY_COUNT" ]; then
            log_debug "Waiting ${RETRY_DELAY}s before retry..."
            sleep "$RETRY_DELAY"
        fi
        
        _attempt="$((_attempt + 1))"
    done
    
    # Also try persistent cleanup
    clean_persist_props
    
    # Final verification
    _remaining=0
    if check_props_exist; then
        _remaining=$?
    fi
    
    if [ "$_success" -eq 1 ]; then
        log_info "Service cleanup completed successfully"
        _exit_code=0
    elif [ "$_remaining" -gt 0 ]; then
        log_warn "Service cleanup partial: $_remaining properties remaining"
        _exit_code=1
    else
        log_info "Service cleanup completed"
        _exit_code=0
    fi
    
    log_execution_time
    log_info "=========================================="
    
    exit "$_exit_code"
}

# Execute
main "$@"

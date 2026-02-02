#!/system/bin/sh
# PIHooks Remover - post-fs-data.sh
# Uses KernelSU/Magisk Magic Mount overlay for build.prop filtering
# This runs very early (~500ms) - perfect for overlay setup before prop daemon
# POSIX-compliant, shellcheck-verified
# Target: Android 10-16, KernelSU 0.9.0+, Magisk 20.0+

MODDIR="${0%/*}"
# Read version from module.prop
VERSION="$(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d'=' -f2 || echo "unknown")"
# Use /data/local/tmp for logging - works on all devices including A/B
# /cache doesn't exist on modern A/B partition devices
LOGFILE="/data/local/tmp/pihooks_remover.log"
OVERLAY_DIR="$MODDIR/system"

# Property patterns to filter out from build.prop
# These are the persist.sys.pihooks and persist.sys.pixelprops entries
# Extended pattern to catch all variants including ro.pihooks and ro.pixelprops
FILTER_PATTERNS="pihooks\|pixelprops"

# Logging function with timestamp
log() {
    _timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"
    _msg="[$_timestamp] [post-fs-data] $*"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null
    echo "$_msg" >> "$LOGFILE" 2>/dev/null
}

# Rotate log if too large (> 100KB)
rotate_log() {
    if [ -f "$LOGFILE" ]; then
        _size="$(wc -c < "$LOGFILE" 2>/dev/null || echo 0)"
        if [ "$_size" -gt 102400 ]; then
            mv "$LOGFILE" "${LOGFILE}.old" 2>/dev/null
        fi
    fi
}

# ============================================================
# Verification helper
# ============================================================
verify_cleanup() {
    _count="$(getprop 2>/dev/null | grep -c -E "pihooks|pixelprops" || echo 0)"
    if [ "$_count" -eq 0 ]; then
        log "VERIFIED: All pihooks/pixelprops properties removed"
        return 0
    else
        log "WARNING: $_count properties still remain"
        getprop 2>/dev/null | grep -E "pihooks|pixelprops" | while read -r line; do
            log "  Remaining: $line"
        done
        return 1
    fi
}

# ============================================================
# MAIN EXECUTION
# Strategy: Create Magic Mount overlay with filtered build.prop
# KernelSU will automatically mount $MODDIR/system over /system
# This avoids timing issues - overlay is ready before prop daemon
# ============================================================

rotate_log

# Start timing
_start_time="$(date +%s%N 2>/dev/null || date +%s)000000"

log "=========================================="
log "PIHooks Remover v${VERSION} starting"
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
    log "WARNING: Unknown root solution - attempting generic approach"
fi

log "Strategy: Magic Mount overlay ($ROOT_TYPE)"

# List of all prop files to filter (Infinity-X stores props in multiple locations)
PROP_FILES="
/system/build.prop
/system/system_ext/etc/build.prop
/system/product/build.prop
/system/vendor/build.prop
/vendor/build.prop
/product/build.prop
/system_ext/build.prop
/odm/etc/build.prop
"

# Create overlay directory structure for all potential paths
for _subdir in "" "system_ext/etc" "product" "vendor"; do
    mkdir -p "$OVERLAY_DIR/$_subdir" 2>/dev/null
done

# Create additional overlay directories
mkdir -p "$MODDIR/vendor" "$MODDIR/product" "$MODDIR/system_ext/etc" "$MODDIR/odm/etc" 2>/dev/null

log "Created overlay directories"

_total_filtered=0

# Process each prop file
for _prop_file in $PROP_FILES; do
    [ ! -f "$_prop_file" ] && continue
    
    # Determine overlay destination path
    case "$_prop_file" in
        /system/*)
            _overlay_dest="$MODDIR$_prop_file"
            ;;
        /vendor/*)
            _overlay_dest="$MODDIR$_prop_file"
            ;;
        /product/*)
            _overlay_dest="$MODDIR$_prop_file"
            ;;
        /system_ext/*)
            _overlay_dest="$MODDIR$_prop_file"
            ;;
        /odm/*)
            _overlay_dest="$MODDIR$_prop_file"
            ;;
        *)
            continue
            ;;
    esac
    
    # Create parent directory
    mkdir -p "$(dirname "$_overlay_dest")" 2>/dev/null
    
    # Single pass: filter and count in one operation
    # This is more efficient than grep -c followed by grep -v
    _original_lines=$(wc -l < "$_prop_file" 2>/dev/null || echo 0)
    
    # Create filtered overlay
    if grep -v "$FILTER_PATTERNS" "$_prop_file" > "$_overlay_dest" 2>/dev/null; then
        _new_lines=$(wc -l < "$_overlay_dest" 2>/dev/null || echo 0)
        _match_count=$((_original_lines - _new_lines))
        
        if [ "$_match_count" -gt 0 ]; then
            log "Filtered $_match_count entries from $_prop_file"
            _total_filtered=$((_total_filtered + _match_count))
            
            # Set permissions and SELinux context
            chmod 644 "$_overlay_dest" 2>/dev/null
            chown root:root "$_overlay_dest" 2>/dev/null
            if command -v chcon >/dev/null 2>&1; then
                chcon --reference="$_prop_file" "$_overlay_dest" 2>/dev/null
            fi
            log "Created filtered overlay: $_overlay_dest"
        else
            # No changes needed - remove empty overlay to avoid unnecessary mount
            rm -f "$_overlay_dest" 2>/dev/null
        fi
    fi
done

if [ "$_total_filtered" -eq 0 ]; then
    log "No pihooks/pixelprops entries found in any prop files (already clean)"
else
    log "Total entries filtered from all prop files: $_total_filtered"
fi

log "Overlay setup complete - root solution will mount automatically"

# Calculate execution time
_end_time="$(date +%s%N 2>/dev/null || date +%s)000000"
_elapsed=$(( (_end_time - _start_time) / 1000000 ))
log "Execution completed in ${_elapsed}ms"

# Final verification (properties may still exist until service.sh runs)
verify_cleanup
_exit_code=$?

log "=========================================="

# Exit 0 = success, overlay is ready for root solution to mount
exit $_exit_code

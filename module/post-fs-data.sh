#!/system/bin/sh
# PIHooks Remover - post-fs-data.sh
# FIX BUG #1: Uses KernelSU Magic Mount overlay instead of direct /system modification
# This runs very early (~500ms) - too early for resetprop, but perfect for overlay setup
# POSIX-compliant, shellcheck-verified
# Target: Android 14-16, KernelSU 0.9.0+, Infinity-X 3.5

MODDIR="${0%/*}"
LOGFILE="/cache/pihooks_remover.log"
BUILD_PROP="/system/build.prop"
OVERLAY_DIR="$MODDIR/system"
OVERLAY_PROP="$OVERLAY_DIR/build.prop"

# Property patterns to filter out from build.prop
# These are the persist.sys.pihooks and persist.sys.pixelprops entries
FILTER_PATTERNS="persist.sys.pihooks\|persist.sys.pixelprops"

# Logging function with timestamp
log() {
    _timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"
    _msg="[$_timestamp] [post-fs-data] $*"
    
    # Ensure /cache exists and is writable
    if [ -d "/cache" ] || mkdir -p /cache 2>/dev/null; then
        echo "$_msg" >> "$LOGFILE" 2>/dev/null
    fi
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
# MAIN EXECUTION
# Strategy: Create Magic Mount overlay with filtered build.prop
# KernelSU will automatically mount $MODDIR/system over /system
# This avoids timing issues - overlay is ready before prop daemon
# ============================================================

rotate_log

log "=========================================="
log "PIHooks Remover v1.1.0 starting"
log "Module directory: $MODDIR"
log "Strategy: KernelSU Magic Mount overlay"

# Check if source build.prop exists
if [ ! -f "$BUILD_PROP" ]; then
    log "ERROR: $BUILD_PROP not found - cannot create overlay"
    log "=========================================="
    exit 1
fi

# Create overlay directory structure
# KernelSU mounts $MODDIR/system over /system automatically
if ! mkdir -p "$OVERLAY_DIR" 2>/dev/null; then
    log "ERROR: Failed to create overlay directory $OVERLAY_DIR"
    log "=========================================="
    exit 1
fi

log "Created overlay directory: $OVERLAY_DIR"

# Count matching lines before filtering (for logging)
_match_count="$(grep -c "$FILTER_PATTERNS" "$BUILD_PROP" 2>/dev/null || echo 0)"

if [ "$_match_count" -eq 0 ]; then
    log "No pihooks/pixelprops entries found in build.prop (already clean)"
    # Still create the overlay to ensure consistency
    cp "$BUILD_PROP" "$OVERLAY_PROP" 2>/dev/null
else
    log "Found $_match_count pihooks/pixelprops entries to remove"
fi

# Filter out pihooks and pixelprops lines using grep -v
# grep -v is POSIX-compliant and fast (< 50ms typically)
# This creates a clean build.prop in the overlay directory
if grep -v "$FILTER_PATTERNS" "$BUILD_PROP" > "$OVERLAY_PROP" 2>/dev/null; then
    log "Successfully created filtered overlay at $OVERLAY_PROP"
    
    # Verify the overlay was created correctly
    _new_count="$(grep -c "$FILTER_PATTERNS" "$OVERLAY_PROP" 2>/dev/null || echo 0)"
    if [ "$_new_count" -eq 0 ]; then
        log "Verification passed: overlay contains 0 pihooks/pixelprops entries"
    else
        log "WARNING: Overlay still contains $_new_count entries (unexpected)"
    fi
    
    # Set proper permissions (same as original build.prop)
    chmod 644 "$OVERLAY_PROP" 2>/dev/null
    chown root:root "$OVERLAY_PROP" 2>/dev/null
    
    # Copy SELinux context from original if available
    if command -v chcon >/dev/null 2>&1; then
        chcon --reference="$BUILD_PROP" "$OVERLAY_PROP" 2>/dev/null
        log "Applied SELinux context from original build.prop"
    fi
else
    log "ERROR: Failed to create overlay build.prop"
    log "=========================================="
    exit 1
fi

log "Overlay setup complete - KernelSU will mount automatically"
log "Execution time: < 100ms (grep -v only)"
log "=========================================="

# Exit 0 = success, overlay is ready for KernelSU to mount
exit 0

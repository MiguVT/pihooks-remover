#!/system/bin/sh
# PIHooks Remover - KernelSU post-mount verification
# Runs AFTER OverlayFS is mounted (KernelSU-specific)
# POSIX-compliant, shellcheck-verified

MODDIR="${0%/*}"
LOGFILE="/data/local/tmp/pihooks_remover.log"

# ============================================================
# Logging function
# ============================================================
log() {
    _timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")"
    mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null
    echo "[$_timestamp] [post-mount] $*" >> "$LOGFILE" 2>/dev/null
}

# ============================================================
# Only run on KernelSU
# ============================================================
if [ -z "$KSU" ]; then
    exit 0
fi

# ============================================================
# Read version from module.prop
# ============================================================
VERSION="$(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d'=' -f2 || echo "unknown")"

log "=========================================="
log "PIHooks Remover v${VERSION} post-mount (KernelSU)"
log "Verifying OverlayFS overlay..."

# ============================================================
# Verify overlay is working
# ============================================================
_remaining="$(getprop 2>/dev/null | grep -c -E "pihooks|pixelprops" || echo 0)"

if [ "$_remaining" -eq 0 ]; then
    log "SUCCESS: OverlayFS overlay active - 0 properties found"
else
    log "WARNING: $_remaining properties remain after OverlayFS mount"
    log "Runtime cleanup will be handled by service.sh"
    
    # Log which properties remain for debugging
    getprop 2>/dev/null | grep -E "pihooks|pixelprops" | while read -r line; do
        log "  Remaining: $line"
    done
fi

log "=========================================="
exit 0

#!/system/bin/sh
# PIHooks Remover - Installation script
# Provides KernelSU/Magisk/APatch detection and setup instructions
# POSIX-compliant, shellcheck-verified

# shellcheck disable=SC2034
# SKIPUNZIP is used by KernelSU/Magisk installer framework
SKIPUNZIP=0

# ============================================================
# Display installation banner
# ============================================================
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " PIHooks Remover"
ui_print " Removes PIF/PixelProps properties"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ============================================================
# Read version from module.prop
# ============================================================
if [ -f "$MODPATH/module.prop" ]; then
    VERSION="$(grep '^version=' "$MODPATH/module.prop" 2>/dev/null | cut -d'=' -f2 || echo "unknown")"
else
    VERSION="unknown"
fi
ui_print " Version: v${VERSION}"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ============================================================
# Detect root solution
# ============================================================
if [ -n "$KSU" ]; then
    ui_print ""
    ui_print "✓ KernelSU detected (OverlayFS mode)"
    ui_print ""
    ui_print "📦 Recommended for KernelSU:"
    ui_print "   Install meta-overlayfs metamodule"
    ui_print "   https://github.com/backslashxx/ksu-metamodule"
    ui_print ""
    
    # Check for meta-overlayfs
    if [ -d "/data/adb/modules/metamodule" ] || [ -d "/data/adb/metamodule" ]; then
        ui_print "✓ meta-overlayfs detected"
    else
        ui_print "⚠ meta-overlayfs not found (optional)"
        ui_print "  Module will work, but meta-overlayfs provides"
        ui_print "  cleaner OverlayFS integration"
    fi
    
elif [ -n "$APATCH" ]; then
    ui_print ""
    ui_print "✓ APatch detected"
    ui_print "  Note: APatch support is experimental"
    
elif [ -d "/data/adb/magisk" ]; then
    ui_print ""
    ui_print "✓ Magisk detected (magic mount mode)"
    
else
    ui_print ""
    ui_print "⚠ Unknown root solution"
    ui_print "  Module may not function correctly"
fi

ui_print ""
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "✓ Installation complete"
ui_print "  Properties will be removed on next boot"
ui_print "  Check logs: /data/local/tmp/pihooks_remover.log"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

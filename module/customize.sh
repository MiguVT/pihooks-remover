#!/system/bin/sh
# PIHooks Remover - Installation script
# Detects root solution and provides installation feedback
# POSIX-compliant, shellcheck-verified

# shellcheck disable=SC2034
# SKIPUNZIP is used by KernelSU/Magisk/APatch installer framework
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
  ui_print "✓ KernelSU detected"

elif [ -n "$APATCH" ]; then
  ui_print ""
  ui_print "✓ APatch detected"

elif [ -d "/data/adb/magisk" ]; then
  ui_print ""
  ui_print "✓ Magisk detected"

else
  ui_print ""
  ui_print "⚠ Unknown root solution"
  ui_print "  Module requires resetprop to function"
fi

# ============================================================
# Installation complete - explain module functionality
# ============================================================
ui_print ""
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "✓ Installation complete"
ui_print ""
ui_print "📋 Module:"
ui_print "  • Removes persist.sys.pihooks_* properties"
ui_print "  • Removes persist.sys.pixelprops* properties"
ui_print "  • Works with KernelSU, Magisk, and APatch"
ui_print ""
ui_print "⚙️  Execution:"
ui_print "  • Runs at boot after system is ready"
ui_print "  • Uses resetprop --delete for cleanup"
ui_print "  • Cleans /data/property/ persistence files"
ui_print ""
ui_print "📝 Logs: /data/local/tmp/pihooks_remover.log"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

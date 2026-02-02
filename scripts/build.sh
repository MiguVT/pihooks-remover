#!/bin/bash
# shellcheck shell=bash
# PIHooks Remover - Build Script
# Creates flashable KernelSU/Magisk module ZIP
# Run from repository root
#
# NOTE: This development script requires Bash (not POSIX sh)
#       Module scripts (customize.sh, service.sh, etc.) remain
#       POSIX-compliant and use /system/bin/sh

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MODULE_DIR="$ROOT_DIR/module"
BUILD_DIR="$ROOT_DIR/build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Cleanup function
cleanup() {
    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
    fi
}

# Validate module structure
validate_module() {
    log_info "Validating module structure..."
    
    local required_files=(
        "module.prop"
        "customize.sh"
        "service.sh"
    )
    
    local missing=0
    for file in "${required_files[@]}"; do
        if [ ! -f "$MODULE_DIR/$file" ]; then
            log_error "Missing required file: $file"
            missing=$((missing + 1))
        fi
    done
    
    if [ $missing -gt 0 ]; then
        log_error "Module validation failed: $missing file(s) missing"
        exit 1
    fi
    
    # Validate module.prop
    if ! grep -q '^id=' "$MODULE_DIR/module.prop"; then
        log_error "module.prop missing 'id' field"
        exit 1
    fi
    
    if ! grep -q '^version=' "$MODULE_DIR/module.prop"; then
        log_error "module.prop missing 'version' field"
        exit 1
    fi
    
    log_success "Module structure valid"
}

# Get version from module.prop
get_version() {
    grep '^version=' "$MODULE_DIR/module.prop" | cut -d'=' -f2
}

# Build the module
build_module() {
    local version
    version=$(get_version)
    local zip_name="PIHooks-Remover-v${version}.zip"
    local zip_path="$ROOT_DIR/$zip_name"
    
    log_info "Building PIHooks Remover v${version}..."
    
    # Create clean build directory
    cleanup
    mkdir -p "$BUILD_DIR"
    
    # Copy module files
    log_info "Copying module files..."
    cp "$MODULE_DIR/module.prop" "$BUILD_DIR/"
    cp "$MODULE_DIR/customize.sh" "$BUILD_DIR/"
    cp "$MODULE_DIR/service.sh" "$BUILD_DIR/"
    
    # Copy uninstall.sh if exists
    if [ -f "$MODULE_DIR/uninstall.sh" ]; then
        cp "$MODULE_DIR/uninstall.sh" "$BUILD_DIR/"
    fi
    
    # Copy customize.sh if exists
    if [ -f "$MODULE_DIR/customize.sh" ]; then
        cp "$MODULE_DIR/customize.sh" "$BUILD_DIR/"
    fi
    
    # Set correct permissions
    log_info "Setting permissions..."
    chmod 644 "$BUILD_DIR/module.prop"
    chmod 755 "$BUILD_DIR"/*.sh
    
    # Remove any existing ZIP
    rm -f "$zip_path"
    
    # Create ZIP (Magisk/KernelSU compatible structure)
    log_info "Creating ZIP archive..."
    (
        cd "$BUILD_DIR"
        zip -r9 "$zip_path" . -x "*.git*" -x "*.DS_Store"
    )
    
    # Cleanup build directory
    cleanup
    
    # Verify ZIP
    if [ ! -f "$zip_path" ]; then
        log_error "Failed to create ZIP file"
        exit 1
    fi
    
    local zip_size
    zip_size=$(du -h "$zip_path" | cut -f1)
    
    log_success "Build complete!"
    echo ""
    echo "  Output: $zip_name"
    echo "  Size:   $zip_size"
    echo "  Path:   $zip_path"
    echo ""
    
    # Show ZIP contents
    log_info "ZIP contents:"
    unzip -l "$zip_path"
}

# Main
main() {
    log_info "PIHooks Remover Build Script"
    echo ""
    
    # Change to root directory
    cd "$ROOT_DIR"
    
    # Validate
    validate_module
    
    # Build
    build_module
    
    log_success "Build completed successfully!"
}

# Run main
main "$@"

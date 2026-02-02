#!/bin/bash
# PIHooks Remover - Local Test Script
# Tests module scripts without Android environment
# Run from repository root
#
# NOTE: This development script requires Bash (not POSIX sh)
#       Module scripts (post-fs-data.sh, service.sh, etc.) remain
#       POSIX-compliant and use /system/bin/sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MODULE_DIR="$ROOT_DIR/module"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test functions
test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Testing: $1... "
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}PASS${NC}"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}FAIL${NC} - $1"
}

test_warn() {
    echo -e "${YELLOW}WARN${NC} - $1"
}

# Section header
section() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Test module.prop
test_module_prop() {
    section "Testing module.prop"
    
    local prop_file="$MODULE_DIR/module.prop"
    
    test_start "File exists"
    if [ -f "$prop_file" ]; then
        test_pass
    else
        test_fail "File not found"
        return 1
    fi
    
    test_start "Has id field"
    if grep -q '^id=' "$prop_file"; then
        test_pass
    else
        test_fail "Missing id"
    fi
    
    test_start "Has name field"
    if grep -q '^name=' "$prop_file"; then
        test_pass
    else
        test_fail "Missing name"
    fi
    
    test_start "Has version field"
    if grep -q '^version=' "$prop_file"; then
        test_pass
    else
        test_fail "Missing version"
    fi
    
    test_start "Has versionCode field"
    if grep -q '^versionCode=' "$prop_file"; then
        test_pass
    else
        test_fail "Missing versionCode"
    fi
    
    test_start "Version format (X.Y.Z)"
    local version
    version=$(grep '^version=' "$prop_file" | cut -d'=' -f2)
    if echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        test_pass
    else
        test_fail "Invalid format: $version"
    fi
    
    test_start "versionCode is numeric"
    local version_code
    version_code=$(grep '^versionCode=' "$prop_file" | cut -d'=' -f2)
    if echo "$version_code" | grep -qE '^[0-9]+$'; then
        test_pass
    else
        test_fail "Invalid versionCode: $version_code"
    fi
    
    test_start "ID format (lowercase, no spaces)"
    local id
    id=$(grep '^id=' "$prop_file" | cut -d'=' -f2)
    if echo "$id" | grep -qE '^[a-z][a-z0-9_]*$'; then
        test_pass
    else
        test_fail "Invalid id format: $id"
    fi
}

# Test shell script syntax
test_script_syntax() {
    section "Testing Shell Script Syntax"
    
    for script in "$MODULE_DIR"/*.sh; do
        local name
        name=$(basename "$script")
        
        test_start "$name exists"
        if [ -f "$script" ]; then
            test_pass
        else
            test_fail "Not found"
            continue
        fi
        
        test_start "$name shebang"
        local shebang
        shebang=$(head -1 "$script")
        if [ "$shebang" = "#!/system/bin/sh" ]; then
            test_pass
        else
            test_fail "Expected #!/system/bin/sh, got: $shebang"
        fi
        
        test_start "$name shellcheck"
        if command -v shellcheck &>/dev/null; then
            if shellcheck -x -s sh "$script" 2>/dev/null; then
                test_pass
            else
                test_fail "shellcheck errors"
            fi
        else
            test_warn "shellcheck not installed"
        fi
        
        test_start "$name no bashisms (basic check)"
        local bashisms=0
        
        # Check for common bashisms
        if grep -q '\[\[' "$script"; then
            bashisms=$((bashisms + 1))
        fi
        if grep -q '^function ' "$script"; then
            bashisms=$((bashisms + 1))
        fi
        if grep -q '<<<' "$script"; then
            bashisms=$((bashisms + 1))
        fi
        
        if [ $bashisms -eq 0 ]; then
            test_pass
        else
            test_fail "Found $bashisms potential bashisms"
        fi
    done
}

# Test build script
test_build_script() {
    section "Testing Build Script"
    
    local build_script="$ROOT_DIR/scripts/build.sh"
    
    test_start "Build script exists"
    if [ -f "$build_script" ]; then
        test_pass
    else
        test_fail "Not found"
        return 1
    fi
    
    test_start "Build script executable"
    if [ -x "$build_script" ] || chmod +x "$build_script"; then
        test_pass
    else
        test_fail "Cannot make executable"
    fi
    
    test_start "Build produces ZIP"
    if "$build_script" >/dev/null 2>&1; then
        if ls "$ROOT_DIR"/PIHooks-Remover-*.zip >/dev/null 2>&1; then
            test_pass
            # Cleanup test build
            rm -f "$ROOT_DIR"/PIHooks-Remover-*.zip
        else
            test_fail "No ZIP produced"
        fi
    else
        test_fail "Build script failed"
    fi
}

# Test documentation
test_documentation() {
    section "Testing Documentation"
    
    local docs=(
        "docs/README.md"
        "docs/CHANGELOG.md"
        "docs/TECHNICAL.md"
        "LICENSE"
    )
    
    for doc in "${docs[@]}"; do
        test_start "$doc exists"
        if [ -f "$ROOT_DIR/$doc" ]; then
            test_pass
        else
            test_fail "Not found"
        fi
    done
    
    test_start "CHANGELOG has Unreleased section"
    if grep -q '## \[Unreleased\]' "$ROOT_DIR/docs/CHANGELOG.md" 2>/dev/null; then
        test_pass
    else
        test_warn "No Unreleased section"
    fi
}

# Test CI/CD files
test_cicd() {
    section "Testing CI/CD Configuration"
    
    local workflows=(
        ".github/workflows/release.yml"
        ".github/workflows/build.yml"
        ".github/workflows/lint.yml"
    )
    
    for workflow in "${workflows[@]}"; do
        test_start "$workflow exists"
        if [ -f "$ROOT_DIR/$workflow" ]; then
            test_pass
        else
            test_fail "Not found"
        fi
    done
    
    test_start ".shellcheckrc exists"
    if [ -f "$ROOT_DIR/.shellcheckrc" ]; then
        test_pass
    else
        test_fail "Not found"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${BLUE}==============================${NC}"
    echo -e "${BLUE}       TEST SUMMARY${NC}"
    echo -e "${BLUE}==============================${NC}"
    echo ""
    echo "  Total:  $TESTS_RUN"
    echo -e "  Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "  Failed: ${RED}$TESTS_FAILED${NC}"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}$TESTS_FAILED test(s) failed${NC}"
        return 1
    fi
}

# Main
main() {
    echo -e "${BLUE}PIHooks Remover - Test Suite${NC}"
    echo "=============================="
    
    cd "$ROOT_DIR"
    
    test_module_prop
    test_script_syntax
    test_build_script
    test_documentation
    test_cicd
    
    print_summary
}

main "$@"

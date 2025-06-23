#!/bin/bash
#
# SafeJourney Git Hooks Installer
#
# This script installs the SafeJourney git hooks for your repository.
# It will set up both pre-commit and pre-push hooks to ensure thread safety.
#
# Usage:
#   ./git-hooks/install.sh
#   ./git-hooks/install.sh --pre-commit-only
#   ./git-hooks/install.sh --pre-push-only
#   ./git-hooks/install.sh --uninstall

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_HOOKS_DIR=".git/hooks"
PRE_COMMIT_SOURCE="$SCRIPT_DIR/pre-commit"
PRE_PUSH_SOURCE="$SCRIPT_DIR/pre-push"
PRE_COMMIT_TARGET="$GIT_HOOKS_DIR/pre-commit"
PRE_PUSH_TARGET="$GIT_HOOKS_DIR/pre-push"

# Functions
print_header() {
    echo ""
    echo "${BLUE}${BOLD}🛡️  SafeJourney Git Hooks Installer${NC}"
    echo "${BLUE}${BOLD}===========================================${NC}"
    echo ""
}

print_usage() {
    cat << EOF
${BOLD}Usage:${NC}
  $0                    Install both pre-commit and pre-push hooks
  $0 --pre-commit-only  Install only the pre-commit hook
  $0 --pre-push-only    Install only the pre-push hook
  $0 --uninstall        Remove SafeJourney hooks
  $0 --help             Show this help message

${BOLD}What these hooks do:${NC}
  ${GREEN}pre-commit${NC}  - Checks staged Swift files before commit
  ${GREEN}pre-push${NC}    - Comprehensive check of all Swift files before push

${BOLD}Examples:${NC}
  $0                    # Install both hooks
  $0 --pre-commit-only  # Only install pre-commit hook
  $0 --uninstall        # Remove all hooks

EOF
}

check_requirements() {
    # Check if we're in a git repository
    if [ ! -d ".git" ]; then
        echo "${RED}❌ Error: Not in a git repository root${NC}"
        echo "${YELLOW}💡 Run this script from the root of your git repository${NC}"
        exit 1
    fi
    
    # Check if source files exist
    if [ ! -f "$PRE_COMMIT_SOURCE" ]; then
        echo "${RED}❌ Error: Pre-commit hook source not found: $PRE_COMMIT_SOURCE${NC}"
        exit 1
    fi
    
    if [ ! -f "$PRE_PUSH_SOURCE" ]; then
        echo "${RED}❌ Error: Pre-push hook source not found: $PRE_PUSH_SOURCE${NC}"
        exit 1
    fi
    
    # Create hooks directory if it doesn't exist
    if [ ! -d "$GIT_HOOKS_DIR" ]; then
        echo "${YELLOW}📁 Creating git hooks directory: $GIT_HOOKS_DIR${NC}"
        mkdir -p "$GIT_HOOKS_DIR"
    fi
    
    echo "${GREEN}✅ Requirements check passed${NC}"
}

backup_existing_hook() {
    local hook_path="$1"
    local hook_name="$2"
    
    if [ -f "$hook_path" ]; then
        local backup_path="${hook_path}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "${YELLOW}📦 Backing up existing $hook_name hook to: $backup_path${NC}"
        cp "$hook_path" "$backup_path"
    fi
}

install_hook() {
    local source_path="$1"
    local target_path="$2"
    local hook_name="$3"
    
    echo "${BLUE}📥 Installing $hook_name hook...${NC}"
    
    # Backup existing hook if it exists
    backup_existing_hook "$target_path" "$hook_name"
    
    # Copy the hook
    cp "$source_path" "$target_path"
    chmod +x "$target_path"
    
    echo "${GREEN}✅ $hook_name hook installed successfully${NC}"
    echo "${BLUE}   Source: $source_path${NC}"
    echo "${BLUE}   Target: $target_path${NC}"
}

install_pre_commit() {
    install_hook "$PRE_COMMIT_SOURCE" "$PRE_COMMIT_TARGET" "pre-commit"
}

install_pre_push() {
    install_hook "$PRE_PUSH_SOURCE" "$PRE_PUSH_TARGET" "pre-push"
}

uninstall_hooks() {
    echo "${YELLOW}🗑️  Uninstalling SafeJourney hooks...${NC}"
    
    local uninstalled=false
    
    if [ -f "$PRE_COMMIT_TARGET" ]; then
        # Check if it's our hook
        if grep -q "SafeJourney Pre-commit Hook" "$PRE_COMMIT_TARGET" 2>/dev/null; then
            echo "${BLUE}🗑️  Removing pre-commit hook${NC}"
            rm "$PRE_COMMIT_TARGET"
            uninstalled=true
        else
            echo "${YELLOW}⚠️  Pre-commit hook exists but doesn't appear to be SafeJourney hook${NC}"
        fi
    fi
    
    if [ -f "$PRE_PUSH_TARGET" ]; then
        # Check if it's our hook
        if grep -q "SafeJourney Pre-push Hook" "$PRE_PUSH_TARGET" 2>/dev/null; then
            echo "${BLUE}🗑️  Removing pre-push hook${NC}"
            rm "$PRE_PUSH_TARGET"
            uninstalled=true
        else
            echo "${YELLOW}⚠️  Pre-push hook exists but doesn't appear to be SafeJourney hook${NC}"
        fi
    fi
    
    if [ "$uninstalled" = true ]; then
        echo "${GREEN}✅ SafeJourney hooks uninstalled successfully${NC}"
    else
        echo "${YELLOW}ℹ️  No SafeJourney hooks found to uninstall${NC}"
    fi
}

show_installation_success() {
    local hooks_installed="$1"
    
    echo ""
    echo "${GREEN}${BOLD}🎉 Installation Complete!${NC}"
    echo ""
    echo "${GREEN}✅ Installed hooks: $hooks_installed${NC}"
    echo ""
    echo "${BLUE}${BOLD}What happens next:${NC}"
    
    if [[ "$hooks_installed" == *"pre-commit"* ]]; then
        echo "${BLUE}• ${BOLD}Pre-commit:${NC} Checks staged Swift files before each commit"
        echo "${BLUE}  - Runs automatically on 'git commit'${NC}"
        echo "${BLUE}  - Blocks commits with critical violations${NC}"
        echo "${BLUE}  - Bypass with 'git commit --no-verify' (not recommended)${NC}"
    fi
    
    if [[ "$hooks_installed" == *"pre-push"* ]]; then
        echo "${BLUE}• ${BOLD}Pre-push:${NC} Comprehensive check before pushing to remote"
        echo "${BLUE}  - Runs automatically on 'git push'${NC}"
        echo "${BLUE}  - Uses strict configuration${NC}"
        echo "${BLUE}  - Bypass with 'git push --no-verify' (not recommended)${NC}"
    fi
    
    echo ""
    echo "${BLUE}${BOLD}Configuration:${NC}"
    echo "${BLUE}• Create 'safe-journey-config.json' for custom rules${NC}"
    echo "${BLUE}• Hooks will download the checker automatically if needed${NC}"
    echo "${BLUE}• Source directory checked: Sources/${NC}"
    echo ""
    echo "${YELLOW}${BOLD}💡 Pro tip:${NC} Test the hooks with a dummy commit to ensure they work correctly!"
    echo ""
    echo "${BLUE}📚 For more information: https://github.com/customerio/safe-journey${NC}"
    echo ""
}

# Main execution
main() {
    print_header
    
    case "${1:-}" in
        --help|-h)
            print_usage
            exit 0
            ;;
        --uninstall)
            check_requirements
            uninstall_hooks
            exit 0
            ;;
        --pre-commit-only)
            check_requirements
            install_pre_commit
            show_installation_success "pre-commit"
            ;;
        --pre-push-only)
            check_requirements
            install_pre_push
            show_installation_success "pre-push"
            ;;
        "")
            check_requirements
            install_pre_commit
            install_pre_push
            show_installation_success "pre-commit and pre-push"
            ;;
        *)
            echo "${RED}❌ Error: Unknown option '$1'${NC}"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
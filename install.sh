#!/bin/bash
# Copyright (c) 2025 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/linux-server-reboot-management
#
# Version: 1.0.0
# Created: 2026-01-20
#
# Linux Server Reboot Management Installer
# Installs graceful shutdown hooks and provides templates for autostart/verification

set -uo pipefail

# ============================================================================
# COLORS & LOGGING
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# ============================================================================
# CONFIGURATION
# ============================================================================

# Installation directory
INSTALL_DIR="${INSTALL_DIR:-/opt/linux-server-reboot-management}"

# Detect repository directory
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_DIR="${SCRIPT_DIR}"

# systemd service name
SERVICE_NAME="docker-graceful-shutdown"

# ============================================================================
# PREREQUISITES
# ============================================================================

check_prerequisites() {
    log "Checking prerequisites..."

    # OS Detection
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect OS (missing /etc/os-release)"
        return 1
    fi

    # Bash Version Check
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        error "Bash 4.0+ required (current: $BASH_VERSION)"
        echo "On macOS: brew install bash"
        return 1
    fi

    # Check for systemd
    if ! command -v systemctl >/dev/null 2>&1; then
        error "systemd not found (systemctl command missing)"
        return 1
    fi

    # Check systemd version (require 240+)
    local systemd_version
    systemd_version=$(systemctl --version | head -n1 | awk '{print $2}')
    if [[ "$systemd_version" -lt 240 ]]; then
        error "systemd 240+ required (current: $systemd_version)"
        return 1
    fi

    # Check for Docker
    if ! command -v docker >/dev/null 2>&1; then
        warn "Docker not found - graceful shutdown won't work without Docker"
        warn "Install with: curl -fsSL https://get.docker.com | sh"
    fi

    # Root/Sudo Check
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        warn "This script requires sudo privileges for systemd installation"
        log "You may be prompted for your password"
    fi

    success "Prerequisites check passed"
    return 0
}

# ============================================================================
# INSTALLATION
# ============================================================================

install_graceful_shutdown() {
    log "Installing graceful shutdown hook..."

    # Create installation directory
    if [[ ! -d "$INSTALL_DIR" ]]; then
        sudo mkdir -p "$INSTALL_DIR" || {
            error "Failed to create $INSTALL_DIR"
            return 1
        }
        log "Created installation directory: $INSTALL_DIR"
    else
        log "Installation directory exists: $INSTALL_DIR"
    fi

    # Copy graceful shutdown script
    local script_src="${REPO_DIR}/1-graceful-shutdown/docker-graceful-shutdown.sh"
    if [[ ! -f "$script_src" ]]; then
        error "Graceful shutdown script not found: $script_src"
        return 1
    fi

    sudo cp "$script_src" "${INSTALL_DIR}/" || {
        error "Failed to copy graceful shutdown script"
        return 1
    }
    sudo chmod +x "${INSTALL_DIR}/docker-graceful-shutdown.sh"
    success "Installed: ${INSTALL_DIR}/docker-graceful-shutdown.sh"

    # Install systemd service
    local service_src="${REPO_DIR}/config/systemd/docker-graceful-shutdown.service"
    if [[ ! -f "$service_src" ]]; then
        error "systemd service file not found: $service_src"
        return 1
    fi

    # Create temporary service file with correct path
    local temp_service="/tmp/${SERVICE_NAME}.service"
    sed "s|/opt/docker-shutdown/docker-graceful-shutdown.sh|${INSTALL_DIR}/docker-graceful-shutdown.sh|g" \
        "$service_src" > "$temp_service"

    sudo cp "$temp_service" "/etc/systemd/system/${SERVICE_NAME}.service" || {
        error "Failed to install systemd service"
        return 1
    }
    rm -f "$temp_service"
    success "Installed: /etc/systemd/system/${SERVICE_NAME}.service"

    # Reload systemd
    sudo systemctl daemon-reload || {
        error "Failed to reload systemd"
        return 1
    }

    # Enable and start service
    if ! sudo systemctl is-enabled "${SERVICE_NAME}.service" &>/dev/null; then
        sudo systemctl enable "${SERVICE_NAME}.service" || {
            error "Failed to enable ${SERVICE_NAME}.service"
            return 1
        }
        log "Enabled ${SERVICE_NAME}.service"
    else
        log "${SERVICE_NAME}.service already enabled"
    fi

    sudo systemctl start "${SERVICE_NAME}.service" || {
        error "Failed to start ${SERVICE_NAME}.service"
        return 1
    }

    # Verify service is active
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        success "Graceful shutdown hook installed and active"
        return 0
    else
        error "${SERVICE_NAME}.service is not active"
        log "Check status: sudo systemctl status ${SERVICE_NAME}.service"
        return 1
    fi
}

install_templates() {
    log "Templates available for customization:"
    echo ""
    echo "  - 0-pre-reboot/system-snapshot.sh         (Optional: System snapshots)"
    echo "  - 2-autostart/autostart-template.sh       (Template: 13-phase boot orchestration)"
    echo "  - 2-autostart/autostart-minimal.sh        (Template: Simplified autostart)"
    echo "  - 3-verification/post-reboot-check.sh     (Ready-to-use: Post-reboot verification)"
    echo "  - 3-verification/snapshot-compare.py      (Ready-to-use: Snapshot comparison)"
    echo ""
    log "See docs/TEMPLATES.md for customization guide"
}

# ============================================================================
# VERIFICATION
# ============================================================================

verify_installation() {
    log "Verifying installation..."

    # Check service status
    if ! systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        warn "${SERVICE_NAME}.service is not active"
        log "Run: sudo systemctl status ${SERVICE_NAME}.service"
        return 1
    fi

    # Check script exists and is executable
    if [[ ! -x "${INSTALL_DIR}/docker-graceful-shutdown.sh" ]]; then
        warn "Graceful shutdown script is not executable"
        return 1
    fi

    success "Installation verified successfully"
    return 0
}

# ============================================================================
# NEXT STEPS
# ============================================================================

print_next_steps() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "✅ Linux Server Reboot Management installed successfully!"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "✅ Graceful shutdown hook is active and will run on next reboot"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Test graceful shutdown (optional):"
    echo "   sudo systemctl stop ${SERVICE_NAME}.service"
    echo "   sudo systemctl start ${SERVICE_NAME}.service"
    echo ""
    echo "2. Verify service status:"
    echo "   sudo systemctl status ${SERVICE_NAME}.service"
    echo "   journalctl -u ${SERVICE_NAME}.service -n 20"
    echo ""
    echo "3. Customize autostart and verification scripts:"
    echo "   See: docs/TEMPLATES.md"
    echo "   Templates: 0-pre-reboot/, 2-autostart/, 3-verification/"
    echo ""
    echo "4. Test reboot workflow:"
    echo "   sudo reboot"
    echo "   (After reboot) journalctl -b -1 -u ${SERVICE_NAME}.service"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Documentation:"
    echo "  - Setup Guide:     ${REPO_DIR}/docs/SETUP.md"
    echo "  - Workflow:        ${REPO_DIR}/docs/WORKFLOW.md"
    echo "  - Architecture:    ${REPO_DIR}/docs/ARCHITECTURE.md"
    echo "  - Troubleshooting: ${REPO_DIR}/docs/TROUBLESHOOTING.md"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "GitHub: https://github.com/fidpa/linux-server-reboot-management"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo "═══════════════════════════════════════════════════════════"
    echo " Linux Server Reboot Management Installer v1.0.0"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # Prerequisites check
    check_prerequisites || {
        error "Prerequisites check failed"
        exit 1
    }

    echo ""

    # Install graceful shutdown hook
    install_graceful_shutdown || {
        error "Installation failed"
        exit 1
    }

    echo ""

    # Show templates info
    install_templates

    echo ""

    # Verify installation
    verify_installation || {
        warn "Installation completed but verification failed"
        exit 1
    }

    # Print next steps
    print_next_steps

    exit 0
}

# Run main function
main "$@"

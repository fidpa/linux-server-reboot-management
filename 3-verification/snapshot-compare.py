#!/usr/bin/env python3
# Copyright (c) 2026 Marc Allgeier (fidpa)
# SPDX-License-Identifier: MIT
# https://github.com/fidpa/linux-server-reboot-management
# Version: 1.0.0
"""
Snapshot Comparison Tool - Compare pre/post reboot system snapshots

Compares 20+ sections of system snapshots to detect configuration drift,
service failures, and unexpected changes after reboot.

Usage:
    # Auto-find latest snapshots
    ./snapshot-compare.py --auto-latest

    # Specify snapshot files
    ./snapshot-compare.py pre-reboot.json post-reboot.json

    # JSON output for CI/CD
    ./snapshot-compare.py --auto-latest --json

    # Verbose output
    ./snapshot-compare.py --auto-latest --verbose

Exit Codes:
    0: All checks passed
    1: Critical issues found
    2: Usage error

Environment Variables:
    SNAPSHOT_DIR  Directory containing snapshots (default: /var/log/snapshots)
"""

import argparse
import contextlib
import io
import json
import os
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass
class ComparisonResult:
    """Result of a single comparison section."""

    section: str
    problems: int
    warnings: int
    changes: list[str]


def load_snapshot(filepath: Path) -> dict[str, Any] | None:
    """
    Load JSON snapshot file.

    Args:
        filepath: Path to snapshot JSON file

    Returns:
        Parsed snapshot dictionary, or None on error

    Raises:
        OSError: If file cannot be read
        json.JSONDecodeError: If JSON is invalid
    """
    try:
        with filepath.open("r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"Error loading {filepath}: {e}", file=sys.stderr)
        return None


def compare_system(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare system metrics between snapshots.

    Checks kernel version, disk usage, CPU temperature, memory.

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with problems/warnings count
    """
    print("\n=== SYSTEM COMPARISON ===")

    pre_sys = pre.get("system", {})
    post_sys = post.get("system", {})

    problems = 0
    warnings = 0
    changes = []

    # Check kernel version
    if pre_sys.get("kernel") != post_sys.get("kernel"):
        msg = f"Kernel changed: {pre_sys.get('kernel')} → {post_sys.get('kernel')}"
        print(f"ℹ {msg}")
        changes.append(msg)

    # Check disk space (snapshot uses 'disk_usage_percent')
    pre_disk = pre_sys.get("disk_usage_percent", 0)
    post_disk = post_sys.get("disk_usage_percent", 0)

    if post_disk > 90:
        msg = f"Disk space critical: {post_disk}% used"
        print(f"❌ {msg}")
        problems += 1
        changes.append(msg)
    elif post_disk > pre_disk + 10:
        msg = f"Disk usage increased significantly: {pre_disk}% → {post_disk}%"
        print(f"⚠ {msg}")
        warnings += 1
        changes.append(msg)

    # Check CPU temperature (from system.cpu_temp or custom.cpu_temp_celsius)
    post_temp = post_sys.get("cpu_temp", 0)
    if post_temp == 0:
        # Fallback: Check custom extensions for cpu_temp_celsius
        post_temp = post.get("custom", {}).get("cpu_temp_celsius", 0)
    if post_temp > 80:
        msg = f"CPU temperature high: {post_temp}°C"
        print(f"⚠ {msg}")
        warnings += 1
        changes.append(msg)

    if problems == 0 and warnings == 0:
        print("✓ System metrics healthy")

    return ComparisonResult("system", problems, warnings, changes)


def compare_services(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare systemd service status between snapshots.

    Checks running, enabled, and failed services.

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with problems count
    """
    print("\n=== SERVICE COMPARISON ===")

    pre_running = set(pre.get("services", {}).get("running", []))
    post_running = set(post.get("services", {}).get("running", []))
    pre_failed = set(pre.get("services", {}).get("failed", []))
    post_failed = set(post.get("services", {}).get("failed", []))

    # Remove "●" marker artifact from failed services
    pre_failed.discard("●")
    post_failed.discard("●")

    stopped = pre_running - post_running
    started = post_running - pre_running
    new_failures = post_failed - pre_failed

    problems = 0
    changes = []

    if stopped:
        msg = f"Services stopped after reboot ({len(stopped)})"
        print(f"❌ {msg}:")
        for s in sorted(stopped):
            print(f"   - {s}")
            changes.append(f"stopped: {s}")
        problems += len(stopped)

    if started:
        msg = f"New services started ({len(started)})"
        print(f"✅ {msg}:")
        for s in sorted(started):
            print(f"   + {s}")
            changes.append(f"started: {s}")

    if new_failures:
        msg = f"New failed services ({len(new_failures)})"
        print(f"❌ {msg}:")
        for s in sorted(new_failures):
            print(f"   ! {s}")
            changes.append(f"failed: {s}")
        problems += len(new_failures)

    if not stopped and not started and not new_failures:
        print("✓ All services maintained their state")

    return ComparisonResult("services", problems, 0, changes)


def compare_docker(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare Docker container status.

    Checks container state (running/stopped/missing).

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with problems count
    """
    print("\n=== DOCKER CONTAINER COMPARISON ===")

    pre_docker = pre.get("docker", {})
    post_docker = post.get("docker", {})

    pre_containers = pre_docker.get("containers", [])
    post_containers = post_docker.get("containers", [])

    if not pre_containers and not post_containers:
        print("ℹ No Docker containers (skipping)")
        return ComparisonResult("docker", 0, 0, [])

    pre_names = {c["name"]: c.get("state") for c in pre_containers if c.get("name")}
    post_names = {c["name"]: c.get("state") for c in post_containers if c.get("name")}

    problems = 0
    changes = []

    for name, state in pre_names.items():
        if name not in post_names:
            msg = f"{name}: Missing after reboot"
            print(f"❌ {msg}")
            problems += 1
            changes.append(msg)
        elif state == "running" and post_names[name] != "running":
            msg = f"{name}: Was {state}, now {post_names[name]}"
            print(f"❌ {msg}")
            problems += 1
            changes.append(msg)

    # Check for new containers
    new_containers = set(post_names.keys()) - set(pre_names.keys())
    if new_containers:
        print(f"✅ New containers started ({len(new_containers)}):")
        for name in sorted(new_containers):
            print(f"   + {name} ({post_names[name]})")
            changes.append(f"new: {name}")

    if problems == 0 and not new_containers:
        print("✓ All containers maintained their state")

    return ComparisonResult("docker", problems, 0, changes)


def compare_network_interfaces(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare network interface states.

    Checks state (UP/DOWN), IP addresses, MAC addresses from ip -j output.

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with problems/warnings count
    """
    print("\n=== NETWORK INTERFACE COMPARISON ===")

    # interfaces is an array from ip -j, convert to dict by ifname
    pre_ifaces_list = pre.get("network", {}).get("interfaces", [])
    post_ifaces_list = post.get("network", {}).get("interfaces", [])

    pre_ifaces = {
        iface.get("ifname"): iface for iface in pre_ifaces_list if iface.get("ifname")
    }
    post_ifaces = {
        iface.get("ifname"): iface for iface in post_ifaces_list if iface.get("ifname")
    }

    problems = 0
    warnings = 0
    changes = []

    for ifname, pre_data in pre_ifaces.items():
        if ifname not in post_ifaces:
            msg = f"{ifname}: Interface missing after reboot"
            print(f"❌ {msg}")
            problems += 1
            changes.append(msg)
            continue

        post_data = post_ifaces[ifname]

        # State change (operstate from ip -j)
        pre_state = pre_data.get("operstate", "UNKNOWN")
        post_state = post_data.get("operstate", "UNKNOWN")
        if pre_state != post_state:
            msg = f"{ifname}: State changed {pre_state} → {post_state}"
            print(f"⚠ {msg}")
            warnings += 1
            changes.append(msg)

        # IP change (check addr_info array)
        pre_ips = {
            addr.get("local")
            for addr in pre_data.get("addr_info", [])
            if addr.get("family") == "inet"
        }
        post_ips = {
            addr.get("local")
            for addr in post_data.get("addr_info", [])
            if addr.get("family") == "inet"
        }
        if pre_ips != post_ips:
            msg = f"{ifname}: IP changed {pre_ips} → {post_ips}"
            print(f"⚠ {msg}")
            warnings += 1
            changes.append(msg)

        # MAC change (should NEVER happen)
        pre_mac = pre_data.get("address", "")
        post_mac = post_data.get("address", "")
        if pre_mac != post_mac:
            msg = f"{ifname}: MAC changed {pre_mac} → {post_mac}"
            print(f"❌ {msg}")
            problems += 1
            changes.append(msg)

    # Check default gateway
    pre_gateway = pre.get("network", {}).get("default_gateway", "none")
    post_gateway = post.get("network", {}).get("default_gateway", "none")

    if pre_gateway != post_gateway:
        msg = "Default route changed"
        print(f"⚠ {msg}")
        if verbose:
            print(f"   Pre:  {pre_gateway}")
            print(f"   Post: {post_gateway}")
        warnings += 1
        changes.append(msg)

    if problems == 0 and warnings == 0:
        print("✓ Network configuration maintained")

    return ComparisonResult("network", problems, warnings, changes)


def compare_usb_devices(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare USB devices (critical for network adapters).

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with problems count
    """
    print("\n=== USB DEVICE COMPARISON ===")

    pre_devices = set(pre.get("usb_devices", []))
    post_devices = set(post.get("usb_devices", []))

    removed = pre_devices - post_devices
    added = post_devices - pre_devices

    problems = 0
    warnings = 0
    changes = []

    # Critical: Network adapter missing?
    critical_missing = [d for d in removed if "RTL8153" in d or "RTL8156" in d]
    if critical_missing:
        print(f"❌ Network adapters missing ({len(critical_missing)}):")
        for device in critical_missing:
            print(f"   - {device}")
            changes.append(f"missing: {device}")
        problems += len(critical_missing)

    # Non-critical removed devices
    non_critical_removed = removed - set(critical_missing)
    if non_critical_removed:
        print(f"⚠ USB devices removed ({len(non_critical_removed)}):")
        for device in sorted(non_critical_removed):
            print(f"   - {device}")
            changes.append(f"removed: {device}")
        warnings += len(non_critical_removed)

    # New devices
    if added:
        print(f"✅ USB devices added ({len(added)}):")
        for device in sorted(added):
            print(f"   + {device}")
            changes.append(f"added: {device}")

    if problems == 0 and warnings == 0 and not added:
        print("✓ USB devices unchanged")

    return ComparisonResult("usb_devices", problems, warnings, changes)


def compare_route_guardian(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare Route Guardian status (router/gateway systems only).

    Critical for failover functionality.

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with problems/warnings count
    """
    print("\n=== ROUTE GUARDIAN COMPARISON ===")

    pre_rg = pre.get("route_guardian", {})
    post_rg = post.get("route_guardian", {})

    if not pre_rg and not post_rg:
        print("ℹ Route Guardian not available (not configured)")
        return ComparisonResult("route_guardian", 0, 0, [])

    problems = 0
    warnings = 0
    changes = []

    # Service active check
    if pre_rg.get("service_active") and not post_rg.get("service_active"):
        msg = "Route Guardian service not active after reboot"
        print(f"❌ {msg}")
        problems += 1
        changes.append(msg)

    # Gateway changes
    pre_gw = pre_rg.get("active_gateway", "unknown")
    post_gw = post_rg.get("active_gateway", "unknown")
    if pre_gw != post_gw:
        msg = f"Active gateway changed: {pre_gw} → {post_gw}"
        print(f"⚠ {msg}")
        warnings += 1
        changes.append(msg)

    # DSL route check
    if pre_rg.get("dsl_route_present") and not post_rg.get("dsl_route_present"):
        msg = "DSL route missing after reboot"
        print(f"❌ {msg}")
        problems += 1
        changes.append(msg)

    # LTE route check
    if pre_rg.get("lte_route_present") and not post_rg.get("lte_route_present"):
        msg = "LTE route missing after reboot"
        print(f"⚠ {msg}")
        warnings += 1
        changes.append(msg)

    if problems == 0 and warnings == 0:
        print("✓ Route Guardian status maintained")

    return ComparisonResult("route_guardian", problems, warnings, changes)


def compare_pi_zero_fleet(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare Pi Zero Fleet reachability.

    Checks fleet devices: watchdog, security, dns_gateway, gpio_bedroom, gpio_bathroom.

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with problems/warnings count
    """
    print("\n=== PI ZERO FLEET COMPARISON ===")

    pre_fleet = pre.get("pi_zero_fleet", {})
    post_fleet = post.get("pi_zero_fleet", {})

    if not pre_fleet and not post_fleet:
        print("ℹ Pi Zero Fleet not available (not configured)")
        return ComparisonResult("pi_zero_fleet", 0, 0, [])

    problems = 0
    warnings = 0
    changes = []

    devices = ["watchdog", "security", "dns_gateway", "gpio_bedroom", "gpio_bathroom"]

    for device in devices:
        pre_data = pre_fleet.get(device, {})
        post_data = post_fleet.get(device, {})

        pre_reachable = pre_data.get("reachable", False)
        post_reachable = post_data.get("reachable", False)

        if pre_reachable and not post_reachable:
            msg = f"{device} ({post_data.get('ip', 'unknown')}): Unreachable after reboot"
            print(f"⚠ {msg}")
            warnings += 1
            changes.append(msg)
        elif not pre_reachable and post_reachable:
            msg = f"{device} ({post_data.get('ip', 'unknown')}): Now reachable"
            print(f"✅ {msg}")
            changes.append(msg)

    if problems == 0 and warnings == 0 and not changes:
        print("✓ All fleet devices reachable")

    return ComparisonResult("pi_zero_fleet", problems, warnings, changes)


def compare_networkmanager(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare NetworkManager connection states.

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with warnings count
    """
    print("\n=== NETWORKMANAGER COMPARISON ===")

    pre_nm = pre.get("networkmanager", {})
    post_nm = post.get("networkmanager", {})

    pre_active = {
        conn.get("name"): conn.get("state")
        for conn in pre_nm.get("active_connections", [])
        if conn.get("name")
    }
    post_active = {
        conn.get("name"): conn.get("state")
        for conn in post_nm.get("active_connections", [])
        if conn.get("name")
    }

    warnings = 0
    changes = []

    # Check for deactivated connections
    deactivated = set(pre_active.keys()) - set(post_active.keys())
    if deactivated:
        print(f"⚠ Connections deactivated ({len(deactivated)}):")
        for conn in sorted(deactivated):
            print(f"   - {conn}")
            changes.append(f"deactivated: {conn}")
        warnings += len(deactivated)

    # Check for newly activated connections
    activated = set(post_active.keys()) - set(pre_active.keys())
    if activated:
        print(f"✅ Connections activated ({len(activated)}):")
        for conn in sorted(activated):
            print(f"   + {conn}")
            changes.append(f"activated: {conn}")

    if warnings == 0 and not activated:
        print("✓ NetworkManager connections maintained")

    return ComparisonResult("networkmanager", 0, warnings, changes)


def compare_wireguard(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare WireGuard VPN status.

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with problems/warnings count
    """
    print("\n=== WIREGUARD COMPARISON ===")

    pre_wg = pre.get("wireguard", {})
    post_wg = post.get("wireguard", {})

    if not pre_wg.get("interface_active") and not post_wg.get("interface_active"):
        print("ℹ WireGuard not active (not configured)")
        return ComparisonResult("wireguard", 0, 0, [])

    problems = 0
    warnings = 0
    changes = []

    # Interface active check
    if pre_wg.get("interface_active") and not post_wg.get("interface_active"):
        msg = "WireGuard interface not active after reboot"
        print(f"❌ {msg}")
        problems += 1
        changes.append(msg)

    # Peer count change
    pre_peers = pre_wg.get("peers_count", 0)
    post_peers = post_wg.get("peers_count", 0)
    if pre_peers != post_peers:
        msg = f"Peer count changed: {pre_peers} → {post_peers}"
        print(f"⚠ {msg}")
        warnings += 1
        changes.append(msg)

    if problems == 0 and warnings == 0:
        print("✓ WireGuard status maintained")

    return ComparisonResult("wireguard", problems, warnings, changes)


def compare_hardware_throttling(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare hardware throttling events (Raspberry Pi systems).

    Detects under-voltage, thermal throttling.

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with warnings count
    """
    print("\n=== HARDWARE THROTTLING COMPARISON ===")

    pre_hw = pre.get("hardware", {})
    post_hw = post.get("hardware", {})

    if not pre_hw.get("throttle_events") and not post_hw.get("throttle_events"):
        print("ℹ Hardware throttling data not available")
        return ComparisonResult("hardware_throttling", 0, 0, [])

    warnings = 0
    changes = []

    post_throttle = post_hw.get("throttle_events", {})

    # Check for throttling events
    if post_throttle.get("under_voltage"):
        msg = "Under-voltage detected"
        print(f"⚠ {msg}")
        warnings += 1
        changes.append(msg)

    if post_throttle.get("currently_throttled"):
        msg = "CPU throttling active"
        print(f"⚠ {msg}")
        warnings += 1
        changes.append(msg)

    if post_throttle.get("soft_temp_limit"):
        msg = "Soft temperature limit reached"
        print(f"⚠ {msg}")
        warnings += 1
        changes.append(msg)

    if warnings == 0:
        print("✓ No hardware throttling detected")

    return ComparisonResult("hardware_throttling", 0, warnings, changes)


def compare_critical_services(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare critical service health.

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with problems/warnings count
    """
    print("\n=== CRITICAL SERVICES COMPARISON ===")

    pre_crit = pre.get("critical_services", {})
    post_crit = post.get("critical_services", {})

    if not pre_crit and not post_crit:
        print("ℹ No critical services data")
        return ComparisonResult("critical_services", 0, 0, [])

    problems = 0
    warnings = 0
    changes = []

    for service, post_data in post_crit.items():
        if post_data.get("active") != "active":
            msg = f"{service}: Not active (state: {post_data.get('active')})"
            print(f"❌ {msg}")
            problems += 1
            changes.append(msg)

        # Check restart count increase
        pre_data = pre_crit.get(service, {})
        pre_restarts = pre_data.get("restarts", 0)
        post_restarts = post_data.get("restarts", 0)
        if post_restarts > pre_restarts:
            msg = (
                f"{service}: Restarted {post_restarts - pre_restarts} times during reboot"
            )
            print(f"⚠ {msg}")
            warnings += 1
            changes.append(msg)

    if problems == 0 and warnings == 0:
        print("✓ All critical services healthy")

    return ComparisonResult("critical_services", problems, warnings, changes)


def compare_config_checksums(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare configuration file checksums.

    Detects unexpected config changes during reboot.

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with warnings count
    """
    print("\n=== CONFIG CHECKSUM COMPARISON ===")

    pre_checksums = pre.get("config_checksums", {})
    post_checksums = post.get("config_checksums", {})

    warnings = 0
    changes = []

    for config_file, pre_hash in pre_checksums.items():
        post_hash = post_checksums.get(config_file, "missing")
        if pre_hash != post_hash:
            msg = f"{config_file}: Checksum changed"
            print(f"⚠ {msg}")
            if verbose:
                print(f"   Pre:  {pre_hash}")
                print(f"   Post: {post_hash}")
            warnings += 1
            changes.append(msg)

    if warnings == 0:
        print("✓ All config checksums unchanged")

    return ComparisonResult("config_checksums", 0, warnings, changes)


def compare_memory_detail(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare memory details (swap usage).

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with warnings count
    """
    print("\n=== MEMORY DETAIL COMPARISON ===")

    post_mem = post.get("memory_detail", {})

    warnings = 0
    changes = []

    post_swap_usage = post_mem.get("swap_usage_percent", 0)
    if post_swap_usage > 50:
        msg = f"Swap usage high: {post_swap_usage}%"
        print(f"⚠ {msg}")
        warnings += 1
        changes.append(msg)
    elif post_swap_usage > 0:
        print(f"ℹ Swap usage: {post_swap_usage}%")

    if warnings == 0:
        print("✓ Memory usage normal")

    return ComparisonResult("memory_detail", 0, warnings, changes)


def compare_cron_jobs(
    pre: dict[str, Any], post: dict[str, Any], verbose: bool = False
) -> ComparisonResult:
    """
    Compare cron jobs.

    Args:
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with warnings count
    """
    print("\n=== CRON JOB COMPARISON ===")

    pre_cron = set(pre.get("cron_jobs", []))
    post_cron = set(post.get("cron_jobs", []))

    removed = pre_cron - post_cron
    added = post_cron - pre_cron

    warnings = 0
    changes = []

    if removed:
        print(f"⚠ Cron jobs removed ({len(removed)}):")
        for job in sorted(removed):
            print(f"   - {job}")
            changes.append(f"removed: {job}")
        warnings += len(removed)

    if added:
        print(f"✅ Cron jobs added ({len(added)}):")
        for job in sorted(added):
            print(f"   + {job}")
            changes.append(f"added: {job}")

    if warnings == 0 and not added:
        print("✓ Cron jobs unchanged")

    return ComparisonResult("cron_jobs", 0, warnings, changes)


def validate_boot_info(post: dict[str, Any], verbose: bool = False) -> ComparisonResult:
    """
    Validate boot completion (post-reboot snapshots only).

    Checks all 13 phases completed and boot duration reasonable.

    Args:
        post: Post-reboot snapshot
        verbose: Enable verbose output

    Returns:
        ComparisonResult with problems/warnings count
    """
    print("\n=== BOOT INFO VALIDATION ===")

    boot_info = post.get("boot_info")

    # Skip if boot_info section is not present in snapshot
    # (boot_info is optional - collected by autostart, not by system-snapshot.sh)
    if boot_info is None:
        print("ℹ Boot info not available (not collected by snapshot)")
        return ComparisonResult("boot_info", 0, 0, [])

    if not boot_info.get("available", True):
        print("ℹ Boot info not available (pre-reboot snapshot)")
        return ComparisonResult("boot_info", 0, 0, [])

    problems = 0
    warnings = 0
    changes = []

    # Check phases completed
    phases = boot_info.get("phases_completed", 0)
    if phases < 13:
        msg = f"Incomplete boot: Only {phases}/13 phases completed"
        print(f"❌ {msg}")
        problems += 1
        changes.append(msg)
    else:
        print("✓ All 13 boot phases completed")

    # Check boot duration
    duration = boot_info.get("boot_duration_seconds", "unknown")
    if duration != "unknown":
        try:
            duration_int = int(duration)
            if duration_int > 300:  # 5 minutes
                msg = f"Boot duration long: {duration_int}s (>{duration_int // 60}m)"
                print(f"⚠ {msg}")
                warnings += 1
                changes.append(msg)
            else:
                print(f"✓ Boot duration normal: {duration_int}s")
        except ValueError:
            pass

    return ComparisonResult("boot_info", problems, warnings, changes)


def generate_json_output(
    results: list[ComparisonResult], pre: dict[str, Any], post: dict[str, Any]
) -> dict[str, Any]:
    """
    Generate JSON output for CI/CD integration.

    Args:
        results: List of comparison results
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot

    Returns:
        JSON-serializable dictionary
    """
    return {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "pre_reboot_time": pre.get("timestamp", "unknown"),
        "post_reboot_time": post.get("timestamp", "unknown"),
        "total_problems": sum(r.problems for r in results),
        "total_warnings": sum(r.warnings for r in results),
        "sections": [asdict(r) for r in results],
        "success": sum(r.problems for r in results) == 0,
    }


def print_summary(
    results: list[ComparisonResult], pre: dict[str, Any], post: dict[str, Any]
) -> None:
    """
    Print categorized summary.

    Args:
        results: List of comparison results
        pre: Pre-reboot snapshot
        post: Post-reboot snapshot
    """
    print("\n" + "=" * 60)
    print("=== SUMMARY ===")
    print("=" * 60)

    print(f"\nPre-reboot:  {pre.get('timestamp', 'unknown')}")
    print(f"Post-reboot: {post.get('timestamp', 'unknown')}")

    # Calculate boot time
    pre_ts = pre.get("timestamp", "")
    post_ts = post.get("timestamp", "")
    if pre_ts and post_ts:
        try:
            # Timestamps are in format "YYYYMMDD-HHMMSS"
            pre_dt = datetime.strptime(pre_ts, "%Y%m%d-%H%M%S")
            post_dt = datetime.strptime(post_ts, "%Y%m%d-%H%M%S")
            diff = post_dt - pre_dt
            total_seconds = int(diff.total_seconds())
            minutes = total_seconds // 60
            seconds = total_seconds % 60
            print(f"Boot time:   {minutes} minutes {seconds} seconds")
        except ValueError:
            pass

    # Categorize issues
    critical = [r for r in results if r.problems > 0]
    warnings = [r for r in results if r.warnings > 0 and r.problems == 0]
    info = [r for r in results if len(r.changes) > 0 and r.problems == 0 and r.warnings == 0]

    if critical:
        print("\n🚨 CRITICAL (must fix):")
        for result in critical:
            print(f"  ❌ {result.section}: {result.problems} problem(s)")
            for change in result.changes[:3]:  # Show first 3
                print(f"     - {change}")

    if warnings:
        print("\n⚠️  WARNINGS (review):")
        for result in warnings:
            print(f"  ⚠ {result.section}: {result.warnings} warning(s)")

    if info:
        print("\nℹ️  INFO:")
        for result in info:
            print(f"  ℹ {result.section}: {len(result.changes)} change(s)")

    # Final verdict
    total_problems = sum(r.problems for r in results)
    total_warnings = sum(r.warnings for r in results)

    print("\n" + "=" * 60)
    if total_problems == 0 and total_warnings == 0:
        print("✅ System recovered successfully after reboot")
    elif total_problems == 0:
        print(f"⚠️  System recovered with {total_warnings} warning(s)")
    else:
        print(f"❌ Found {total_problems} critical issue(s) and {total_warnings} warning(s)")
    print("=" * 60)


def find_latest_snapshots(snapshot_dir: Path) -> tuple[Path | None, Path | None]:
    """
    Find latest pre and post reboot snapshots.

    Args:
        snapshot_dir: Directory containing snapshot files

    Returns:
        Tuple of (pre_file, post_file) or (None, None) on error
    """
    try:
        pre_files = sorted(snapshot_dir.glob("pre-reboot-*.json"), reverse=True)
        post_files = sorted(snapshot_dir.glob("post-reboot-*.json"), reverse=True)

        pre_file = pre_files[0] if pre_files else None
        post_file = post_files[0] if post_files else None

        return pre_file, post_file
    except OSError:
        return None, None


def main() -> int:
    """
    Main entry point.

    Returns:
        Exit code (0=success, 1=critical issues, 2=usage error)
    """
    parser = argparse.ArgumentParser(
        description="Compare pre/post reboot system snapshots",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --auto-latest
  %(prog)s --auto-latest --json
  %(prog)s pre-reboot.json post-reboot.json
  %(prog)s --auto-latest --verbose
        """,
    )
    parser.add_argument(
        "pre_snapshot",
        nargs="?",
        type=Path,
        help="Pre-reboot snapshot file",
    )
    parser.add_argument(
        "post_snapshot",
        nargs="?",
        type=Path,
        help="Post-reboot snapshot file",
    )
    parser.add_argument(
        "--auto-latest",
        action="store_true",
        help="Auto-find latest snapshots",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Verbose output",
    )

    args = parser.parse_args()

    # Determine snapshot directory
    snapshot_dir = Path(os.getenv("SNAPSHOT_DIR", "/var/log/snapshots"))

    # Parse arguments
    if args.auto_latest or (not args.pre_snapshot and not args.post_snapshot):
        # Auto-find latest snapshots
        pre_file, post_file = find_latest_snapshots(snapshot_dir)

        if not pre_file or not post_file:
            print("Error: Could not find pre/post reboot snapshots", file=sys.stderr)
            print(f"Expected location: {snapshot_dir}", file=sys.stderr)
            return 2

    elif args.pre_snapshot and args.post_snapshot:
        pre_file = args.pre_snapshot
        post_file = args.post_snapshot
    else:
        parser.print_help()
        return 2

    if not args.json:
        print("=== SNAPSHOT COMPARISON ===")
        print(f"Pre-reboot:  {pre_file}")
        print(f"Post-reboot: {post_file}")

    # Load snapshots
    pre = load_snapshot(pre_file)
    post = load_snapshot(post_file)

    if not pre or not post:
        print("Error: Could not load snapshots", file=sys.stderr)
        return 1

    # Run all comparisons
    # For JSON output, suppress all print() calls during comparison
    results: list[ComparisonResult] = []

    output_context = contextlib.redirect_stdout(io.StringIO()) if args.json else contextlib.nullcontext()

    with output_context:
        results.append(compare_system(pre, post, args.verbose))
        results.append(compare_services(pre, post, args.verbose))
        results.append(compare_docker(pre, post, args.verbose))
        results.append(compare_network_interfaces(pre, post, args.verbose))
        results.append(compare_usb_devices(pre, post, args.verbose))
        results.append(compare_route_guardian(pre, post, args.verbose))
        results.append(compare_pi_zero_fleet(pre, post, args.verbose))
        results.append(compare_networkmanager(pre, post, args.verbose))
        results.append(compare_wireguard(pre, post, args.verbose))
        results.append(compare_hardware_throttling(pre, post, args.verbose))
        results.append(compare_critical_services(pre, post, args.verbose))
        results.append(compare_config_checksums(pre, post, args.verbose))
        results.append(compare_memory_detail(pre, post, args.verbose))
        results.append(compare_cron_jobs(pre, post, args.verbose))

        # Boot info validation (post-reboot only)
        if post.get("type") == "post-reboot":
            results.append(validate_boot_info(post, args.verbose))

    # Output
    if args.json:
        output = generate_json_output(results, pre, post)
        print(json.dumps(output, indent=2))
    else:
        print_summary(results, pre, post)

    # Exit code
    total_problems = sum(r.problems for r in results)
    return 0 if total_problems == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

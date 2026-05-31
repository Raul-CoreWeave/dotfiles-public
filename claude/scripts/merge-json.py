#!/usr/bin/env python3
"""merge-json.py — merge an optional private overlay JSON into a portable base.

For settings.json: array-aware merge for hooks (grouped by matcher) and
sandbox.network.allowedDomains; object merge for enabledPlugins and
extraKnownMarketplaces.

For installed_plugins.json: simple plugins-object key merge.

The file type is detected from the base filename.

Usage:
    merge-json.py <base.json> <overlay.json> <output.json>

Exit codes:
    0 — merged successfully
    2 — usage error or unknown file type
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def merge_hooks(base_hooks: list, overlay_hooks: list) -> list:
    """Merge two hook arrays by matcher.

    Each entry is {"matcher": str, "hooks": [...]} or {"hooks": [...]} for
    SessionStart. Matching matchers get their hooks arrays concatenated
    (base-first, overlay-appended). Overlay matchers not in base append
    at the end.
    """
    result = [{**e, "hooks": list(e.get("hooks", []))} for e in base_hooks]
    for overlay_entry in overlay_hooks:
        overlay_matcher = overlay_entry.get("matcher")
        for r in result:
            if r.get("matcher") == overlay_matcher:
                r["hooks"].extend(overlay_entry.get("hooks", []))
                break
        else:
            result.append({**overlay_entry, "hooks": list(overlay_entry.get("hooks", []))})
    return result


def merge_settings(base: dict, overlay: dict) -> dict:
    """Merge a private overlay into a portable settings.json base."""
    result = json.loads(json.dumps(base))  # deep copy

    if "hooks" in overlay:
        for event, entries in overlay["hooks"].items():
            base_entries = result.setdefault("hooks", {}).get(event, [])
            result["hooks"][event] = merge_hooks(base_entries, entries)

    if "enabledPlugins" in overlay:
        result.setdefault("enabledPlugins", {}).update(overlay["enabledPlugins"])

    if "extraKnownMarketplaces" in overlay:
        result.setdefault("extraKnownMarketplaces", {}).update(overlay["extraKnownMarketplaces"])

    if "sandbox" in overlay and "network" in overlay["sandbox"]:
        existing = (
            result.setdefault("sandbox", {})
            .setdefault("network", {})
            .setdefault("allowedDomains", [])
        )
        for domain in overlay["sandbox"]["network"].get("allowedDomains", []):
            if domain not in existing:
                existing.append(domain)

    return result


def merge_plugins(base: dict, overlay: dict) -> dict:
    """Merge a private overlay into a portable installed_plugins.json base."""
    result = json.loads(json.dumps(base))
    if "plugins" in overlay:
        result.setdefault("plugins", {}).update(overlay["plugins"])
    return result


def main() -> None:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        sys.exit(2)

    base_path, overlay_path, output_path = (Path(p) for p in sys.argv[1:])
    base = json.loads(base_path.read_text())
    overlay = json.loads(overlay_path.read_text())

    if "settings" in base_path.name:
        merged = merge_settings(base, overlay)
    elif "installed_plugins" in base_path.name:
        merged = merge_plugins(base, overlay)
    else:
        print(f"merge-json: unknown file type: {base_path}", file=sys.stderr)
        sys.exit(2)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(merged, indent=2) + "\n")
    print(f"merged {base_path.name} + {overlay_path.name} → {output_path}")


if __name__ == "__main__":
    main()

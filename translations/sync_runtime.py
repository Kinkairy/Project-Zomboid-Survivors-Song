#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "translations" / "catalog.json"


def load_catalog():
    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    assert data.get("schema") == 1
    assert data.get("languages") == ["EN", "CN", "CH"]
    seen = set()
    for entry in data.get("entries", []):
        key = entry["key"]
        assert key not in seen, f"duplicate key: {key}"
        seen.add(key)
        assert entry.get("reviewed") is True, f"unreviewed key: {key}"
        for locale in ("en", "cn", "ch"):
            assert str(entry.get(locale, "")).strip(), f"empty {locale}: {key}"
        assert "{LOCALE}" in entry["runtime_group"], key
    return data


def rendered_payloads(data):
    grouped: dict[tuple[str, str], dict[str, str]] = defaultdict(dict)
    for entry in data["entries"]:
        for locale in ("EN", "CN", "CH"):
            path = entry["runtime_group"].replace("{LOCALE}", locale)
            grouped[(locale, path)][entry["key"]] = entry[locale.lower()]
    return grouped


def render_json(payload):
    return json.dumps(payload, ensure_ascii=False, indent=4) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    data = load_catalog()
    mismatches = []
    for (_, relative), payload in rendered_payloads(data).items():
        path = ROOT / relative
        expected = render_json(payload)
        if args.write:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(expected, encoding="utf-8")
        elif not path.is_file() or path.read_text(encoding="utf-8") != expected:
            mismatches.append(relative)
    if mismatches:
        raise SystemExit("runtime translation drift: " + ", ".join(sorted(set(mismatches))))
    print(f"Trilingual catalog/runtime parity: PASS ({len(data['entries'])} keys)")


if __name__ == "__main__":
    main()

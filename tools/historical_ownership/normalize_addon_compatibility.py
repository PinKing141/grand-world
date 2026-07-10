#!/usr/bin/env python3
"""Normalize owned histories around the addon's intentionally lightweight parser."""

from __future__ import annotations

import json
import re
import shutil
from datetime import datetime, timezone

import build_manifest as ownership


TRIBAL_TOKEN = re.compile(r"\btribal_owner\b")


def addon_accepts(text: str) -> bool:
    owner_position = text.find("owner =")
    owner_is_line_start = owner_position >= 0 and (
        owner_position == 0 or text[owner_position - 1] == "\n"
    )
    return owner_is_line_start and "tribal_owner" not in text


def main() -> int:
    histories = ownership.load_histories()
    selected = []
    for province_id, (path, fields) in histories.items():
        owner = fields.get("owner", "").upper()
        if owner and not addon_accepts(ownership.read_lossless(path)):
            selected.append((province_id, path, owner))
    if not selected:
        print("All owned province histories already satisfy the addon parser.")
        return 0

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_dir = ownership.BACKUPS / f"{stamp}-addon-normalization"
    backup_dir.mkdir(parents=True, exist_ok=False)
    changes = []
    for province_id, path, owner in selected:
        shutil.copy2(path, backup_dir / path.name)
        original = ownership.read_lossless(path)
        normalized = TRIBAL_TOKEN.sub("tribal_authority", original)
        owner_position = normalized.find("owner =")
        owner_is_line_start = owner_position >= 0 and (
            owner_position == 0 or normalized[owner_position - 1] == "\n"
        )
        if not owner_is_line_start:
            newline = "\r\n" if "\r\n" in normalized else "\n"
            normalized = f"owner = {owner}{newline}" + normalized
        if not addon_accepts(normalized):
            raise ValueError(f"Could not normalize {path.name}")
        path.write_bytes(normalized.encode("utf-8", errors="surrogateescape"))
        changes.append({"province_id": province_id, "file": path.name, "owner": owner})
    (backup_dir / "normalized.json").write_text(
        json.dumps(
            {"created_at_utc": datetime.now(timezone.utc).isoformat(), "changes": changes},
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Normalized {len(changes)} owned histories. Safety copies: {backup_dir.relative_to(ownership.ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

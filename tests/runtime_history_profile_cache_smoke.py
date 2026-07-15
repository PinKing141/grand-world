#!/usr/bin/env python3
"""Validate the generated history-profile cache and its parser contract."""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "runtime_data"))

import build_history_profile_cache as builder  # noqa: E402


def _write_bytes(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


def validate_parser_contract() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        root = Path(temporary_directory)
        countries = root / "countries"
        provinces = root / "provinces"
        _write_bytes(
            countries / "TST - Test Realm.txt",
            b'# comment\ngovernment = monarchy\nprimary_culture = test_culture\n'
            b'religion = "old_faith"\n1444.11.11 = {\nreligion = changed_too_late\n}\n',
        )
        _write_bytes(
            provinces / "7-Test Province.txt",
            b'# legacy byte: \xe9\ncapital = "Test City" # note\nculture = first_culture\n'
            b'culture = ignored_culture\nreligion = test_faith\ntrade_goods = grain\n'
            b'1444.11.11 = { culture = changed_too_late }\n',
        )

        payload = builder.build_payload(countries, provinces)
        assert payload["countries"]["TST"] == {
            "government": "monarchy",
            "primary_culture": "test_culture",
            "religion": "old_faith",
        }
        assert payload["provinces"]["7"] == {
            "capital": "Test City",
            "culture": "first_culture",
            "religion": "test_faith",
            "trade_goods": "grain",
        }


def validate_generated_cache() -> None:
    expected = builder.serialize(builder.build_payload())
    actual = builder.OUTPUT.read_text(encoding="utf-8")
    assert actual == expected, "Generated history-profile cache is stale."
    payload = json.loads(actual)
    assert payload["countries"]["ENG"] == {
        "government": "monarchy",
        "primary_culture": "english",
        "religion": "catholic",
    }
    assert payload["provinces"]["1"] == {
        "capital": "Stockholm",
        "culture": "swedish",
        "religion": "catholic",
        "trade_goods": "grain",
    }


def main() -> int:
    validate_parser_contract()
    validate_generated_cache()
    print("Runtime history profile cache smoke test passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

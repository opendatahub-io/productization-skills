"""
Tests for jira-release-setup/scripts/_next_version.sh

Pure logic — no external dependencies or auth required.
"""

import pathlib
import subprocess

import pytest

SCRIPT = pathlib.Path(__file__).parent.parent / "scripts/_next_version.sh"


def next_version(version: str):
    return subprocess.run(
        [SCRIPT, version],
        capture_output=True,
        text=True,
    )


@pytest.mark.parametrize("version,expected", [
    ("3.4 GA",  "3.4.1"),
    ("3.3.2",   "3.3.3"),
    ("3.0.0",   "3.0.1"),
    ("3.4 EA1", "3.4 EA2"),
    ("3.4 EA2", "3.4 EA3"),
    ("3.4 EA9", "3.4 EA10"),
    ("1.0.0",   "1.0.1"),
    ("2.10.5",  "2.10.6"),
])
def test_valid_versions(version, expected):
    result = next_version(version)
    assert result.returncode == 0, f"Expected exit 0 for '{version}', got {result.returncode}: {result.stderr}"
    assert result.stdout.strip() == expected


@pytest.mark.parametrize("bad_version", [
    "3.4",          # missing qualifier
    "3.4.GA",       # wrong separator
    "bogus",
    "3.4 RC1",      # RC not in spec
    "",
])
def test_invalid_versions_exit_1(bad_version):
    result = next_version(bad_version)
    assert result.returncode == 1, f"Expected exit 1 for '{bad_version}', got {result.returncode}"
    assert "ERROR" in result.stderr or "Usage" in result.stderr

"""
Tests for ANSI escape sequence stripping in get_issue.sh and search_issues.sh.

acli writes its loading spinner to stdout, prefixing the JSON with ANSI
control sequences. Both scripts must strip these before piping to jq.
"""

import json
import os
import pathlib
import subprocess

import pytest

_SKILL_ROOT = pathlib.Path(__file__).parent.parent
GET_ISSUE = _SKILL_ROOT / "scripts/get_issue.sh"

# Realistic acli spinner output: ESC sequences + carriage returns before the JSON
ANSI_PREFIX = (
    "\r\x1b[2K\x1b[?25l Fetching AIPCC-7229...\r\x1b[2K"
    "\x1b[1;32m\u2714\x1b[0m Done\r\n"
)
CLEAN_JSON = json.dumps({
    "key": "AIPCC-7229",
    "fields": {
        "summary": "Test issue for ANSI stripping",
        "status": {"name": "Open"},
    },
})


@pytest.fixture
def acli_ansi_view(jira_env, monkeypatch, tmp_path):
    """Override the stub acli so workitem view emits ANSI sequences before JSON."""
    ansi_file = tmp_path / "acli_view_output.txt"
    ansi_file.write_text(ANSI_PREFIX + CLEAN_JSON + "\n")
    monkeypatch.setenv("ACLI_WORKITEM_VIEW_FILE", str(ansi_file))
    return jira_env


def test_get_issue_strips_ansi_and_returns_valid_json(acli_ansi_view):
    result = subprocess.run(
        [GET_ISSUE, "AIPCC-7229"],
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )
    assert result.returncode == 0, f"get_issue.sh failed: {result.stderr}"
    data = json.loads(result.stdout)
    assert data["key"] == "AIPCC-7229"
    assert data["fields"]["summary"] == "Test issue for ANSI stripping"


def test_get_issue_no_ansi_in_output(acli_ansi_view):
    result = subprocess.run(
        [GET_ISSUE, "AIPCC-7229"],
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )
    assert result.returncode == 0, f"get_issue.sh failed: {result.stderr}"
    assert "\x1b" not in result.stdout
    assert "\r" not in result.stdout


def test_get_issue_pure_json_passes_through(jira_env):
    """When acli returns clean JSON (no ANSI), output must still be valid JSON."""
    result = subprocess.run(
        [GET_ISSUE, "TEST-1"],
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )
    assert result.returncode == 0
    data = json.loads(result.stdout)
    assert "key" in data

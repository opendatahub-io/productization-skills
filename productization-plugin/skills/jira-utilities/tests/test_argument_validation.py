"""
Tests for argument validation across jira-utilities scripts.

All checks here run before ensure_auth is called, so no stub acli or
network access is required — just the JIRA_* env vars.
"""

import os
import pathlib
import subprocess

import pytest

_SKILL_ROOT = pathlib.Path(__file__).parent.parent
_SCRIPTS = _SKILL_ROOT / "scripts"

SEARCH  = _SCRIPTS / "search_issues.sh"
GET     = _SCRIPTS / "get_issue.sh"
COMMENT = _SCRIPTS / "comment_issue.sh"
ASSIGN  = _SCRIPTS / "assign_sprint.sh"
TRANS   = _SCRIPTS / "transition_issue.sh"


def run(script, *args):
    return subprocess.run(
        [script, *args],
        capture_output=True,
        text=True,
        env=os.environ | {
            "JIRA_SITE": "test.atlassian.net",
            "JIRA_EMAIL": "test@example.com",
            "JIRA_TOKEN": "test-token",
        },
    )


# ---------------------------------------------------------------------------
# search_issues.sh
# ---------------------------------------------------------------------------

def test_search_no_args_exits_1():
    r = run(SEARCH)
    assert r.returncode == 1

def test_search_mutually_exclusive_exits_1():
    r = run(SEARCH, "--search", "foo", "--epic", "PROJ-1")
    assert r.returncode == 1

def test_search_invalid_format_exits_1():
    r = run(SEARCH, "project = PROJ", "--format", "xml")
    assert r.returncode == 1

def test_search_parent_alias_accepted():
    """--parent must be accepted as an alias for --epic (validation only)."""
    # This will fail at ensure_auth (no real acli), but must NOT fail at arg parsing
    r = run(SEARCH, "--parent", "PROJ-1")
    assert "Unknown option" not in r.stderr


# ---------------------------------------------------------------------------
# get_issue.sh
# ---------------------------------------------------------------------------

def test_get_no_args_exits_1():
    r = run(GET)
    assert r.returncode == 1

@pytest.mark.parametrize("bad_key", [
    "proj-123",    # lowercase
    "123-PROJ",    # reversed
    "PROJ",        # no number
    "PROJ-",       # trailing dash
])
def test_get_invalid_key_exits_1(bad_key):
    r = run(GET, bad_key)
    assert r.returncode == 1
    assert "Invalid issue key" in r.stderr

def test_get_valid_key_format_accepted():
    """A valid key format must pass validation (may fail later at auth)."""
    r = run(GET, "PROJ-123")
    assert "Invalid issue key" not in r.stderr


# ---------------------------------------------------------------------------
# comment_issue.sh
# ---------------------------------------------------------------------------

def test_comment_no_args_exits_1():
    r = run(COMMENT)
    assert r.returncode == 1

def test_comment_invalid_key_exits_1():
    r = run(COMMENT, "bad-key", "some comment")
    assert r.returncode == 1

def test_comment_missing_body_exits_1():
    r = run(COMMENT, "PROJ-123")
    assert r.returncode == 1


# ---------------------------------------------------------------------------
# assign_sprint.sh
# ---------------------------------------------------------------------------

def test_assign_no_args_exits_1():
    r = run(ASSIGN)
    assert r.returncode == 1

def test_assign_non_numeric_sprint_exits_1():
    r = run(ASSIGN, "not-a-number", "PROJ-1")
    assert r.returncode == 1

def test_assign_missing_keys_exits_1():
    r = run(ASSIGN, "12345")
    assert r.returncode == 1


# ---------------------------------------------------------------------------
# transition_issue.sh
# ---------------------------------------------------------------------------

def test_transition_no_args_exits_1():
    r = run(TRANS)
    assert r.returncode == 1

def test_transition_invalid_key_exits_1():
    r = run(TRANS, "bad", "--list")
    assert r.returncode == 1

def test_transition_no_mode_exits_1():
    r = run(TRANS, "PROJ-123")
    assert r.returncode == 1

def test_transition_unknown_flag_exits_1():
    r = run(TRANS, "PROJ-123", "--close")
    assert r.returncode == 1

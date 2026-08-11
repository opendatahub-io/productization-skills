"""
Shared fixtures for jira-utilities skill tests.

Environment setup:
- All scripts need JIRA_SITE, JIRA_EMAIL, JIRA_TOKEN env vars.
- `ensure_auth` greps ~/.config/acli/ — we create a fake config dir.
- A stub `acli` binary is placed first in PATH to avoid real network calls.
  Set ACLI_WORKITEM_VIEW_FILE to control what `workitem view` returns.
"""

import os
import pathlib
import textwrap

import pytest

SKILL_ROOT = pathlib.Path(__file__).parent.parent
JIRA_UTILS = SKILL_ROOT / "scripts"

# 2026-04-21 00:00:00 UTC — used as "today" in jq pipeline tests
TODAY_EPOCH = 1776729600


@pytest.fixture
def jira_env(tmp_path, monkeypatch):
    """
    Complete environment for running jira-utilities scripts without network access.

    - Stubs acli so auth and workitem view succeed without Jira credentials.
    - Creates ~/.config/acli/ so ensure_auth's grep check passes.
    - Sets JIRA_SITE/EMAIL/TOKEN env vars.

    To control what `acli workitem view` returns, set ACLI_WORKITEM_VIEW_FILE
    via monkeypatch.setenv() in the individual test.
    """
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()

    jq_shim = bin_dir / "jq"
    jq_shim.write_text(textwrap.dedent("""\
        #!/usr/bin/env python3
        import sys, json
        import jq as _jq
        expr = sys.argv[1] if len(sys.argv) > 1 else "."
        data = sys.stdin.read()
        for item in _jq.compile(expr).input_text(data).all():
            print(json.dumps(item, ensure_ascii=False))
    """))
    jq_shim.chmod(0o755)

    stub = bin_dir / "acli"
    stub.write_text(textwrap.dedent("""\
        #!/usr/bin/env bash
        case "$*" in
            *"auth login"*)
                exit 0
                ;;
            *"workitem view"*)
                if [[ -n "${ACLI_WORKITEM_VIEW_FILE:-}" ]]; then
                    cat "$ACLI_WORKITEM_VIEW_FILE"
                else
                    printf '{"key":"TEST-1","fields":{"summary":"stub issue","status":{"name":"Open"}}}'
                fi
                ;;
            *"workitem search"*)
                echo "[]"
                ;;
            *)
                echo "[]"
                ;;
        esac
    """))
    stub.chmod(0o755)

    # Fake acli config so ensure_auth's `grep -qrs "$site" ~/.config/acli/` succeeds
    acli_config = tmp_path / ".config" / "acli"
    acli_config.mkdir(parents=True)
    (acli_config / "config").write_text("site: test.atlassian.net\n")

    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")
    monkeypatch.setenv("JIRA_SITE", "test.atlassian.net")
    monkeypatch.setenv("JIRA_EMAIL", "test@example.com")
    monkeypatch.setenv("JIRA_TOKEN", "test-token-abc")

    return tmp_path

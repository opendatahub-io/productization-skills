"""Shared paths for jira-release-setup skill tests."""

import pathlib

SKILL_ROOT = pathlib.Path(__file__).parent.parent
RELEASE_SETUP = SKILL_ROOT / "scripts"

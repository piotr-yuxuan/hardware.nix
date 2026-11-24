"""Tests for the Claude Code marketplace in config/claude-code-marketplace/.

Claude Code gives a file extension to one language server only, and leaves
any other plugin that claims it unused, with no more than a warning in its
plugin list; the marketplace must therefore never offer two servers for one
extension, except for the pair that a project chooses between.
"""

from __future__ import annotations

import json
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from pathlib import Path

# A dbt project enables dbt-lsp-plus and disables yaml-language-server, both
# of which claim YAML; elsewhere the user scope keeps the opposite.
ALTERNATIVES = {"dbt-lsp-plus", "yaml-language-server"}


@pytest.fixture(scope="module")
def marketplace(scripts_dir: Path) -> Path:
    """Return the marketplace's directory."""
    return scripts_dir.parent / "config" / "claude-code-marketplace"


def manifests(marketplace: Path) -> dict[str, dict]:
    """Read every plugin's manifest, keyed by its directory's name."""
    return {
        path.parent.parent.name: json.loads(path.read_text())
        for path in marketplace.glob("plugins/*/.claude-plugin/plugin.json")
    }


def test_entries_match_plugin_directories(marketplace: Path) -> None:
    """Each entry names a plugin directory of its own name, and every one is listed."""
    entries = json.loads((marketplace / ".claude-plugin/marketplace.json").read_text())
    listed = {entry["name"]: entry["source"] for entry in entries["plugins"]}
    plugins = manifests(marketplace)
    assert listed == {name: f"./plugins/{name}" for name in plugins}
    assert all(manifest["name"] == name for name, manifest in plugins.items())


def test_each_extension_has_one_server(marketplace: Path) -> None:
    """No two plugins claim an extension, but for the declared alternatives."""
    claims: dict[str, set[str]] = {}
    for name, manifest in manifests(marketplace).items():
        for server in manifest.get("lspServers", {}).values():
            for extension in server["extensionToLanguage"]:
                claims.setdefault(extension, set()).add(name)
    shared = {ext: names for ext, names in claims.items() if len(names) > 1}
    assert all(names == ALTERNATIVES for names in shared.values()), shared


def test_extensions_are_lower_case(marketplace: Path) -> None:
    """Claude Code looks a file up by its extension in lower case."""
    for manifest in manifests(marketplace).values():
        for server in manifest.get("lspServers", {}).values():
            for extension in server["extensionToLanguage"]:
                assert extension == extension.lower(), extension
                assert extension.startswith("."), extension

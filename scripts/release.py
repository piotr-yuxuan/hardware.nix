#!/usr/bin/env python3
"""Release the commit that the pipeline of the public repository has checked.

The next version is written to `.version` by a commit made through GitHub's
API, which GitHub signs. That commit gets a plain tag and a release whose notes
are computed from the trees; the channel branch moves to it and GitHub records
a deployment. The version and the notes are pure functions; the rest reads git
and sends requests with `gh api`.

It needs Python 3.11 or later, git and gh, and runs at the root of a checkout
of the commit, with every tag.
"""

from __future__ import annotations

import base64
import json
import os
import re
import subprocess
import sys
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path
from typing import TYPE_CHECKING, NamedTuple

if TYPE_CHECKING:
    from collections.abc import Collection, Mapping, Sequence

VERSION_FILE = ".version"
NUMBERS = r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
VERSION_TEXT = re.compile(NUMBERS + r"\n", re.ASCII)
VERSION_TAG = re.compile(NUMBERS, re.ASCII)
# The parts of a version, in the order of its numbers.
BUMPS = ("major", "minor", "patch")
# The branch that only moves to a released commit, and the deployment environment.
CHANNEL = "refs/heads/stable"
ENVIRONMENT = "release"
# What the runner says about the job, and the shape each value must have.
SETTINGS = {
    "GITHUB_REPOSITORY": re.compile(r"[\w.-]+/[\w.-]+", re.ASCII),
    "GITHUB_REF": re.compile(r"refs/heads/[\w./-]+", re.ASCII),
    "GITHUB_SHA": re.compile(r"[0-9a-f]{40}"),
    "GITHUB_SERVER_URL": re.compile(r"https://[\w.-]+", re.ASCII),
}
COMMAND_TIMEOUT_SECONDS = 120
VERSION_COMMIT = """
mutation ($input: CreateCommitOnBranchInput!) {
  createCommitOnBranch(input: $input) { commit { oid } }
}
"""


class ReleaseError(Exception):
    """An input that cannot be trusted as written, or a command that failed."""


class Previous(NamedTuple):
    """The release before this one, as the notes compare with it."""

    lock: str
    # What `git diff --name-status` says since then: a status letter and a path.
    changes: Sequence[tuple[str, str]]
    compare: str


def next_version(text: str | None, tags: Collection[str], bump: str) -> str:
    """Decide the version to release, from the version file and the bump asked.

    Without a file this is the first release, 0.0.0 whatever the bump.
    Otherwise the part that `bump` names is raised and the parts after it go
    back to zero. A version that already has its tag is never given twice.
    """
    if bump not in BUMPS:
        message = f"bump {bump!r} is not one of {', '.join(BUMPS)}"
        raise ReleaseError(message)
    numbers = [0, 0, 0]
    if text is not None:
        current = VERSION_TEXT.fullmatch(text)
        if current is None:
            message = (
                f"{VERSION_FILE} holds {text!r}, not MAJOR.MINOR.PATCH and a newline"
            )
            raise ReleaseError(message)
        raised = BUMPS.index(bump)
        numbers = [int(number) for number in current.groups()]
        numbers = [*numbers[:raised], numbers[raised] + 1, *[0] * (2 - raised)]
    version = ".".join(str(number) for number in numbers)
    if version in tags:
        message = f"the tag {version} already exists"
        raise ReleaseError(message)
    return version


def locked_inputs(lock: str) -> dict[str, str]:
    """Describe each direct input of a flake lock: its revision and its date."""
    try:
        document = json.loads(lock)
        nodes = document["nodes"]
        described = {}
        for name, node in nodes[document["root"]]["inputs"].items():
            # A list is an input that follows another one: it has no lock of its own.
            if isinstance(node, str):
                locked = nodes[node]["locked"]
                revision = locked["rev" if "rev" in locked else "narHash"][:12]
                moment = locked.get("lastModified")
                described[name] = f"`{revision}`" + (
                    f" of {datetime.fromtimestamp(moment, UTC).date()}"
                    if moment is not None
                    else ""
                )
    except (
        ValueError,
        LookupError,
        TypeError,
        AttributeError,
        ArithmeticError,
        OSError,
    ) as error:
        message = f"flake.lock is not a lock file this tool can read: {error!r}"
        raise ReleaseError(message) from error
    return described


def release_notes(new_lock: str, previous: Previous | None) -> str:
    """Write the notes of a release in Markdown, from the trees alone.

    A first release lists its flake inputs. A later one lists the inputs that
    moved, counts the files added, changed and removed in each top-level area,
    and links to the comparison with the release before it.
    """
    new = locked_inputs(new_lock)
    if previous is None:
        inputs = [f"- `{name}`: {new[name]}" for name in sorted(new)]
        return "\n".join(["First release.", "", "Flake inputs:", "", *inputs, ""])
    old = locked_inputs(previous.lock)
    moved = [
        f"- `{name}`: {old.get(name, 'absent')}, now {new.get(name, 'absent')}"
        for name in sorted(old.keys() | new.keys())
        if old.get(name) != new.get(name)
    ]
    columns = {"A": "added", "D": "removed"}
    counts = Counter(
        (path.split("/")[0], columns.get(status, "changed"))
        for status, path in previous.changes
    )
    rows = [
        f"| `{area}` | {counts[area, 'added']} | {counts[area, 'changed']} "
        f"| {counts[area, 'removed']} |"
        for area in sorted({area for area, _ in counts})
    ]
    sections = []
    if moved:
        sections += ["Flake inputs that moved:", "", *moved, ""]
    if rows:
        heading = (
            "| Area | Added | Changed | Removed |\n|------|------:|--------:|--------:|"
        )
        sections += [heading, *rows, ""]
    if not sections:
        sections = ["No file and no flake input changed.", ""]
    return "\n".join([*sections, f"Full difference: {previous.compare}", ""])


def run(*command: str, stdin: bytes = b"") -> bytes:
    """Run a command and return what it prints; any failure stops the release."""
    result = subprocess.run(
        command,
        input=stdin,
        capture_output=True,
        check=False,
        timeout=COMMAND_TIMEOUT_SECONDS,
    )
    if result.returncode != 0:
        reason = result.stderr.decode(errors="replace").strip()
        message = f"{' '.join(command)} failed: {reason}"
        raise ReleaseError(message)
    return result.stdout


def api(method: str, path: str, body: object = None) -> object:
    """Send one request to GitHub with `gh api` and return its parsed reply."""
    arguments, sent = ["gh", "api", "--method", method, path], b""
    if body is not None:
        arguments, sent = [*arguments, "--input", "-"], json.dumps(body).encode()
    reply = run(*arguments, stdin=sent)
    try:
        return json.loads(reply)
    except ValueError as error:
        message = f"{method} {path}: the reply is not JSON"
        raise ReleaseError(message) from error


def dig(reply: object, *keys: str) -> str:
    """Follow keys into a parsed reply, down to a text or a number."""
    found = reply
    for key in keys:
        found = found.get(key) if isinstance(found, dict) else None
    if not isinstance(found, str | int):
        message = f"unexpected reply: no {'.'.join(keys)} in {reply!r}"
        raise ReleaseError(message)
    return str(found)


def release(env: Mapping[str, str]) -> str:
    """Release the checked commit, and say what was done.

    Nothing is sent when the branch has moved on: the run of its new head
    releases. The steps are not atomic. A failure after the version commit
    leaves a version without a tag, and a later run releases under the next one.
    """
    malformed = [
        name
        for name, shape in SETTINGS.items()
        if not shape.fullmatch(env.get(name, ""))
    ]
    if malformed:
        message = f"missing or malformed in the environment: {', '.join(malformed)}"
        raise ReleaseError(message)
    repository, ref, commit, server = (env[name] for name in SETTINGS)
    branches = api("GET", f"repos/{repository}/git/matching-refs/heads/")
    if not isinstance(branches, list):
        message = f"unexpected reply: the branches are not a list but {branches!r}"
        raise ReleaseError(message)
    heads = {dig(head, "ref"): dig(head, "object", "sha") for head in branches}
    if heads.get(ref) != commit:
        return f"::notice::No release: {ref} has moved on from {commit}."
    tags = run("git", "tag", "--list").decode().split()
    written = Path(VERSION_FILE)
    version = next_version(
        written.read_text(encoding="utf-8") if written.exists() else None,
        tags,
        env.get("BUMP") or "patch",
    )
    released = sorted(
        tuple(int(number) for number in found.groups())
        for found in map(VERSION_TAG.fullmatch, tags)
        if found
    )
    previous = None
    if released:
        before = ".".join(str(number) for number in released[-1])
        difference = ("diff", "--name-status", "--no-renames", "-z", before, commit)
        fields = run("git", *difference).decode().split("\0")[:-1]
        previous = Previous(
            run("git", "show", f"{before}:flake.lock").decode(),
            list(zip(fields[::2], fields[1::2], strict=True)),
            f"{server}/{repository}/compare/{before}...{version}",
        )
    notes = release_notes(Path("flake.lock").read_text(encoding="utf-8"), previous)
    commit_input = {
        "branch": {
            "repositoryNameWithOwner": repository,
            "branchName": ref.removeprefix("refs/heads/"),
        },
        "expectedHeadOid": commit,
        "message": {"headline": f"Version {version}", "body": "[skip ci]"},
        "fileChanges": {
            "additions": [
                {
                    "path": VERSION_FILE,
                    "contents": base64.b64encode(f"{version}\n".encode()).decode(),
                }
            ]
        },
    }
    made = api(
        "POST",
        "graphql",
        {"query": VERSION_COMMIT, "variables": {"input": commit_input}},
    )
    oid = dig(made, "data", "createCommitOnBranch", "commit", "oid")
    refs = f"repos/{repository}/git/refs"
    api("POST", refs, {"ref": f"refs/tags/{version}", "sha": oid})
    api(
        "POST",
        f"repos/{repository}/releases",
        {"tag_name": version, "name": f"Version {version}", "body": notes},
    )
    if CHANNEL in heads:
        channel = f"{refs}/{CHANNEL.removeprefix('refs/')}"
        api("PATCH", channel, {"sha": oid, "force": False})
    else:
        api("POST", refs, {"ref": CHANNEL, "sha": oid})
    deployment = api(
        "POST",
        f"repos/{repository}/deployments",
        # Without these two, GitHub would merge the default branch into the tag
        # and wait for checks that a version commit never gets.
        {
            "ref": version,
            "environment": ENVIRONMENT,
            "auto_merge": False,
            "required_contexts": [],
        },
    )
    api(
        "POST",
        f"repos/{repository}/deployments/{dig(deployment, 'id')}/statuses",
        {
            "state": "success",
            "environment_url": f"{server}/{repository}/releases/tag/{version}",
        },
    )
    return f"Released {version} as {oid}."


def main() -> int:
    """Run one release: 0 when released or when the branch moved on, 2 otherwise."""
    try:
        sys.stdout.write(release(os.environ) + "\n")
    except (ReleaseError, subprocess.TimeoutExpired, OSError, UnicodeError) as error:
        sys.stderr.write(f"release.py: {error}\n")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

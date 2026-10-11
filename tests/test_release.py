"""Acceptance tests for scripts/release.py.

Each test states one requirement of a release of the public repository and is
aimed at a plausible wrong implementation. No request leaves the machine: a
fake ``gh`` records what the script would send.
"""

from __future__ import annotations

import base64
import json
import re
from datetime import UTC, datetime
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path
    from types import ModuleType

# The exit statuses that the command line promises.
DONE, STOPPED = 0, 2
API = "repos/example/config"
SITE = "https://github.example/example/config"
BRANCHES = f"GET {API}/git/matching-refs/heads/"
VERSION_COMMIT = "c" * 40
STALE = "5" * 40
# What GitHub answers to the requests whose reply the script reads.
MADE = {"data": {"createCommitOnBranch": {"commit": {"oid": VERSION_COMMIT}}}}
ANSWERS = {"POST graphql": MADE, f"POST {API}/deployments": {"id": 42}}
SEPTEMBER = int(datetime(2026, 9, 30, 12, tzinfo=UTC).timestamp())
OCTOBER = int(datetime(2026, 10, 7, 12, tzinfo=UTC).timestamp())


def lock(**inputs: dict[str, object]) -> str:
    """Write a flake lock whose direct inputs are locked as given."""
    nodes = {name: {"locked": locked} for name, locked in inputs.items()}
    nodes["root"] = {"inputs": {name: name for name in inputs}}
    return json.dumps({"nodes": nodes, "root": "root", "version": 7})


OLD_LOCK = lock(
    nixpkgs={"rev": "a" * 40, "lastModified": SEPTEMBER},
    disko={"rev": "d" * 40, "lastModified": SEPTEMBER},
)
NEW_LOCK = lock(
    nixpkgs={"rev": "b" * 40, "lastModified": OCTOBER},
    disko={"rev": "d" * 40, "lastModified": SEPTEMBER},
)


def branches(**heads: str) -> list[dict[str, object]]:
    """Answer the request for the branches of the repository and their heads."""
    return [
        {"ref": f"refs/heads/{name}", "object": {"sha": commit}}
        for name, commit in heads.items()
    ]


@pytest.mark.parametrize(
    ("text", "tags", "bump", "version"),
    [
        pytest.param(None, [], "patch", "0.0.0", id="first release"),
        pytest.param(None, [], "minor", "0.0.0", id="first release, minor asked"),
        pytest.param(None, [], "major", "0.0.0", id="first release, major asked"),
        pytest.param("0.0.0\n", ["0.0.0"], "patch", "0.0.1", id="second release"),
        pytest.param("0.1.9\n", ["0.1.9"], "patch", "0.1.10", id="nine to ten"),
        pytest.param("1.0.0\n", ["0.9.4"], "patch", "1.0.1", id="file above the tags"),
        pytest.param("0.1.9\n", ["0.1.9"], "minor", "0.2.0", id="new minor line"),
        pytest.param("0.1.9\n", ["0.1.9"], "major", "1.0.0", id="new major line"),
    ],
)
def test_next_version_raises_the_part_that_the_bump_names(
    release: ModuleType, text: str | None, tags: list[str], bump: str, version: str
) -> None:
    """The first release is 0.0.0; later the named part rises and the rest resets."""
    assert release.next_version(text, tags, bump) == version


@pytest.mark.parametrize(
    ("text", "tags", "bump"),
    [
        pytest.param("", [], "patch", id="empty file"),
        pytest.param("1.0\n", [], "patch", id="two numbers"),
        pytest.param("v1.0.0\n", [], "patch", id="letter before the numbers"),
        pytest.param("1.0.0-rc1\n", [], "patch", id="suffix"),
        pytest.param("01.0.0\n", [], "patch", id="leading zero"),
        pytest.param("1\u0663.0.0\n", [], "patch", id="digit that is not ASCII"),
        pytest.param("1.0.0\n2.0.0\n", [], "patch", id="two lines"),
        pytest.param("1.0.0", [], "patch", id="no line break at the end"),
        pytest.param("0.1.9\n", ["0.1.10"], "patch", id="tag of the result exists"),
        pytest.param(None, ["0.0.0"], "patch", id="tag of the first release exists"),
        pytest.param("0.1.9\n", [], "Minor", id="bump in another case"),
        pytest.param("0.1.9\n", [], "build", id="bump that names no part"),
    ],
)
def test_next_version_refuses_what_it_cannot_trust(
    release: ModuleType, text: str | None, tags: list[str], bump: str
) -> None:
    """A malformed file, an unknown bump or a version already tagged stops a release."""
    with pytest.raises(release.ReleaseError):
        release.next_version(text, tags, bump)


def test_notes_of_a_first_release_list_every_input(release: ModuleType) -> None:
    """With nothing to compare with, the notes say what the flake is locked to."""
    first = lock(
        nixpkgs={"rev": "b" * 40, "lastModified": OCTOBER},
        preset={"narHash": "sha256-QaQZfXNTpXhnm"},
    )

    assert release.release_notes(first, None) == (
        "First release.\n"
        "\n"
        "Flake inputs:\n"
        "\n"
        "- `nixpkgs`: `bbbbbbbbbbbb` of 2026-10-07\n"
        "- `preset`: `sha256-QaQZf`\n"
    )


def test_notes_name_what_moved_and_count_the_files_by_area(
    release: ModuleType,
) -> None:
    """An input that stayed is not listed, and each area has one row of the table."""
    changes = [
        ("A", "docs/how-to/new.org"),
        ("M", "docs/reference/layout.org"),
        ("M", "flake.lock"),
        ("D", "scripts/old.sh"),
    ]
    previous = release.Previous(OLD_LOCK, changes, f"{SITE}/compare/0.0.0...0.0.1")

    assert release.release_notes(NEW_LOCK, previous) == (
        "Flake inputs that moved:\n"
        "\n"
        "- `nixpkgs`: `aaaaaaaaaaaa` of 2026-09-30, now `bbbbbbbbbbbb` of 2026-10-07\n"
        "\n"
        "| Area | Added | Changed | Removed |\n"
        "|------|------:|--------:|--------:|\n"
        "| `docs` | 1 | 1 | 0 |\n"
        "| `flake.lock` | 0 | 1 | 0 |\n"
        "| `scripts` | 0 | 0 | 1 |\n"
        "\n"
        f"Full difference: {SITE}/compare/0.0.0...0.0.1\n"
    )


def test_notes_name_an_input_that_appears_or_disappears(release: ModuleType) -> None:
    """Adding or dropping an input is a move too."""
    old = lock(disko={"rev": "d" * 40, "lastModified": SEPTEMBER})
    new = lock(nixpkgs={"rev": "b" * 40, "lastModified": OCTOBER})
    previous = release.Previous(old, [], f"{SITE}/compare/0.0.0...0.0.1")

    assert release.release_notes(new, previous) == (
        "Flake inputs that moved:\n"
        "\n"
        "- `disko`: `dddddddddddd` of 2026-09-30, now absent\n"
        "- `nixpkgs`: absent, now `bbbbbbbbbbbb` of 2026-10-07\n"
        "\n"
        f"Full difference: {SITE}/compare/0.0.0...0.0.1\n"
    )


def test_notes_say_so_when_nothing_changed(release: ModuleType) -> None:
    """A release of an already released tree has neither list nor table."""
    previous = release.Previous(NEW_LOCK, [], f"{SITE}/compare/0.0.1...0.1.0")

    assert release.release_notes(NEW_LOCK, previous) == (
        "No file and no flake input changed.\n"
        "\n"
        f"Full difference: {SITE}/compare/0.0.1...0.1.0\n"
    )


@pytest.mark.parametrize(
    "text",
    [
        pytest.param("not JSON", id="not JSON"),
        pytest.param("{}", id="no nodes"),
        pytest.param('{"nodes": {"root": {}}, "root": "root"}', id="no inputs"),
        pytest.param(lock(nixpkgs={}), id="input without revision or hash"),
        pytest.param(lock(nixpkgs={"rev": 1}), id="revision that is not a text"),
        pytest.param(
            lock(nixpkgs={"rev": "b" * 40, "lastModified": "soon"}),
            id="date that is not a number",
        ),
    ],
)
def test_notes_refuse_a_lock_file_they_cannot_read(
    release: ModuleType, text: str
) -> None:
    """A lock file of another shape stops the release: no guess is published."""
    with pytest.raises(release.ReleaseError):
        release.release_notes(text, None)


def test_first_release_commits_tags_publishes_and_deploys_in_this_order(
    release: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    release_job: Callable[..., str],
    fake_gh: Callable[..., Callable[[], list[list[object]]]],
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Without version file or channel: version 0.0.0, and the channel is created."""
    commit = release_job(git_repo("checkout", {"flake.lock": NEW_LOCK.encode()}))
    sent = fake_gh({BRANCHES: branches(master=commit), **ANSWERS})

    status = release.main()

    first, made, *rest = sent()
    assert status == DONE
    assert capsys.readouterr().out == f"Released 0.0.0 as {VERSION_COMMIT}.\n"
    assert first == ["GET", f"{API}/git/matching-refs/heads/", None]
    assert made[:2] == ["POST", "graphql"]
    assert "createCommitOnBranch" in made[2]["query"]
    assert made[2]["variables"]["input"] == {
        "branch": {"repositoryNameWithOwner": "example/config", "branchName": "master"},
        "expectedHeadOid": commit,
        "message": {"headline": "Version 0.0.0", "body": "[skip ci]"},
        "fileChanges": {
            "additions": [
                {"path": ".version", "contents": base64.b64encode(b"0.0.0\n").decode()}
            ]
        },
    }
    notes = release.release_notes(NEW_LOCK, None)
    assert rest == [
        ["POST", f"{API}/git/refs", {"ref": "refs/tags/0.0.0", "sha": VERSION_COMMIT}],
        [
            "POST",
            f"{API}/releases",
            {"tag_name": "0.0.0", "name": "Version 0.0.0", "body": notes},
        ],
        [
            "POST",
            f"{API}/git/refs",
            {"ref": "refs/heads/stable", "sha": VERSION_COMMIT},
        ],
        [
            "POST",
            f"{API}/deployments",
            {
                "ref": "0.0.0",
                "environment": "release",
                "auto_merge": False,
                "required_contexts": [],
            },
        ],
        [
            "POST",
            f"{API}/deployments/42/statuses",
            {"state": "success", "environment_url": f"{SITE}/releases/tag/0.0.0"},
        ],
    ]


def test_later_release_compares_with_the_highest_tag_and_moves_the_channel(
    release: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    commit: Callable[..., None],
    release_job: Callable[..., str],
    fake_gh: Callable[..., Callable[[], list[list[object]]]],
) -> None:
    """Ten comes after nine: the notes cover what changed since 0.0.10 only."""
    files = {"flake.lock": OLD_LOCK.encode(), ".version": b"0.0.9\n"}
    repository = git_repo("checkout", files)
    release.run("git", "-C", str(repository), "tag", "0.0.9")
    commit(repository, {"since-nine.txt": b"x\n", ".version": b"0.0.10\n"})
    release.run("git", "-C", str(repository), "tag", "0.0.10")
    release.run("git", "-C", str(repository), "tag", "not-a-version")
    commit(repository, {"flake.lock": NEW_LOCK.encode(), "docs/new.org": b"x\n"})
    head = release_job(repository)
    sent = fake_gh({BRANCHES: branches(master=head, stable=STALE), **ANSWERS})

    status = release.main()

    changes = [("A", "docs/new.org"), ("M", "flake.lock")]
    previous = release.Previous(OLD_LOCK, changes, f"{SITE}/compare/0.0.10...0.0.11")
    _, made, _, published, channel, *_ = sent()
    assert status == DONE
    assert made[2]["variables"]["input"]["message"]["headline"] == "Version 0.0.11"
    assert published[2]["body"] == release.release_notes(NEW_LOCK, previous)
    assert channel == [
        "PATCH",
        f"{API}/git/refs/heads/stable",
        {"sha": VERSION_COMMIT, "force": False},
    ]


# What the version file 0.1.9 becomes for each bump that the environment may hold.
RAISED = {None: "0.1.10", "": "0.1.10", "patch": "0.1.10", "minor": "0.2.0"}


@pytest.mark.parametrize("bump", RAISED)
def test_bump_comes_from_the_environment_and_is_a_patch_by_default(
    release: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    release_job: Callable[..., str],
    fake_gh: Callable[..., Callable[[], list[list[object]]]],
    bump: str | None,
) -> None:
    """A manual run names the part to raise; a push names none."""
    files = {"flake.lock": NEW_LOCK.encode(), ".version": b"0.1.9\n"}
    commit = release_job(git_repo("checkout", files), BUMP=bump)
    sent = fake_gh({BRANCHES: branches(master=commit), **ANSWERS})

    release.main()

    message = sent()[1][2]["variables"]["input"]["message"]
    assert message["headline"] == f"Version {RAISED[bump]}"


def test_no_request_is_sent_once_the_branch_has_moved_on(
    release: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    release_job: Callable[..., str],
    fake_gh: Callable[..., Callable[[], list[list[object]]]],
    capsys: pytest.CaptureFixture[str],
) -> None:
    """The run of an older commit leaves the release to the run of the new head."""
    release_job(git_repo("checkout", {"flake.lock": NEW_LOCK.encode()}))
    sent = fake_gh({BRANCHES: branches(master=STALE), **ANSWERS})

    status = release.main()

    assert status == DONE
    assert [request[0] for request in sent()] == ["GET"]
    assert "No release" in capsys.readouterr().out


@pytest.mark.parametrize(
    "wrong",
    [
        pytest.param({BRANCHES: {"message": "Not Found"}}, id="branches not listed"),
        pytest.param(
            {"POST graphql": {"data": None, "errors": [{"message": "stale"}]}},
            id="version commit that GitHub did not make",
        ),
        pytest.param({"POST graphql": None}, id="version commit refused"),
        pytest.param({f"POST {API}/git/refs": None}, id="tag refused"),
        pytest.param({f"POST {API}/releases": None}, id="release refused"),
        pytest.param(
            {f"PATCH {API}/git/refs/heads/stable": None}, id="channel refused"
        ),
        pytest.param({f"POST {API}/deployments": None}, id="deployment refused"),
        pytest.param(
            {f"POST {API}/deployments/42/statuses": None}, id="status refused"
        ),
    ],
)
def test_release_stops_at_the_first_request_that_goes_wrong(
    release: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    release_job: Callable[..., str],
    fake_gh: Callable[..., Callable[[], list[list[object]]]],
    wrong: dict[str, object],
) -> None:
    """Nothing is sent after a failure: the channel never moves to a broken release.

    ``wrong`` maps one request to the reply that spoils it, or to ``None`` when
    GitHub refuses the request.
    """
    commit = release_job(git_repo("checkout", {"flake.lock": NEW_LOCK.encode()}))
    ((request, reply),) = wrong.items()
    answers = {BRANCHES: branches(master=commit, stable=STALE), **ANSWERS, **wrong}
    sent = fake_gh(answers, () if reply is not None else (request,))

    status = release.main()

    assert status == STOPPED
    assert sent()[-1][:2] == request.split(" ")


@pytest.mark.parametrize(
    "version",
    [
        pytest.param(b"0.0.9", id="version file without its line break"),
        pytest.param(b"0.0.9\n", id="next version that already has its tag"),
        pytest.param(b"\xff.0.9\n", id="version file that is not UTF-8"),
    ],
)
def test_checkout_that_cannot_be_released_writes_nothing(
    release: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    release_job: Callable[..., str],
    fake_gh: Callable[..., Callable[[], list[list[object]]]],
    version: bytes,
) -> None:
    """The version file and the tags are read before the first request that writes."""
    files = {"flake.lock": NEW_LOCK.encode(), ".version": version}
    repository = git_repo("checkout", files)
    release.run("git", "-C", str(repository), "tag", "0.0.10")
    commit = release_job(repository)
    sent = fake_gh({BRANCHES: branches(master=commit), **ANSWERS})

    status = release.main()

    assert status == STOPPED
    assert [request[0] for request in sent()] == ["GET"]


@pytest.mark.parametrize(
    "setting",
    [
        pytest.param({"GITHUB_SHA": None}, id="no commit"),
        pytest.param({"GITHUB_SHA": "master"}, id="commit that is not a hash"),
        pytest.param({"GITHUB_REF": "refs/tags/1.0.0"}, id="tag and not a branch"),
        pytest.param({"GITHUB_REPOSITORY": "example"}, id="repository without owner"),
        pytest.param({"BUMP": "Minor"}, id="bump that names no part"),
    ],
)
def test_malformed_environment_writes_nothing(
    release: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    release_job: Callable[..., str],
    fake_gh: Callable[..., Callable[[], list[list[object]]]],
    setting: dict[str, str | None],
) -> None:
    """What the runner and the manual run say is checked before anything changes."""
    repository = git_repo("checkout", {"flake.lock": NEW_LOCK.encode()})
    commit = release_job(repository)
    release_job(repository, **setting)
    sent = fake_gh({BRANCHES: branches(master=commit), **ANSWERS})

    status = release.main()

    assert status == STOPPED
    assert [request[0] for request in sent() if request[0] != "GET"] == []


def test_release_job_waits_for_every_other_job(scripts_dir: Path) -> None:
    """A job that the release did not wait for would be released unchecked."""
    root = scripts_dir.parent
    # The overlay holds the workflow here and becomes the root of the export.
    home = next(
        candidate
        for candidate in (root / "publish/overlay/.github", root / ".github")
        if candidate.is_dir()
    )
    workflow = (home / "workflows/cicd.yml").read_text(encoding="utf-8")
    jobs = re.findall(r"^  ([\w-]+):$", workflow.split("\njobs:\n")[1], re.MULTILINE)
    needed = re.findall(r"^    needs: \[(.*)\]$", workflow, re.MULTILINE)

    assert [sorted(names.split(", ")) for names in needed] == [
        sorted(set(jobs) - {"release"})
    ]

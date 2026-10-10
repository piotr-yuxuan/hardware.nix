"""Acceptance tests for scripts/publish.py.

Each test states one requirement of the public export and is aimed at a
plausible wrong implementation. Samples that the gate itself would refuse
are assembled from pieces, so that this file passes the gate it tests.
"""

from __future__ import annotations

import hashlib
import os
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import Callable
    from pathlib import Path
    from types import ModuleType

DENIED_NAME = "Zebulon Quux"
MANIFEST = "publish/manifest.toml"
EVERYTHING = b'include = ["**"]\nexclude = []\nsweep = true\n'
UNTOUCHED = {"README": b"before the export\n"}
# The exit statuses that the command line promises.
CLEAN, FINDINGS, INVALID_INPUT = 0, 1, 2
HANDLE_ADDRESS = "piotr-yuxuan@users.noreply.github.com"
DISPLAY_NAME = "胡雨軒 Петр"
MAC = "aa:bb:cc:" + "dd:ee:ff"


def test_sweep_applies_overlapping_rules_in_file_order(
    publish: ModuleType, rules_dir: Callable[..., Path]
) -> None:
    """The first rule wins where two sources overlap, as in git filter-repo."""
    rules = publish.load_rules(rules_dir(replacements=("abcd==>long", "ab==>short")))

    assert publish.sweep(rules, b"abcd ab") == b"long short"


def test_sweep_applies_every_literal_before_any_regex(
    publish: ModuleType, rules_dir: Callable[..., Path]
) -> None:
    """Where a literal and a regex overlap, the literal wins, as in git filter-repo."""
    rules = publish.load_rules(rules_dir(replacements=("ab==>x", "regex:a+b==>y")))

    assert publish.sweep(rules, b"aab") == b"ax"


def test_sweep_respects_word_boundaries_of_a_short_token(
    publish: ModuleType, rules_dir: Callable[..., Path]
) -> None:
    """A short account name is rewritten as a word, not inside other words."""
    rules = publish.load_rules(rules_dir(replacements=(r"regex:\bjo\b==>example",)))

    swept = publish.sweep(rules, b"jo /srv/jo/ john banjo")

    assert swept == b"example /srv/example/ john banjo"


def test_sweep_changes_nothing_but_the_matches(
    publish: ModuleType, rules_dir: Callable[..., Path]
) -> None:
    """Line endings and bytes that are not UTF-8 survive around a match."""
    rules = publish.load_rules(rules_dir(replacements=("acme==>example",)))

    assert publish.sweep(rules, b"\xff\r\nacme\r\n") == b"\xff\r\nexample\r\n"


def test_empty_replacements_are_valid_and_rewrite_nothing(
    publish: ModuleType, rules_dir: Callable[..., Path]
) -> None:
    """A repository that needs no rule has an empty replacements file."""
    rules = publish.load_rules(rules_dir())

    assert publish.sweep(rules, b"acme\n") == b"acme\n"


@pytest.mark.parametrize(
    "deny", [pytest.param((), id="empty"), pytest.param(("# people",), id="comments")]
)
def test_deny_list_without_an_entry_is_refused(
    publish: ModuleType, rules_dir: Callable[..., Path], deny: tuple[str, ...]
) -> None:
    """A deny list that forbids nothing is a lost file, not a decision."""
    with pytest.raises(publish.InvalidInputError):
        publish.load_rules(rules_dir(deny=deny))


def test_last_rule_without_a_newline_is_refused(
    publish: ModuleType, rules_dir: Callable[..., Path]
) -> None:
    """A rule appended to the file would otherwise run into the last one."""
    directory = rules_dir()
    (directory / "replacements.txt").write_bytes(b"acme==>example")

    with pytest.raises(publish.InvalidInputError):
        publish.load_rules(directory)


@pytest.mark.parametrize(
    "replacements",
    [
        pytest.param(("acme",), id="no arrow: filter-repo would write REMOVED"),
        pytest.param(("a==>b==>c",), id="two arrows"),
        pytest.param(("# a comment",), id="comment"),
        pytest.param(("acme==>example", "", "zed==>y"), id="blank line"),
        pytest.param(("==>example",), id="empty source"),
        pytest.param(("acme==>exa\\1mple",), id="backslash in the replacement"),
        pytest.param(("glob:ac*==>example",), id="glob"),
        pytest.param(("acme==>example\r",), id="carriage return"),
        pytest.param(("acme==>acme corp",), id="replacement holds its own source"),
        pytest.param(
            ("acme==>example", "zed==>the acme"),
            id="replacement holds another source",
        ),
        pytest.param(
            ("zed==>jo", r"regex:\bjo\b==>example"),
            id="replacement matched by a regex",
        ),
        pytest.param(("regex:a+==>x", "b==>y"), id="literal after a regex"),
        pytest.param(("regex:(==>x",), id="invalid regex"),
        pytest.param(("regex:a*==>x",), id="regex matching the empty text"),
    ],
)
def test_ambiguous_replacement_rules_are_refused(
    publish: ModuleType, rules_dir: Callable[..., Path], replacements: tuple[str, ...]
) -> None:
    """The parser accepts only what it and git filter-repo read the same way."""
    with pytest.raises(publish.InvalidInputError):
        publish.load_rules(rules_dir(replacements=replacements))


def test_path_to_remove_that_reads_as_a_rename_is_refused(
    publish: ModuleType, rules_dir: Callable[..., Path]
) -> None:
    """A line with an arrow would rename the path instead of dropping it."""
    with pytest.raises(publish.InvalidInputError):
        publish.load_rules(rules_dir(remove=("old.png==>new.png",)))


def test_replacement_on_the_deny_list_is_refused_in_any_case(
    publish: ModuleType, rules_dir: Callable[..., Path]
) -> None:
    """A rule may not write what the deny list forbids."""
    directory = rules_dir(replacements=("acme==>Initech",), deny=("INITECH",))

    with pytest.raises(publish.InvalidInputError):
        publish.load_rules(directory)


def test_missing_rules_are_invalid_input(publish: ModuleType, tmp_path: Path) -> None:
    """Without its rules the tool refuses to run, it does not assume none."""
    with pytest.raises(publish.InvalidInputError):
        publish.load_rules(tmp_path / "absent")


@pytest.mark.parametrize(
    "text",
    [
        pytest.param("by ZEBULON QUUX", id="another case"),
        pytest.param("by Zebu\u200blon Quux", id="zero-width character"),
        pytest.param("by Zebulon\n  Quux", id="wrapped across a line"),
        pytest.param("by \uff3aebulon Quux", id="full-width letter"),
    ],
)
def test_denied_name_is_found_however_it_is_written(
    publish: ModuleType, rules_dir: Callable[..., Path], text: str
) -> None:
    """Case, invisible characters, width and line wraps do not hide a name."""
    rules = publish.load_rules(rules_dir(deny=(DENIED_NAME,)))

    findings = publish.scan_entry(
        "notes.org", "100644", text.encode(), rules, publish.load_allow("")
    )

    assert [finding.check for finding in findings] == ["private deny"]


def test_denied_name_in_a_path_only_is_found(
    publish: ModuleType, rules_dir: Callable[..., Path]
) -> None:
    """A clean file under a directory named after a person is still refused."""
    rules = publish.load_rules(rules_dir(deny=(DENIED_NAME,)))

    findings = publish.scan_entry(
        "docs/zebulon quux/notes.org",
        "100644",
        b"clean\n",
        rules,
        publish.load_allow(""),
    )

    assert [finding.check for finding in findings] == ["private deny"]


@pytest.mark.parametrize(
    "payload",
    [
        pytest.param(DENIED_NAME.encode(), id="plain bytes"),
        pytest.param(DENIED_NAME.encode("utf-16-le"), id="UTF-16"),
    ],
)
def test_denied_name_inside_an_allowlisted_binary_is_found(
    publish: ModuleType, rules_dir: Callable[..., Path], payload: bytes
) -> None:
    """Allowlisting a binary by digest does not exempt its bytes from the deny list."""
    rules = publish.load_rules(rules_dir(deny=(DENIED_NAME,)))
    data = b"\x89PNG\0\xff" + payload + b"\xfe"
    allow = publish.load_allow(f'sha256 = ["{hashlib.sha256(data).hexdigest()}"]')

    findings = publish.scan_entry("img/photo.png", "100644", data, rules, allow)

    assert {finding.check for finding in findings} == {"private deny"}


@pytest.mark.parametrize(
    ("payload", "checks"),
    [
        pytest.param(b" zq1 ", [], id="among arbitrary bytes"),
        pytest.param(
            b"/media/zq1/Pictures/photo.jpg", ["private deny"], id="in a string"
        ),
        pytest.param(
            "/media/zq1/Pictures/photo.jpg".encode("utf-16-le"),
            ["private deny"],
            id="in a UTF-16 string",
        ),
    ],
)
def test_short_denied_token_in_a_binary_counts_inside_a_string_only(
    publish: ModuleType,
    rules_dir: Callable[..., Path],
    payload: bytes,
    checks: list[str],
) -> None:
    """Three letters occur by chance in any picture, but not inside its metadata."""
    rules = publish.load_rules(rules_dir(deny=(r"regex:\bzq1\b",)))
    data = b"\x89PNG\0\xff" + payload + b"\xfe"
    allow = publish.load_allow(f'sha256 = ["{hashlib.sha256(data).hexdigest()}"]')

    findings = publish.scan_entry("img/photo.png", "100644", data, rules, allow)

    assert [finding.check for finding in findings] == checks


def test_allowlist_does_not_waive_an_address_at_a_denied_domain(
    publish: ModuleType, rules_dir: Callable[..., Path]
) -> None:
    """The public allowlist acknowledges generic findings only, never the deny list."""
    address = "me@" + "denied-domain.org"
    rules = publish.load_rules(rules_dir(deny=("denied-domain.org",)))
    allow = publish.load_allow(f'values = ["{address}"]')

    findings = publish.scan_entry("notes.org", "100644", address.encode(), rules, allow)

    assert [finding.check for finding in findings] == ["private deny"]


def test_deny_file_comments_and_blank_lines_are_not_entries(
    publish: ModuleType, rules_dir: Callable[..., Path]
) -> None:
    """A comment in deny.txt forbids nothing, and a blank line does not match all."""
    rules = publish.load_rules(rules_dir(deny=("# people", "", DENIED_NAME)))

    findings = publish.scan_entry(
        "notes.org", "100644", b"# people\n\n", rules, publish.load_allow("")
    )

    assert findings == []


def test_deny_regex_is_matched_against_folded_text(
    publish: ModuleType, rules_dir: Callable[..., Path]
) -> None:
    """A deny regex bounds a short token and still ignores case."""
    rules = publish.load_rules(rules_dir(deny=(r"regex:\bzq\d+\b",)))

    findings = publish.scan_entry(
        "notes.org", "100644", b"user ZQ42, not azq1", rules, publish.load_allow("")
    )

    assert [finding.value for finding in findings] == ["zq42"]


@pytest.mark.parametrize(
    ("text", "checks"),
    [
        pytest.param("mail someone@" + "corp.org", {"e-mail address"}, id="e-mail"),
        pytest.param(
            "12345+someone@" + "users.noreply.github.com",
            {"e-mail address", "numeric-id noreply address"},
            id="numeric noreply",
        ),
        pytest.param("aa:bb:cc:" + "dd:ee:ff", {"MAC address"}, id="MAC"),
        pytest.param("123e4567-e89b-12d3-" + "a456-426614174000", {"UUID"}, id="UUID"),
        pytest.param("cd /ho" + "me/zebulon/src", {"home directory"}, id="home"),
        pytest.param("in /Use" + "rs/zebulon", {"home directory"}, id="macOS home"),
        pytest.param(
            'signingKey = "0123456789' + 'abcdef";', {"key id"}, id="signing key"
        ),
        pytest.param(
            "the OpenPGP key\n=0123456789" + "ABCDEF= of the old machine",
            {"key id"},
            id="key id wrapped onto the next line",
        ),
        pytest.param(
            "0123456789ABCDEF0123" + "456789ABCDEF01234567",
            {"key fingerprint"},
            id="fingerprint",
        ),
        pytest.param(
            "0123 4567 89AB CDEF 0123  " + "4567 89AB CDEF 0123 4567",
            {"key fingerprint"},
            id="spaced fingerprint",
        ),
        pytest.param(
            "-----BEGIN OPENSSH " + "PRIVATE KEY-----", {"key material"}, id="key"
        ),
        pytest.param(
            "ssh-ed25519 " + "AAAAC3NzaC1lZDI1NTE5AAAAIabcdefghijk",
            {"key material"},
            id="SSH public key",
        ),
        pytest.param("gh" + "p_" + "a" * 36, {"token"}, id="token"),
        pytest.param(
            "see ../home/base.nix, ./home/C.nix and ~/home/x", set(), id="repo paths"
        ),
        pytest.param(
            'rev = "0123456789abcdef0123' + '456789abcdef01234567";',
            set(),
            id="commit hash away from any signing word",
        ),
        pytest.param(
            "write to first.last@example.com or root@host.test",
            set(),
            id="reserved domains",
        ),
    ],
)
def test_generic_shapes_of_personal_data(
    publish: ModuleType, text: str, checks: set[str]
) -> None:
    """Without private rules, as in public CI, the generic shapes are still caught."""
    findings = publish.scan_entry(
        "notes.org", "100644", text.encode(), None, publish.load_allow("")
    )

    assert {finding.check for finding in findings} == checks


def test_address_shape_ends_where_a_domain_name_must(publish: ModuleType) -> None:
    """A key file named after an address reports the address; a display mode none."""
    address = "someone@" + "corp.org"
    text = f"ssh -i ~/.ssh/{address}_ed25519.pub, at 3440x1440@120.000 Hz"

    findings = publish.scan_entry(
        "notes.org", "100644", text.encode(), None, publish.load_allow("")
    )

    assert [finding.value for finding in findings] == [address]


def test_allowlist_acknowledges_an_exact_value_only(publish: ModuleType) -> None:
    """Acknowledging one address does not let its whole domain through."""
    domain = "corp.org"
    allow = publish.load_allow(f'values = ["bot@{domain}"]')

    findings = publish.scan_entry(
        "notes.org", "100644", f"bot@{domain} boss@{domain}".encode(), None, allow
    )

    assert [finding.value for finding in findings] == [f"boss@{domain}"]


def test_numeric_noreply_address_cannot_be_allowlisted(publish: ModuleType) -> None:
    """The form that carries the account number never passes in contents."""
    address = "12345+someone@" + "users.noreply.github.com"
    allow = publish.load_allow(f'values = ["{address}"]')

    findings = publish.scan_entry("a.txt", "100644", address.encode(), None, allow)

    assert [finding.check for finding in findings] == ["numeric-id noreply address"]


def test_submodule_entry_is_refused(publish: ModuleType) -> None:
    """A gitlink would publish a pointer to a repository nobody reviewed."""
    findings = publish.scan_entry("vendor", "160000", b"", None, publish.load_allow(""))

    assert [finding.check for finding in findings] == ["entry mode"]


@pytest.mark.parametrize(
    ("path", "target", "checks"),
    [
        pytest.param("a/link", "../b/file", [], id="inside the tree"),
        pytest.param("link", "../outside", ["symlink leaves the tree"], id="parent"),
        pytest.param(
            "a/link", "/etc/hosts", ["symlink leaves the tree"], id="absolute"
        ),
        pytest.param(
            "a/link", "b/../../../x", ["symlink leaves the tree"], id="through a detour"
        ),
    ],
)
def test_symlink_must_stay_inside_the_tree(
    publish: ModuleType, path: str, target: str, checks: list[str]
) -> None:
    """A link may point anywhere in the repository and nowhere else."""
    findings = publish.scan_entry(
        path, "120000", target.encode(), None, publish.load_allow("")
    )

    assert [finding.check for finding in findings] == checks


@pytest.mark.parametrize(
    "data",
    [
        pytest.param(b"\x89PNG\0\x01\x02", id="binary"),
        pytest.param(b"0123456789abcde\n" * (1 << 16) + b"\n", id="text over 1 MiB"),
    ],
)
def test_binary_or_large_file_needs_its_digest_allowlisted(
    publish: ModuleType, data: bytes
) -> None:
    """What nobody can review in a diff is published only by explicit digest."""
    digest = hashlib.sha256(data).hexdigest()

    unlisted = publish.scan_entry("blob", "100644", data, None, publish.load_allow(""))
    listed = publish.scan_entry(
        "blob", "100644", data, None, publish.load_allow(f'sha256 = ["{digest}"]')
    )

    assert [(finding.check, finding.value) for finding in unlisted] == [
        ("binary or large file not allowlisted", digest)
    ]
    assert listed == []


@pytest.mark.parametrize(
    ("path", "data"),
    [
        pytest.param("notes.txt", b"\x1f\x8b\x08\0\0\0\0\0", id="gzip content"),
        pytest.param("bundle.ZIP", b"plain text\n", id="archive suffix"),
        pytest.param("old", b"\0" * 257 + b"ustar\0" + b"\0" * 250, id="tar content"),
    ],
)
def test_archive_is_refused_even_when_allowlisted(
    publish: ModuleType, path: str, data: bytes
) -> None:
    """An archive hides its content from every other check, so no digest waives it."""
    allow = publish.load_allow(f'sha256 = ["{hashlib.sha256(data).hexdigest()}"]')

    findings = publish.scan_entry(path, "100644", data, None, allow)

    assert [finding.check for finding in findings] == ["archive or compressed file"]


@pytest.mark.parametrize(
    "path",
    [
        pytest.param("a\tb", id="control character"),
        pytest.param("a\\b", id="backslash"),
        pytest.param("x/.GIT/config", id="git directory"),
        pytest.param("e\u0301.txt", id="decomposed accent"),
        pytest.param("caf\udce9.txt", id="not UTF-8"),
    ],
)
def test_unsafe_path_is_refused(publish: ModuleType, path: str) -> None:
    """Paths must mean the same on every file system that clones the repository."""
    findings = publish.scan_entry(path, "100644", b"", None, publish.load_allow(""))

    assert [finding.check for finding in findings] == ["path hygiene"]


@pytest.mark.parametrize(
    "text",
    [
        pytest.param("values = [", id="not TOML"),
        pytest.param('value = ["a"]', id="unknown key"),
        pytest.param('values = "a"', id="not a list"),
        pytest.param("sha256 = [1]", id="not strings"),
    ],
)
def test_malformed_allowlist_is_invalid_input(publish: ModuleType, text: str) -> None:
    """A typo in the allowlist must not silently allow nothing, or everything."""
    with pytest.raises(publish.InvalidInputError):
        publish.load_allow(text)


def test_export_selects_sweeps_and_overlays_one_commit(
    export_files: Callable[..., tuple[int, dict[str, bytes]]], public_clone: Path
) -> None:
    """The public tree is the selection, rewritten, plus the overlay as written."""
    files = {
        MANIFEST: b'include = ["docs/**", "*.nix"]\nexclude = ["docs/work/**"]\n'
        b"sweep = true\n",
        "publish/overlay/LICENSE": b"the licence mentions acme\n",
        "flake.nix": b"host = acme;\n",
        "docs/acme/guide.org": b"see acme\n",
        "docs/work/plan.org": b"a private plan\n",
    }

    status, tree = export_files(files, replacements=("acme==>example",))

    assert status == CLEAN
    assert tree == {
        "LICENSE": b"the licence mentions acme\n",
        "flake.nix": b"host = example;\n",
        "docs/example/guide.org": b"see example\n",
    }
    assert (public_clone / "docs/example/guide.org").read_bytes() == b"see example\n"


def test_export_reads_the_commit_and_not_the_work_tree(
    export: Callable[..., int],
    git_repo: Callable[[str, dict[str, bytes]], Path],
    public_clone: Path,
    tree_of: Callable[[Path], dict[str, bytes]],
) -> None:
    """An edit or a new file that was never committed cannot be published."""
    source = git_repo("private", {MANIFEST: EVERYTHING, "notes.txt": b"committed\n"})
    (source / "notes.txt").write_bytes(b"edited, not committed\n")
    (source / "draft.txt").write_bytes(b"never added\n")

    status = export(source, public_clone)

    assert status == CLEAN
    assert tree_of(public_clone) == {"notes.txt": b"committed\n"}


def test_export_publishes_the_given_commit_and_not_the_head(
    export: Callable[..., int],
    git_repo: Callable[[str, dict[str, bytes]], Path],
    commit: Callable[..., None],
    public_clone: Path,
    tree_of: Callable[[Path], dict[str, bytes]],
) -> None:
    """The commit to publish is an argument, whatever is checked out."""
    source = git_repo("private", {MANIFEST: EVERYTHING, "notes.txt": b"first\n"})
    commit(source, {"notes.txt": b"second\n", "later.txt": b"not yet\n"})

    status = export(source, public_clone, commit="HEAD~1")

    assert status == CLEAN
    assert tree_of(public_clone) == {"notes.txt": b"first\n"}


def test_export_keeps_paths_modes_and_bytes_exactly(
    publish: ModuleType,
    export: Callable[..., int],
    git_repo: Callable[[str, dict[str, bytes]], Path],
    commit: Callable[..., None],
    public_clone: Path,
) -> None:
    """A path with a space or an accent, a script and a link arrive as they were."""
    files = {MANIFEST: EVERYTHING, "a b/\u00e9.txt": b"no newline", "run.sh": b"#!\n"}
    source = git_repo("private", files)
    (source / "run.sh").chmod(0o755)
    (source / "link").symlink_to("a b/\u00e9.txt")
    commit(source, {})

    status = export(source, public_clone)

    listing = publish.git(public_clone, "ls-tree", "-r", "-z", "HEAD").split(b"\0")
    assert status == CLEAN
    assert [(line[:6], line.partition(b"\t")[2]) for line in listing[:-1]] == [
        (b"100644", "a b/\u00e9.txt".encode()),
        (b"120000", b"link"),
        (b"100755", b"run.sh"),
    ]
    assert (public_clone / "link").read_bytes() == b"no newline"


def test_gate_reads_the_swept_tree_and_not_the_private_one(
    export_files: Callable[..., tuple[int, dict[str, bytes]]],
) -> None:
    """What a rule rewrites is no longer there to be refused."""
    files = {
        MANIFEST: b'include = ["**"]\nexclude = ["private.txt"]\nsweep = true\n',
        "notes.txt": b"host acme\n",
        "private.txt": b"acme, kept private\n",
    }

    outcome = export_files(files, replacements=("acme==>example",), deny=("acme",))

    assert outcome == (CLEAN, {"notes.txt": b"host example\n"})


def test_export_never_publishes_its_own_directory(
    export_files: Callable[..., tuple[int, dict[str, bytes]]],
) -> None:
    """Even a manifest that includes everything leaves the rules private."""
    files = {
        MANIFEST: EVERYTHING,
        "publish/private/replacements.txt": b"the private rules\n",
        "notes.txt": b"public\n",
    }

    assert export_files(files) == (CLEAN, {"notes.txt": b"public\n"})


def test_exclude_wins_over_include(
    export_files: Callable[..., tuple[int, dict[str, bytes]]],
) -> None:
    """A path matched by both lists stays private."""
    manifest = b'include = ["**"]\nexclude = ["home/private.nix"]\nsweep = true\n'
    files = {MANIFEST: manifest, "home/private.nix": b"x\n", "home/base.nix": b"y\n"}

    assert export_files(files) == (CLEAN, {"home/base.nix": b"y\n"})


def test_lock_files_and_binaries_are_never_swept(
    export_files: Callable[..., tuple[int, dict[str, bytes]]],
) -> None:
    """A rule must not corrupt a pinned hash or a picture that happens to match."""
    picture = b"\x89PNG\0acme\xff"
    unswept = {
        "flake.lock": b'{"narHash": "sha256-acme"}\n',
        "package-lock.json": b'{"integrity": "acme"}\n',
        "picture.png": picture,
    }
    allow = f'sha256 = ["{hashlib.sha256(picture).hexdigest()}"]\n'.encode()
    files = {
        MANIFEST: EVERYTHING,
        "publish/overlay/.github/publish-allow.toml": allow,
        "notes.txt": b"acme\n",
        **unswept,
    }

    status, tree = export_files(files, replacements=("acme==>example",))

    assert status == CLEAN
    assert tree == {
        ".github/publish-allow.toml": allow,
        "notes.txt": b"example\n",
        **unswept,
    }


def test_overlay_allowlist_acknowledges_a_generic_finding(
    export_files: Callable[..., tuple[int, dict[str, bytes]]],
) -> None:
    """The allowlist that is published is the one the export gate reads."""
    address = "bot@" + "corp.org"
    allow = f'values = ["{address}"]\n'.encode()
    files = {
        MANIFEST: EVERYTHING,
        "publish/overlay/.github/publish-allow.toml": allow,
        "notes.txt": f"write to {address}\n".encode(),
    }

    status, tree = export_files(files)

    assert status == CLEAN
    assert tree["notes.txt"] == files["notes.txt"]


@pytest.mark.parametrize(
    ("files", "replacements", "check"),
    [
        pytest.param(
            {
                MANIFEST: b'include = ["*.nix"]\nexclude = []\nsweep = true\n',
                "a.nix": b"",
                "new.txt": b"",
            },
            (),
            "new.txt: unclassified path",
            id="file that the manifest does not classify",
        ),
        pytest.param(
            {
                MANIFEST: b'include = ["**"]\nexclude = ["secrte/**"]\nsweep = true\n',
                "secret/key": b"x\n",
            },
            (),
            "stale pattern: secrte/**",
            id="typo in an exclude pattern",
        ),
        pytest.param(
            {MANIFEST: EVERYTHING, "notes.txt": b"by zebulon quux\n"},
            (),
            "notes.txt: private deny",
            id="denied name that no rule rewrites",
        ),
        pytest.param(
            {MANIFEST: EVERYTHING, "notes.txt": b"aa:bb:cc:" + b"dd:ee:ff\n"},
            (),
            "notes.txt: MAC address",
            id="generic finding",
        ),
        pytest.param(
            {
                MANIFEST: b'include = ["**"]\nexclude = []\nsweep = false\n',
                "notes.txt": b"acme\n",
            },
            ("acme==>example",),
            "notes.txt: rule applies but sweep is false",
            id="rule applies where the manifest promised none would",
        ),
        pytest.param(
            {MANIFEST: EVERYTHING, "acme.txt": b"", "example.txt": b""},
            ("acme==>example",),
            "example.txt: path collision",
            id="two files swept onto one path",
        ),
        pytest.param(
            {MANIFEST: EVERYTHING, "Notes.txt": b"", "notes.txt": b""},
            (),
            "path collision ignoring case",
            id="paths that differ by case only",
        ),
        pytest.param(
            {MANIFEST: EVERYTHING, "LICENSE": b"", "publish/overlay/LICENSE": b""},
            (),
            "LICENSE: overlay collision",
            id="overlay would replace a selected file",
        ),
        pytest.param(
            {MANIFEST: EVERYTHING, "publish/overlay/NOTICE": b"by Zebulon Quux\n"},
            (),
            "NOTICE: private deny",
            id="denied name in an overlay file",
        ),
        pytest.param(
            {MANIFEST: EVERYTHING, "notes.txt": b"abb\n"},
            ("ab==>a",),
            "notes.txt: unstable replacement",
            id="sweeping twice would change the file again",
        ),
    ],
)
def test_export_refuses_and_leaves_the_public_clone_untouched(
    export_files: Callable[..., tuple[int, dict[str, bytes]]],
    capsys: pytest.CaptureFixture[str],
    files: dict[str, bytes],
    replacements: tuple[str, ...],
    check: str,
) -> None:
    """One finding of any kind stops the export before anything is written."""
    outcome = export_files(files, replacements, deny=(DENIED_NAME,))

    assert outcome == (FINDINGS, UNTOUCHED)
    assert check in capsys.readouterr().out


def test_public_branch_does_not_move_when_the_new_commit_fails_the_gate(
    export_files: Callable[..., tuple[int, dict[str, bytes]]],
    capsys: pytest.CaptureFixture[str],
) -> None:
    """The commit is gated like any other before the branch may reach it."""
    files = {MANIFEST: EVERYTHING, "notes.txt": b"public\n"}

    outcome = export_files(files, deny=("the private repository",))

    assert outcome == (FINDINGS, UNTOUCHED)
    assert "private deny: the private repository" in capsys.readouterr().out


@pytest.mark.usefixtures("work_identity")
def test_export_commit_ignores_the_ambient_identity_and_key(
    publish: ModuleType,
    export: Callable[..., int],
    git_repo: Callable[[str, dict[str, bytes]], Path],
    public_clone: Path,
    signing_key: str,
) -> None:
    """The commit is signed by the given key, as the handle, on top of the head."""
    source = git_repo("private", {MANIFEST: EVERYTHING, "notes.txt": b"public\n"})
    parent = publish.git(public_clone, "rev-parse", "HEAD").decode().strip()

    status = export(source, public_clone)

    handle = "piotr-yuxuan <piotr-yuxuan@users.noreply.github.com>"
    shown = publish.git(
        public_clone,
        *("log", "-1", "--no-show-signature"),
        "--format=%an <%ae>%n%cn <%ce>%n%s%n%GF%n%P",
    )
    assert status == CLEAN
    assert shown.decode().splitlines() == [
        handle,
        handle,
        "Update configuration files",
        signing_key,
        parent,
    ]


def test_export_commit_carries_the_committer_date_of_its_source(
    publish: ModuleType,
    export: Callable[..., int],
    git_repo: Callable[[str, dict[str, bytes]], Path],
    public_clone: Path,
) -> None:
    """The same private commit always yields the same public commit dates."""
    source = git_repo("private", {MANIFEST: EVERYTHING, "notes.txt": b"public\n"})
    date = "2020-02-02T02:02:02+02:00"
    publish.git(
        source,
        *("-c", "user.name=x", "-c", "user.email=x@example.org"),
        *("commit", "--quiet", "--amend", "--no-edit"),
        env={**os.environ, "GIT_COMMITTER_DATE": date},
    )

    status = export(source, public_clone)

    shown = publish.git(public_clone, "log", "-1", "--format=%aI %cI")
    assert status == CLEAN
    assert shown.decode().split() == [date, date]


def test_second_export_of_the_same_commit_is_a_no_op(
    publish: ModuleType,
    export: Callable[..., int],
    git_repo: Callable[[str, dict[str, bytes]], Path],
    public_clone: Path,
) -> None:
    """Publishing what is already public adds no commit."""
    source = git_repo("private", {MANIFEST: EVERYTHING, "notes.txt": b"public\n"})
    first = export(source, public_clone)
    head = publish.git(public_clone, "rev-parse", "HEAD")

    second = export(source, public_clone)

    assert (first, second) == (CLEAN, CLEAN)
    assert publish.git(public_clone, "rev-parse", "HEAD") == head


@pytest.mark.parametrize(
    "files",
    [
        pytest.param({"notes.txt": b""}, id="no manifest"),
        pytest.param({MANIFEST: b"include = ["}, id="manifest is not TOML"),
        pytest.param({MANIFEST: b'include = ["**"]\nsweep = true\n'}, id="missing key"),
        pytest.param(
            {MANIFEST: b'include = "**"\nexclude = []\nsweep = true\n'},
            id="include is not a list",
        ),
        pytest.param(
            {MANIFEST: b'include = ["**"]\nexclude = []\nsweep = "no"\n'},
            id="sweep is not a boolean",
        ),
        pytest.param({MANIFEST: EVERYTHING + b"sweeep = false\n"}, id="unknown key"),
    ],
)
def test_malformed_manifest_is_invalid_input(
    export_files: Callable[..., tuple[int, dict[str, bytes]]], files: dict[str, bytes]
) -> None:
    """A manifest that cannot be read as written publishes nothing."""
    assert export_files(files) == (INVALID_INPUT, UNTOUCHED)


@pytest.mark.parametrize("target", ["the private repository", "a clone of it"])
def test_export_refuses_a_target_that_holds_the_private_history(
    publish: ModuleType,
    export: Callable[..., int],
    git_repo: Callable[[str, dict[str, bytes]], Path],
    commit: Callable[..., None],
    target: str,
) -> None:
    """The export goes from the private repository to another, public one."""
    source = git_repo("private", {MANIFEST: EVERYTHING, "notes.txt": b"public\n"})
    publish.git(source.parent, "clone", "--quiet", str(source), "copy")
    commit(source, {"notes.txt": b"public, edited\n"})
    public = source if target == "the private repository" else source.parent / "copy"
    head = publish.git(public, "rev-parse", "HEAD")

    status = export(source, public)

    assert status == INVALID_INPUT
    assert publish.git(public, "rev-parse", "HEAD") == head


def test_export_refuses_a_public_clone_with_local_changes(
    export: Callable[..., int],
    git_repo: Callable[[str, dict[str, bytes]], Path],
    public_clone: Path,
) -> None:
    """The public clone is only ever fast-forwarded, never edited by hand."""
    source = git_repo("private", {MANIFEST: EVERYTHING, "notes.txt": b"public\n"})
    (public_clone / "hand-made.txt").write_bytes(b"x\n")

    assert export(source, public_clone) == INVALID_INPUT


def test_history_made_of_exports_is_clean(
    export: Callable[..., int],
    git_repo: Callable[[str, dict[str, bytes]], Path],
    public_clone: Path,
    check_history: Callable[..., tuple[int, str]],
) -> None:
    """What the export commits passes the gate that public CI runs."""
    source = git_repo("private", {MANIFEST: EVERYTHING, "notes.txt": b"public\n"})
    export(source, public_clone)

    assert check_history(public_clone)[0] == CLEAN


@pytest.mark.parametrize(
    ("change", "checks"),
    [
        pytest.param(
            {"committer": ("piotr-yuxuan", "work@corp.example")},
            {"committer identity"},
            id="work address as committer only",
        ),
        pytest.param(
            {"author": ("Zebulon Quux", HANDLE_ADDRESS)},
            {"author identity"},
            id="another name as author",
        ),
        pytest.param(
            {"message": "Fix\n\nCO-AUTHORED-BY: Bot <bot@example.org>"},
            {"attribution trailer"},
            id="attribution trailer in any case",
        ),
        pytest.param(
            {"message": f"Pair the keyboard {MAC}"},
            {"MAC address"},
            id="personal data in a message",
        ),
    ],
)
def test_commit_metadata_is_gated(
    git_repo: Callable[[str, dict[str, bytes]], Path],
    commit: Callable[..., None],
    check_history: Callable[..., tuple[int, str]],
    change: dict[str, object],
    checks: set[str],
) -> None:
    """Every commit is made by the handle, without trailer or personal data."""
    repository = git_repo("public", {"notes.txt": b"public\n"})
    commit(repository, {}, **change)

    status, report = check_history(repository)

    assert status == FINDINGS
    assert {line.split(": ")[1] for line in report.splitlines()} == checks


def test_display_name_at_the_numeric_noreply_address_is_a_valid_identity(
    git_repo: Callable[[str, dict[str, bytes]], Path],
    commit: Callable[..., None],
    check_history: Callable[..., tuple[int, str]],
) -> None:
    """The author GitHub writes for an edit on its website is the owner too."""
    repository = git_repo("public", {"notes.txt": b"public\n"})
    commit(repository, {}, author=(DISPLAY_NAME, "12345+" + HANDLE_ADDRESS))

    assert check_history(repository) == (CLEAN, "")


def test_denied_text_in_an_otherwise_valid_identity_is_found(
    git_repo: Callable[[str, dict[str, bytes]], Path],
    commit: Callable[..., None],
    check_history: Callable[..., tuple[int, str]],
) -> None:
    """The deny list also reads the names and addresses of commits."""
    repository = git_repo("public", {"notes.txt": b"public\n"})
    commit(repository, {}, author=(DISPLAY_NAME, "12345+" + HANDLE_ADDRESS))

    assert check_history(repository, deny=("12345",))[0] == FINDINGS


def test_file_deleted_by_a_later_commit_is_still_gated(
    git_repo: Callable[[str, dict[str, bytes]], Path],
    commit: Callable[..., None],
    check_history: Callable[..., tuple[int, str]],
) -> None:
    """History is public too: removing a file does not unpublish it."""
    repository = git_repo("public", {"old.txt": MAC.encode()})
    commit(repository, {"old.txt": None})

    status, report = check_history(repository)

    assert status == FINDINGS
    assert f"old.txt: MAC address: {MAC}" in report


@pytest.mark.parametrize(
    "ref", ["refs/heads/side", "refs/tags/old", "refs/remotes/origin/main"]
)
def test_every_ref_is_gated_not_only_the_checked_out_branch(
    publish: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    commit: Callable[..., None],
    check_history: Callable[..., tuple[int, str]],
    ref: str,
) -> None:
    """A branch nobody looks at, a tag and a fetched ref are as public as main."""
    repository = git_repo("public", {"notes.txt": b"public\n"})
    clean = publish.git(repository, "rev-parse", "HEAD").decode().strip()
    commit(repository, {"leak.txt": MAC.encode()})
    publish.git(repository, "update-ref", ref, "HEAD")
    publish.git(repository, "update-ref", "refs/heads/main", clean)

    assert check_history(repository)[0] == FINDINGS


def test_ref_names_are_gated_and_annotated_tags_refused(
    publish: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    check_history: Callable[..., tuple[int, str]],
) -> None:
    """A ref name is public text, and a tag object holds text the gate skips."""
    repository = git_repo("public", {"notes.txt": b"public\n"})
    publish.git(repository, "branch", "zebulon-quux/draft")
    tagger = ("-c", "user.name=x", "-c", "user.email=x@example.org")
    publish.git(repository, *tagger, "tag", "--annotate", "--message=v1", "v1")

    status, report = check_history(repository, deny=("zebulon-quux",))

    assert status == FINDINGS
    assert sorted(line.split(": ")[1] for line in report.splitlines()) == [
        "annotated tag",
        "private deny",
    ]


def test_private_rules_gate_what_public_ci_cannot_know(
    git_repo: Callable[[str, dict[str, bytes]], Path],
    commit: Callable[..., None],
    check_history: Callable[..., tuple[int, str]],
) -> None:
    """With the rules, a denied name in an old path or a message is found."""
    repository = git_repo("public", {"docs/zebulon quux.org": b"x\n"})
    commit(repository, {"docs/zebulon quux.org": None}, "Remove a page")
    commit(repository, {}, "Thank Zebulon\nQuux")

    without_rules = check_history(repository)
    status, report = check_history(repository, deny=(DENIED_NAME,))

    assert without_rules == (CLEAN, "")
    assert status == FINDINGS
    assert [line.split(": ", 1)[1] for line in report.splitlines()] == [
        "private deny: zebulon quux",
        "private deny: zebulon quux",
    ]
    assert ":docs/zebulon quux.org: " in report


def test_check_acknowledges_what_the_given_allowlist_lists(
    git_repo: Callable[[str, dict[str, bytes]], Path],
    check_history: Callable[..., tuple[int, str]],
) -> None:
    """The allowlist of the clone waives a generic finding of its history."""
    repository = git_repo("public", {"notes.txt": MAC.encode()})

    assert check_history(repository, allow=f'values = ["{MAC}"]') == (CLEAN, "")


def test_check_without_a_readable_allowlist_is_invalid_input(
    publish: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    tmp_path: Path,
) -> None:
    """A missing allowlist is an error, not an empty one."""
    repository = git_repo("public", {"notes.txt": b"public\n"})
    arguments = ["check", str(repository), "--allow", str(tmp_path / "absent.toml")]

    assert publish.main(arguments) == INVALID_INPUT


def test_rewrite_history_applies_the_rules_and_keeps_every_commit(
    publish: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    commit: Callable[..., None],
    rewrite: Callable[..., tuple[int, Path]],
    tree_of: Callable[[Path], dict[str, bytes]],
) -> None:
    """Identities, paths, contents and messages are rewritten; no commit is lost."""
    work = ("piotr-yuxuan", "someone@corp.example")
    website = ("GitHub", "noreply@" + "github.com")
    origin = git_repo("origin", {"hosts/acme.nix": b"name = acme;\n"})
    trailer = "Tune acme\n\nCo-Authored-By: Bot <bot@example.org>"
    commit(origin, {"hosts/acme.nix": b"name = acme; # 2\n"}, trailer, work, work)
    numbered = (DISPLAY_NAME, "12345+" + HANDLE_ADDRESS)
    commit(origin, {}, "Edit on the website", numbered, website)
    commit(origin, {"hosts/acme.nix": b"name = example; # 2\n"}, "Rename by hand")
    mailmap = "".join(
        f"piotr-yuxuan <{HANDLE_ADDRESS}> <{address}>\n"
        for address in (work[1], website[1])
    )
    untouched = publish.git(origin, "log", "--all", "--format=%H %aI %cI")

    status, out = rewrite(origin, ("acme==>example",), mailmap)

    handle = f"piotr-yuxuan <{HANDLE_ADDRESS}>"
    log = publish.git(out, "log", "--format=%an <%ae>|%cn <%ce>|%B%x00").decode()
    assert status == CLEAN
    assert [entry.strip() for entry in log.split("\0")[:-1]] == [
        f"{handle}|{handle}|Rename by hand",
        f"{numbered[0]} <{numbered[1]}>|{handle}|Edit on the website",
        f"{handle}|{handle}|Tune example",
        f"{handle}|{handle}|Initial commit",
    ]
    assert tree_of(out) == {"hosts/example.nix": b"name = example; # 2\n"}
    assert publish.git(origin, "log", "--all", "--format=%H %aI %cI") == untouched
    assert [line.split(b" ", 1)[1] for line in untouched.splitlines()] == (
        publish.git(out, "log", "--all", "--format=%aI %cI").splitlines()
    )


def test_rewrite_history_rewrites_contents_exactly_as_the_sweep_does(
    publish: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    rewrite: Callable[..., tuple[int, Path]],
    rules_dir: Callable[..., Path],
    tree_of: Callable[[Path], dict[str, bytes]],
) -> None:
    """One rules file means the same to the export and to git filter-repo."""
    replacements = ("ab==>x", "regex:a+b==>y", r"regex:\bjo\b==>example")
    content = b"aab ab jo banjo\n"
    origin = git_repo("origin", {"notes.txt": content})

    status, out = rewrite(origin, replacements)

    rules = publish.load_rules(rules_dir(replacements=replacements))
    assert status == CLEAN
    assert tree_of(out) == {"notes.txt": b"ax x example banjo\n"}
    assert tree_of(out) == {"notes.txt": publish.sweep(rules, content)}


def test_rewrite_history_keeps_what_the_export_never_sweeps(
    publish: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    rewrite: Callable[..., tuple[int, Path]],
    tree_of: Callable[[Path], dict[str, bytes]],
) -> None:
    """A pinned hash or a file that is not text stays as it was in old commits."""
    kept = {
        "flake.lock": b'{"narHash": "sha256-acme"}\n',
        "legacy.txt": b"acme caf\xe9\n",
        "picture.png": b"\x89PNG\0acme\xff",
    }
    origin = git_repo("origin", {"notes.txt": b"acme\n", **kept})
    digests = (hashlib.sha256(kept[name]).hexdigest() for name in kept)
    allow = "sha256 = [" + ", ".join(f'"{digest}"' for digest in digests) + "]"
    (origin.parent / "history-allow.toml").write_text(allow, encoding="utf-8")

    _, out = rewrite(origin, ("acme==>example",))

    arguments = [
        "check",
        str(out),
        "--allow",
        str(origin.parent / "history-allow.toml"),
    ]
    assert publish.main(arguments) == CLEAN
    assert tree_of(out) == {"notes.txt": b"example\n", **kept}


def test_rewrite_history_reports_what_no_rule_removed(
    git_repo: Callable[[str, dict[str, bytes]], Path],
    commit: Callable[..., None],
    rewrite: Callable[..., tuple[int, Path]],
    capsys: pytest.CaptureFixture[str],
) -> None:
    """A rewrite is only clean once the whole rewritten history passes the gate."""
    origin = git_repo("origin", {"old.txt": MAC.encode()})
    commit(origin, {"old.txt": None})

    status, _ = rewrite(origin)

    assert status == FINDINGS
    assert f"old.txt: MAC address: {MAC}" in capsys.readouterr().out


def test_rewrite_history_drops_the_listed_paths_from_every_commit(
    publish: ModuleType,
    git_repo: Callable[[str, dict[str, bytes]], Path],
    commit: Callable[..., None],
    rewrite: Callable[..., tuple[int, Path]],
) -> None:
    """A picture that shows what no text rule can rewrite leaves the history."""
    picture = b"\x89PNG\0 a window title that names the host"
    origin = git_repo("origin", {"notes.txt": b"public\n"})
    commit(origin, {"shots/startup.png": picture}, "Add a screenshot")
    commit(origin, {"notes.txt": b"public, edited\n"}, "Edit the notes")

    status, out = rewrite(origin, remove=("# old screenshots", "shots/startup.png"))

    paths = publish.git(out, "log", "--all", "--format=", "--name-only")
    assert status == CLEAN
    assert set(paths.decode().split()) == {"notes.txt"}
    assert publish.git(out, "rev-list", "--count", "--all").strip() == b"3"


def test_rewrite_history_needs_a_new_directory(
    git_repo: Callable[[str, dict[str, bytes]], Path],
    rewrite: Callable[..., tuple[int, Path]],
    tmp_path: Path,
) -> None:
    """An earlier rewrite is never overwritten or mixed with a new one."""
    origin = git_repo("origin", {"notes.txt": b"public\n"})
    (tmp_path / "out/new.git").mkdir(parents=True)

    status, out = rewrite(origin)

    assert status == INVALID_INPUT
    assert list(out.iterdir()) == []


@pytest.mark.parametrize(
    "source", ["scripts/publish.py", "tests/test_publish.py", "tests/conftest.py"]
)
def test_sources_of_the_tool_pass_the_gate_they_implement(
    publish: ModuleType, scripts_dir: Path, source: str
) -> None:
    """The tool and its tests are published, under the allowlist published with them."""
    root = scripts_dir.parent
    # The overlay holds the allowlist here and becomes the root of the export.
    allowlist = next(
        candidate
        for candidate in (root / "publish/overlay/.github", root / ".github")
        if candidate.is_dir()
    )
    allow = publish.load_allow((allowlist / "publish-allow.toml").read_text("utf-8"))

    findings = publish.scan_entry(
        source, "100644", (root / source).read_bytes(), None, allow
    )

    assert findings == []

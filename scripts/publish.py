#!/usr/bin/env python3
"""Export a private repository to its public mirror, and gate what is published.

The public tree is a function of one private commit: a manifest selects the
files, private rules rename and rewrite them, and a gate that fails closed
refuses personal data. This code is public; the rules it reads are private.

It needs Python 3.13 or later and git, and git filter-repo to rewrite a
history.
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import os
import posixpath
import re
import subprocess
import sys
import tempfile
import tomllib
import unicodedata
from collections import Counter
from pathlib import Path
from typing import TYPE_CHECKING, NamedTuple

if TYPE_CHECKING:
    from collections.abc import Iterable, Mapping, Sequence

MANIFEST = "publish/manifest.toml"
OVERLAY = "publish/overlay/"
ALLOWLIST = ".github/publish-allow.toml"
# Rewriting a lock file would break the hashes it pins.
LOCK_FILE = re.compile(r"(?:\.lock|-lock\.json)$")
HANDLE = "piotr-yuxuan"
EXPORT_EMAIL = f"{HANDLE}@users.noreply.github.com"
EXPORT_MESSAGE = "Update configuration files "
SIGNING_KEY = re.compile(r"(?:0x)?([0-9A-Fa-f]{16,40})!?")
# Who may appear as author or committer of a public commit: the handle or the
# GitHub display name, at the handle's noreply address.
COMMIT_NAMES = frozenset({HANDLE, "胡雨軒 Петр"})
COMMIT_EMAIL = re.compile(rf"(?:\d+\+)?{HANDLE}@users\.noreply\.github\.com")
IDENTITY = re.compile(r"^(author|committer) (.*) <(.*)> \d+ [+-]\d{4}$", re.MULTILINE)
TRAILER = re.compile(r"^[ \t]*co-authored-by[ \t]*:.*$", re.IGNORECASE | re.MULTILINE)
# The file that the release pipeline of the public repository owns.
VERSION_FILE = ".version"
# The one commit that this pipeline makes, as a commit object: its single parent,
# who GitHub writes as author and committer, and its message. A history rewrite
# removes the signature.
VERSION_COMMIT = re.compile(
    rb"tree [0-9a-f]+\nparent (?P<parent>[0-9a-f]+)\n"
    rb"author github-actions\[bot\] "
    rb"<41898282\+github-actions\[bot\]@users\.noreply\.github\.com> \d+ [+-]\d{4}\n"
    rb"committer GitHub <noreply@github\.com> \d+ [+-]\d{4}\n"
    rb"(?:gpgsig .*\n(?: .*\n)*)?"
    rb"\nVersion (?P<version>(?:0|[1-9]\d*)(?:\.(?:0|[1-9]\d*)){2})\n\n\[skip ci\]\n?"
)
GIT_TIMEOUT_SECONDS = 600
GITLINK = "160000"
SYMLINK = "120000"
PUBLISHABLE_MODES = frozenset({"100644", "100755", SYMLINK})
LARGE_FILE_BYTES = 1 << 20
# A key id counts when a signing word stands within this many characters.
NEARBY_CHARACTERS = 160
# Among megabytes of arbitrary bytes a shorter deny match is chance, not data.
BINARY_MATCH_CHARACTERS = 6
# Unless it stands in a run of printable characters, ASCII or UTF-16, that is
# itself too long to be chance: there a deny entry counts whatever its length.
PRINTABLE_RUN = re.compile(rb"(?:[\x20-\x7e]\x00){12,}|[\x20-\x7e]{12,}")
# Body of the `git filter-repo` callback that rewrites the blobs of a history.
# It keeps what the export keeps: lock files and whatever is not UTF-8 text.
FILE_INFO_CALLBACK = f"""
contents = None if mode == b"{GITLINK}" else value.get_contents_by_identifier(blob_id)
swept = contents
if contents is not None and not re.search({LOCK_FILE.pattern.encode()!r}, filename):
    try:
        if b"\\0" not in contents[:8192]:
            contents.decode()
            swept = value.apply_replace_text(contents)
    except UnicodeDecodeError:
        pass
if swept != contents:
    blob_id = value.insert_file_with_contents(swept)
return (filename, mode, blob_id)
"""
ARCHIVE_MAGIC = (
    b"\x1f\x8b",  # gzip
    b"\x1f\x9d",  # compress
    b"BZh",  # bzip2
    b"PK\x03\x04",  # zip, and the formats built on it
    b"PK\x05\x06",  # empty zip
    b"\xfd7zXZ\x00",  # xz
    b"\x28\xb5\x2f\xfd",  # zstd
    b"\x04\x22\x4d\x18",  # lz4
    b"7z\xbc\xaf\x27\x1c",  # 7z
    b"Rar!\x1a\x07",  # rar
)
ARCHIVE_SUFFIXES = (
    ".7z",
    ".bz2",
    ".gz",
    ".jar",
    ".rar",
    ".tar",
    ".tgz",
    ".xz",
    ".zip",
    ".zst",
)
# Control characters, a backslash, bytes that are not UTF-8 (decoded as lone
# surrogates) or a `.git` component.
UNSAFE_PATH = re.compile(
    r"[\x00-\x1f\x7f\\\udc80-\udcff]|(?:^|/)\.git(?:/|$)", re.IGNORECASE
)

# One rule of replacements.txt, in the subset of the `git filter-repo`
# expressions syntax that this tool and filter-repo read the same way: exactly
# one `==>`, a non-empty source, no backslash in the replacement (filter-repo
# would expand it as a group reference), no glob and no carriage return.
REPLACEMENT_LINE = re.compile(
    rb"""(?!glob:) (?: (?P<regex>regex:) | literal: )?
         (?P<source> (?: (?!==>) [^\r] )+ ) ==> (?P<target> (?: (?!==>) [^\\\r] )* )
    """,
    re.VERBOSE,
)


class InvalidInputError(Exception):
    """A rules file, manifest or argument that cannot be trusted as written."""


class Allow(NamedTuple):
    """The public allowlist: generic findings acknowledged by their exact value."""

    values: frozenset[str]
    sha256: frozenset[str]


class Finding(NamedTuple):
    """One reason not to publish."""

    where: str
    check: str
    value: str


class Shape(NamedTuple):
    """A generic shape of secret or personal data.

    A match is reported unless `near` is set and matches nowhere around it,
    `exempt` matches the whole value, or the allowlist acknowledges a
    `waivable` value.
    """

    check: str
    pattern: re.Pattern[str]
    near: re.Pattern[str] | None = None
    exempt: re.Pattern[str] | None = None
    waivable: bool = True


SHAPES = (
    Shape(
        "key material",
        re.compile(
            r"-----BEGIN [A-Z0-9 ]*(?:PRIVATE KEY|KEY BLOCK)-----"
            r"|\b(?:ssh-(?:rsa|dss|ed25519)|ecdsa-sha2-nistp\d+) AAAA[\w+/=]{20,}"
            r"|AGE-SECRET-KEY-1[0-9A-Z]{20,}"
        ),
    ),
    Shape(
        "token",
        re.compile(
            r"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_\w{22,}|glpat-[\w-]{20,}"
            r"|A[KS]IA[0-9A-Z]{16}|xox[abprs]-[\w-]{10,}|sk-[A-Za-z0-9_-]{20,}"
            r"|AIza[\w-]{35}|eyJ[\w-]{10,}\.eyJ[\w-]{10,}\.[\w-]{10,})"
        ),
    ),
    Shape(
        "numeric-id noreply address",
        re.compile(r"\d+[+-][\w.-]+@users\.noreply\.git(?:hub|lab)\.com"),
        waivable=False,
    ),
    Shape(
        "e-mail address",
        # No domain label holds an underscore, and the last one is alphabetic.
        re.compile(r"[\w.%+-]+@(?:(?:[^\W_]|-)+\.)+[^\W\d_]{2,}"),
        exempt=re.compile(
            r".+@(?:[\w-]+\.)*(?:example\.(?:com|org|net)|example|invalid|test|localhost)"
        ),
    ),
    Shape(
        "MAC address",
        re.compile(
            r"(?<![0-9A-Fa-f:-])(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}(?![0-9A-Fa-f:-])"
        ),
    ),
    Shape(
        "UUID",
        re.compile(
            r"(?<![0-9A-Fa-f-])[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}"
            r"(?![0-9A-Fa-f-])"
        ),
    ),
    Shape("home directory", re.compile(r"(?<![\w.~-])/(?:home|Users)/[\w.-]+")),
    Shape(
        "key id",
        re.compile(r"\b(?:0x)?[0-9A-Fa-f]{16}\b|\b[0-9A-Fa-f]{40}\b"),
        near=re.compile(
            r"sign|gpg|pgp|fingerprint|key.?id|\b(?:sec|ssb|pub|sub)\s+[a-z]+\d+/",
            re.IGNORECASE,
        ),
    ),
    Shape(
        "key fingerprint",
        re.compile(r"\b[0-9A-F]{40}\b|\b(?:[0-9A-F]{4} +){9}[0-9A-F]{4}\b"),
    ),
)


class Rules(NamedTuple):
    """The private rules: what to rewrite and what must never be published."""

    literals: tuple[tuple[bytes, bytes], ...]
    regexes: tuple[tuple[re.Pattern[bytes], bytes], ...]
    deny: tuple[re.Pattern[str], ...]
    # Paths that a history rewrite drops from every commit.
    removals: tuple[bytes, ...]


def normalise(text: str) -> str:
    """Fold case, width, invisible characters and line wraps before deny matching."""
    visible = "".join(
        character
        for character in unicodedata.normalize("NFKC", text)
        if unicodedata.category(character) != "Cf"
    )
    return " ".join(visible.casefold().split())


def load_rules(directory: Path) -> Rules:
    """Read replacements.txt, deny.txt and remove.txt, refusing anything ambiguous.

    Deny entries are literals, or `regex:` patterns written for normalised
    (case-folded) text. remove.txt lists paths. In both, blank lines and `#`
    comments are skipped.
    """
    try:
        replacement_lines = (directory / "replacements.txt").read_bytes()
        deny_lines = (directory / "deny.txt").read_text(encoding="utf-8")
        removals = tuple(
            line
            for line in (directory / "remove.txt").read_bytes().splitlines()
            if line.strip() and not line.startswith(b"#")
        )
    except (OSError, UnicodeDecodeError) as error:
        message = f"{directory}: cannot read the rules: {error}"
        raise InvalidInputError(message) from error
    # Split on line feeds only, as filter-repo does when it iterates the file.
    *lines, unterminated = replacement_lines.split(b"\n")
    if unterminated:
        # A rule appended to the file would run into this one.
        message = "replacements.txt: the last line does not end with a newline"
        raise InvalidInputError(message)
    matches = [REPLACEMENT_LINE.fullmatch(line) for line in lines]
    rules = [match for match in matches if match]
    if len(rules) != len(lines):
        message = (
            f"replacements.txt line {matches.index(None) + 1}: expected FROM==>TO "
            "with one ==>, a non-empty FROM, no backslash in TO and no glob"
        )
        raise InvalidInputError(message)
    is_regex = [bool(rule["regex"]) for rule in rules]
    if is_regex != sorted(is_regex):
        # filter-repo applies every literal before any regex, whatever the order.
        message = "replacements.txt: literal rules must come before regex rules"
        raise InvalidInputError(message)
    try:
        regexes = tuple(
            (re.compile(rule["source"]), rule["target"])
            for rule in rules
            if rule["regex"]
        )
        deny = tuple(
            re.compile(
                line.removeprefix("regex:")
                if line.startswith("regex:")
                else re.escape(normalise(line))
            )
            for line in deny_lines.splitlines()
            if line.strip() and not line.startswith("#")
        )
    except re.error as error:
        message = f"{directory}: invalid pattern {error.pattern!r}: {error.msg}"
        raise InvalidInputError(message) from error
    literals = tuple(
        (rule["source"], rule["target"]) for rule in rules if not rule["regex"]
    )
    targets = [rule["target"] for rule in rules]
    problems = [] if deny else ["deny.txt has no entry, so nothing would be refused"]
    problems += [
        f"pattern {regex.pattern!r} matches the empty text"
        for regex, _ in regexes
        if regex.search(b"")
    ]
    problems += [
        f"pattern {pattern.pattern!r} matches the empty text"
        for pattern in deny
        if pattern.search("")
    ]
    problems += [
        f"path to remove {path!r} would be read as a rename"
        for path in removals
        if b"==>" in path
    ]
    problems += [
        f"replacement {target!r} would be rewritten again"
        for target in targets
        if any(source in target for source, _ in literals)
        or any(regex.search(target) for regex, _ in regexes)
    ]
    problems += [
        f"replacement {target!r} is on the deny list"
        for target in targets
        if any(
            pattern.search(normalise(target.decode(errors="replace")))
            for pattern in deny
        )
    ]
    if problems:
        message = f"{directory}: {'; '.join(problems)}"
        raise InvalidInputError(message)
    return Rules(literals, regexes, deny, removals)


def sweep(rules: Rules, data: bytes) -> bytes:
    """Rewrite bytes as `git filter-repo` does: every literal, then every regex."""
    for source, target in rules.literals:
        data = data.replace(source, target)
    for pattern, target in rules.regexes:
        data = pattern.sub(target, data)
    return data


def git(
    repository: Path,
    *arguments: str,
    stdin: bytes = b"",
    env: Mapping[str, str] | None = None,
) -> bytes:
    """Run git in a repository and return what it prints; any failure is fatal."""
    result = subprocess.run(
        ["git", "-C", str(repository), *arguments],
        input=stdin,
        capture_output=True,
        check=False,
        env=env,
        timeout=GIT_TIMEOUT_SECONDS,
    )
    if result.returncode != 0:
        reason = result.stderr.decode(errors="replace").strip()
        message = f"git {' '.join(arguments)} failed in {repository}: {reason}"
        raise InvalidInputError(message)
    return result.stdout


def list_tree(repository: Path, revision: str) -> list[tuple[str, str, str]]:
    """List a commit's files as (mode, object id, path), from the commit object."""
    entries = []
    listing = git(repository, "ls-tree", "-r", "-z", revision)
    for record in listing.split(b"\0")[:-1]:
        meta, _, path = record.partition(b"\t")
        mode, _kind, oid = meta.decode().split(" ")
        entries.append((mode, oid, path.decode(errors="surrogateescape")))
    return entries


def read_objects(repository: Path, oids: Iterable[str]) -> dict[str, bytes]:
    """Read git objects by id, through one `git cat-file --batch`."""
    wanted = sorted(set(oids))
    request = "".join(f"{oid}\n" for oid in wanted).encode()
    stream = git(repository, "cat-file", "--batch", stdin=request)
    objects = {}
    start = 0
    for oid in wanted:
        end_of_header = stream.index(b"\n", start)
        size = int(stream[start:end_of_header].split()[2])
        objects[oid] = stream[end_of_header + 1 : end_of_header + 1 + size]
        start = end_of_header + size + 2
    return objects


def load_allow(text: str) -> Allow:
    """Parse the public allowlist; an unknown key is refused, not ignored."""
    try:
        table = tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        message = f"allowlist: {error}"
        raise InvalidInputError(message) from error
    lists = [table.get("values", []), table.get("sha256", [])]
    if set(table) - {"values", "sha256"} or not all(
        isinstance(items, list) and all(isinstance(item, str) for item in items)
        for items in lists
    ):
        message = "allowlist: expected only `values` and `sha256`, lists of strings"
        raise InvalidInputError(message)
    return Allow(frozenset(lists[0]), frozenset(lists[1]))


def text_of(data: bytes) -> str | None:
    """Decode a blob, or return None for what git or UTF-8 calls binary."""
    if b"\0" in data[:8192]:
        return None
    try:
        return data.decode()
    except UnicodeDecodeError:
        return None


def denied(text: str, where: str, rules: Rules | None) -> list[Finding]:
    """Report what the private deny list forbids; no allowlist waives it."""
    if rules is None:
        return []
    folded = normalise(text)
    return [
        Finding(where, "private deny", match.group())
        for pattern in rules.deny
        for match in pattern.finditer(folded)
    ]


def suspicious(text: str, where: str, allow: Allow) -> list[Finding]:
    """Report generic shapes of secrets and personal data left unacknowledged."""
    findings = []
    for shape in SHAPES:
        for match in shape.pattern.finditer(text):
            value = match.group()
            around = (max(0, match.start() - NEARBY_CHARACTERS), match.end())
            if shape.near and not shape.near.search(
                text, around[0], around[1] + NEARBY_CHARACTERS
            ):
                continue
            if shape.exempt and shape.exempt.fullmatch(value):
                continue
            if shape.waivable and value in allow.values:
                continue
            findings.append(Finding(where, shape.check, value))
    return findings


def scan_entry(
    path: str, mode: str, data: bytes, rules: Rules | None, allow: Allow
) -> list[Finding]:
    """Gate one entry of a tree: its path, its mode and its content."""
    findings = denied(path, path, rules) + suspicious(path, path, allow)
    if UNSAFE_PATH.search(path) or path != unicodedata.normalize("NFC", path):
        findings.append(Finding(path, "path hygiene", path))
    if mode not in PUBLISHABLE_MODES:
        return [*findings, Finding(path, "entry mode", mode)]
    text = text_of(data)
    digest = hashlib.sha256(data).hexdigest()
    if mode == SYMLINK:
        target = posixpath.join(posixpath.dirname(path), text or "/")
        if posixpath.normpath(target).startswith(("/", "..")):
            findings.append(Finding(path, "symlink leaves the tree", repr(data)))
    elif (
        data.startswith(ARCHIVE_MAGIC)
        or data[257:262] == b"ustar"
        or path.lower().endswith(ARCHIVE_SUFFIXES)
    ):
        findings.append(Finding(path, "archive or compressed file", digest))
    elif (text is None or len(data) > LARGE_FILE_BYTES) and digest not in allow.sha256:
        findings.append(Finding(path, "binary or large file not allowlisted", digest))
    if text is None:
        # Raw bytes, the same without NUL (UTF-16) and what decodes as UTF-8.
        views = (
            data.decode("latin-1"),
            data.replace(b"\0", b"").decode("latin-1"),
            data.decode(errors="ignore"),
        )
        strings = "\n".join(
            run.replace(b"\0", b"").decode("ascii")
            for run in PRINTABLE_RUN.findall(data)
        )
        return [
            *findings,
            *denied(strings, path, rules),
            *(
                finding
                for view in views
                for finding in denied(view, path, rules)
                if len(finding.value) >= BINARY_MATCH_CHARACTERS
            ),
        ]
    return findings + denied(text, path, rules) + suspicious(text, path, allow)


def version_commits(
    raw: Mapping[str, bytes],
    trees: Mapping[str, Sequence[tuple[str, str, str]]],
    blobs: Mapping[str, bytes],
) -> set[str]:
    """Name the commits that raise the version as the public pipeline does.

    Such a commit has the identities, the message and the single parent of
    `VERSION_COMMIT`, and differs from that parent by the version file alone,
    a plain file that holds the version of the message. `raw` maps a commit to
    its object, `trees` to its entries as `list_tree` gives them, and `blobs`
    an object id to its content.
    """
    found = set()
    for commit, data in raw.items():
        claim = VERSION_COMMIT.fullmatch(data)
        if claim is None:
            continue
        parent = trees.get(claim["parent"].decode(), ())
        changed = {path for _, _, path in set(trees[commit]) ^ set(parent)}
        written = [
            (mode, blobs.get(oid))
            for mode, oid, path in trees[commit]
            if path == VERSION_FILE
        ]
        version = ("100644", claim["version"] + b"\n")
        if changed == {VERSION_FILE} and written == [version]:
            found.add(commit)
    return found


def scan_commit(
    raw: bytes,
    where: str,
    rules: Rules | None,
    allow: Allow,
    *,
    version_commit: bool = False,
) -> list[Finding]:
    """Gate one commit object: who made it and what its message says.

    A version commit of the public pipeline is not made by the owner: only the
    rule on who may make a commit is skipped for it.
    """
    header, _, message = raw.decode(errors="replace").partition("\n\n")
    findings = denied(message, where, rules) + suspicious(message, where, allow)
    findings += [
        Finding(where, "attribution trailer", line.strip())
        for line in TRAILER.findall(message)
    ]
    people = IDENTITY.findall(header)
    if [role for role, _, _ in people] != ["author", "committer"]:
        findings.append(Finding(where, "commit identity", "unreadable header"))
    for role, name, email in people:
        person = f"{name} <{email}>"
        if not version_commit and (
            name not in COMMIT_NAMES or not COMMIT_EMAIL.fullmatch(email)
        ):
            findings.append(Finding(where, f"{role} identity", person))
        findings += denied(person, where, rules)
    return findings


def public_tree(
    private: dict[str, tuple[str, bytes]], rules: Rules
) -> tuple[dict[str, tuple[str, bytes]], list[Finding]]:
    """Select, sweep and overlay a private tree, given as path to (mode, content).

    Return the public tree and what the manifest or the rules leave undecided.
    Exclude wins over include, and `publish/` only contributes its overlay.
    Neither may write the version file, which the public pipeline owns.
    """
    try:
        manifest = tomllib.loads(private[MANIFEST][1].decode())
        include, exclude, swept = (
            manifest.pop(key) for key in ("include", "exclude", "sweep")
        )
        patterns = {
            pattern: re.compile(
                glob.translate(pattern, recursive=True, include_hidden=True)
            )
            for pattern in [*include, *exclude]
        }
    except (KeyError, TypeError, ValueError) as error:
        message = f"{MANIFEST}: expected include, exclude and sweep: {error!r}"
        raise InvalidInputError(message) from error
    if manifest or not (
        isinstance(include, list)
        and isinstance(exclude, list)
        and isinstance(swept, bool)
    ):
        message = f"{MANIFEST}: expected two lists and a boolean, and no other key"
        raise InvalidInputError(message)
    candidates = [path for path in private if not path.startswith("publish/")]
    matched = {
        pattern: {path for path in candidates if regex.match(path)}
        for pattern, regex in patterns.items()
    }
    excluded = set().union(*(matched[pattern] for pattern in exclude))
    included = set().union(*(matched[pattern] for pattern in include)) - excluded
    findings = [
        Finding(path, "unclassified path", path)
        for path in candidates
        if path not in included | excluded
    ]
    findings += [
        Finding(MANIFEST, "stale pattern", pattern)
        for pattern, paths in matched.items()
        if not paths
    ]
    tree = {}
    for path in sorted(included):
        mode, data = private[path]
        sweepable = not LOCK_FILE.search(path) and text_of(data) is not None
        new_data = sweep(rules, data) if sweepable else data
        raw_path = sweep(rules, path.encode(errors="surrogateescape"))
        new_path = raw_path.decode(errors="surrogateescape")
        if sweep(rules, raw_path) != raw_path or (
            sweepable and sweep(rules, new_data) != new_data
        ):
            findings.append(Finding(path, "unstable replacement", new_path))
        if not swept and (new_path, new_data) != (path, data):
            findings.append(Finding(path, "rule applies but sweep is false", path))
        if new_path in tree:
            findings.append(Finding(new_path, "path collision", path))
        tree[new_path] = (mode, new_data)
    overlay = {
        path.removeprefix(OVERLAY): entry
        for path, entry in private.items()
        if path.startswith(OVERLAY)
    }
    findings += [
        Finding(path, "overlay collision", path) for path in overlay.keys() & tree
    ]
    tree |= overlay
    findings += [
        Finding(path, "reserved path", path)
        for path in tree
        if unicodedata.normalize("NFC", path).casefold().split("/")[0] == VERSION_FILE
    ]
    folded = Counter(unicodedata.normalize("NFC", path).casefold() for path in tree)
    findings += [
        Finding(path, "path collision ignoring case", path)
        for path in tree
        if folded[unicodedata.normalize("NFC", path).casefold()] > 1
    ]
    return tree, findings


def export(
    source: Path, commit: str, rules: Path, public: Path, signing_key: str
) -> list[Finding]:
    """Publish one private commit as one signed commit of the public clone.

    The private tree is read from the commit object, never from the work
    tree. The version file of the public head is kept as it is. Nothing is
    written to the public clone unless the tree passes the gate, and its
    branch only moves once the new commit passes it too.
    """
    loaded = load_rules(rules)
    key = SIGNING_KEY.fullmatch(signing_key)
    if key is None:
        message = f"signing key {signing_key!r} is not a hexadecimal key id"
        raise InvalidInputError(message)
    git(public, "symbolic-ref", "HEAD")
    if git(public, "status", "--porcelain"):
        message = f"{public} has local changes; the export only fast-forwards it"
        raise InvalidInputError(message)
    revision = git(source, "rev-parse", "--verify", f"{commit}^{{commit}}")
    revision = revision.decode().strip()
    history = set(git(source, "rev-list", revision).split())
    if history.intersection(git(public, "rev-list", "--all").split()):
        # The source itself, or a clone of it, given as the public clone.
        message = f"{public} holds commits of the private history: not a public clone"
        raise InvalidInputError(message)
    listing = list_tree(source, revision)
    blobs = read_objects(source, [oid for mode, oid, _ in listing if mode != GITLINK])
    private = {path: (mode, blobs.get(oid, b"")) for mode, oid, path in listing}
    tree, findings = public_tree(private, loaded)
    # The pipeline of the public repository raises the version file between two
    # exports: the new commit keeps the one of the public head.
    tree |= {
        path: (mode, git(public, "cat-file", "blob", oid))
        for mode, oid, path in list_tree(public, "HEAD")
        if path == VERSION_FILE
    }
    allow = load_allow(tree[ALLOWLIST][1].decode() if ALLOWLIST in tree else "")
    for path, (mode, data) in tree.items():
        findings += scan_entry(path, mode, data, loaded, allow)
    if findings:
        return findings
    with tempfile.TemporaryDirectory() as scratch:
        index = {**os.environ, "GIT_INDEX_FILE": str(Path(scratch) / "index")}
        records = b""
        for path, (mode, data) in tree.items():
            blob = git(
                public, "hash-object", "-w", "--no-filters", "--stdin", stdin=data
            )
            records += f"{mode} {blob.decode().strip()}\t".encode()
            records += path.encode(errors="surrogateescape") + b"\0"
        git(public, "update-index", "-z", "--index-info", stdin=records, env=index)
        new_tree = git(public, "write-tree", env=index).decode().strip()
    head = git(public, "rev-parse", "--verify", "HEAD^{commit}").decode().strip()
    if new_tree == git(public, "rev-parse", "HEAD^{tree}").decode().strip():
        sys.stdout.write("Nothing to publish: the public tree is up to date.\n")
        return []
    date = git(source, "log", "-1", "--no-show-signature", "--format=%cI", revision)
    date = date.decode().strip()
    identity = {
        f"GIT_{role}_{field}": value
        for role in ("AUTHOR", "COMMITTER")
        for field, value in (("NAME", HANDLE), ("EMAIL", EXPORT_EMAIL), ("DATE", date))
    }
    # The key, the signature format and the identity are all given here, so
    # that nothing from the ambient git configuration reaches the commit.
    new = git(
        public,
        "-c",
        "gpg.format=openpgp",
        "commit-tree",
        f"-S{key[1]}",
        "-p",
        head,
        "-m",
        EXPORT_MESSAGE,
        new_tree,
        env={**os.environ, **identity},
    )
    new = new.decode().strip()
    where = f"commit {new[:12]}"
    findings = scan_commit(read_objects(public, [new])[new], where, loaded, allow)
    signature = ("log", "-1", "--no-show-signature", "--format=%G?%n%GF%n%GP")
    status, *signers = git(public, *signature, new).split()
    if status not in {b"G", b"U"} or not any(
        signer.upper().endswith(key[1].upper().encode()) for signer in signers
    ):
        findings.append(Finding(where, "signature", f"{status!r} by {signers!r}"))
    if not findings:
        git(public, "merge", "--ff-only", "--quiet", new)
        sys.stdout.write(f"Published {revision[:12]} as {new[:12]} in {public}.\n")
    return findings


def check(clone: Path, allow: Path, rules: Path | None) -> list[Finding]:
    """Gate every ref of a clone: its name, its commits and all their trees.

    Without rules only the generic checks run, as in public CI. An annotated
    tag is refused, since its tagger and message are not read. Every commit is
    made by the owner, except the version commits of the public pipeline.
    """
    loaded = load_rules(rules) if rules else None
    try:
        allowed = load_allow(allow.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError) as error:
        message = f"{allow}: cannot read the allowlist: {error}"
        raise InvalidInputError(message) from error
    commits = git(clone, "rev-list", "--all").decode().split()
    raw = read_objects(clone, commits)
    findings = []
    refs = git(clone, "for-each-ref", "--format=%(objecttype) %(refname)")
    for line in refs.decode(errors="replace").splitlines():
        kind, _, ref = line.partition(" ")
        findings += denied(ref, ref, loaded) + suspicious(ref, ref, allowed)
        if kind == "tag":
            findings.append(Finding(ref, "annotated tag", "not gated, use a plain tag"))
    trees = {commit: list_tree(clone, commit) for commit in commits}
    newest: dict[tuple[str, str, str], str] = {}
    for commit in commits:
        for entry in trees[commit]:
            newest.setdefault(entry, commit)
    blobs = read_objects(clone, [oid for mode, oid, _ in newest if mode != GITLINK])
    versions = version_commits(raw, trees, blobs)
    findings += [
        finding
        for commit in commits
        for finding in scan_commit(
            raw[commit],
            f"commit {commit[:12]}",
            loaded,
            allowed,
            version_commit=commit in versions,
        )
    ]
    for (mode, oid, path), commit in newest.items():
        findings += [
            finding._replace(where=f"{commit[:12]}:{finding.where}")
            for finding in scan_entry(path, mode, blobs.get(oid, b""), loaded, allowed)
        ]
    return findings


def rewrite_history(origin: str, rules: Path, allow: Path, out: Path) -> list[Finding]:
    """Clone a public repository and rewrite the clone with `git filter-repo`.

    The private rules rewrite contents, messages and paths, and drop the
    paths of remove.txt; the mailmap rewrites identities; attribution
    trailers are removed. Every commit is kept, with its dates, and loses
    its signature. The result is gated like any history; the origin is never
    touched.
    """
    loaded = load_rules(rules)
    # git runs inside the new clone, where a relative path would not resolve.
    rules = rules.resolve()
    if out.exists():
        message = f"{out} already exists; the rewrite needs a new directory"
        raise InvalidInputError(message)
    git(Path(), "clone", "--quiet", "--bare", "--no-local", origin, str(out))
    dates = ("log", "--all", "--format=%aI %cI")
    before = sorted(git(out, *dates).splitlines())
    with tempfile.TemporaryDirectory() as scratch:
        # With --invert-paths a line without `==>` drops a path. The others
        # rename, in file order as the sweep does: the parser keeps every
        # literal rule before any regex rule.
        paths = Path(scratch) / "paths"
        paths.write_bytes(
            b"".join(b"literal:" + path + b"\n" for path in loaded.removals)
            + b"".join(
                b"regex:" + pattern + b"==>" + target + b"\n"
                for pattern, target in (
                    *(
                        (re.escape(source), target)
                        for source, target in loaded.literals
                    ),
                    *((regex.pattern, target) for regex, target in loaded.regexes),
                )
            )
        )
        messages = Path(scratch) / "messages"
        messages.write_bytes(
            (rules / "replacements.txt").read_bytes()
            + b"regex:(?im)^[ \\t]*co-authored-by[ \\t]*:.*\\n?==>\n"
        )
        git(
            out,
            "filter-repo",
            *("--replace-text", str(rules / "replacements.txt")),
            *("--file-info-callback", FILE_INFO_CALLBACK),
            *("--replace-message", str(messages)),
            *("--paths-from-file", str(paths), "--invert-paths"),
            *("--mailmap", str(rules / "mailmap")),
            *("--prune-empty", "never", "--prune-degenerate", "never"),
        )
    after = sorted(git(out, *dates).splitlines())
    findings = check(out, allow, rules)
    if before != after:
        counts = f"{len(before)} commits before, {len(after)} after"
        findings.append(Finding(str(out), "commits or dates changed", counts))
    return findings


COMMANDS = {"export": export, "check": check, "rewrite-history": rewrite_history}


def main(argv: Sequence[str] | None = None) -> int:
    """Run one command: 0 when clean, 1 on findings, 2 on invalid input."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    exporting = commands.add_parser("export", help=export.__doc__)
    exporting.add_argument("--source", type=Path, required=True)
    exporting.add_argument("--commit", required=True)
    exporting.add_argument("--rules", type=Path, required=True)
    exporting.add_argument("--public", type=Path, required=True)
    exporting.add_argument("--signing-key", required=True)
    checking = commands.add_parser("check", help=check.__doc__)
    checking.add_argument("clone", type=Path)
    checking.add_argument("--allow", type=Path, required=True)
    checking.add_argument("--rules", type=Path)
    rewriting = commands.add_parser("rewrite-history", help=rewrite_history.__doc__)
    rewriting.add_argument("--origin", required=True)
    rewriting.add_argument("--rules", type=Path, required=True)
    rewriting.add_argument("--allow", type=Path, required=True)
    rewriting.add_argument("--out", type=Path, required=True)
    arguments = vars(parser.parse_args(argv))
    command = COMMANDS[arguments.pop("command")]
    try:
        findings = command(**arguments)
    except (InvalidInputError, subprocess.TimeoutExpired) as error:
        sys.stderr.write(f"publish.py: {error}\n")
        return 2
    for finding in sorted(set(findings)):
        line = f"{finding.where}: {finding.check}: {finding.value}\n"
        sys.stdout.write(line.encode(errors="backslashreplace").decode())
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())

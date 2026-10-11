"""Shared pytest fixtures for the test suite.

All test files should import fixtures from here rather than duplicating
setup logic.
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType
from typing import Callable, Iterator

import pytest


@pytest.fixture(scope="session")
def scripts_dir() -> Path:
    """Return the absolute path to the scripts/ directory.

    Computed relative to this conftest file so test files do not need to
    re-derive the path themselves.
    """
    return Path(__file__).resolve().parent.parent / "scripts"


@pytest.fixture()
def fake_sysfs(tmp_path: Path) -> Callable[[dict[str, str]], Path]:
    """Build a temporary /sys/class/input-like directory tree.

    Returns a callable that accepts a dict mapping event-node names to
    device name strings and returns the sysfs root path.

    Example::

        sysfs = fake_sysfs({"event2": "PIXA3854:00 093A:0274 Touchpad"})
    """

    def _build(devices: dict[str, str]) -> Path:
        sysfs = tmp_path / "sys" / "class" / "input"
        for node, name in devices.items():
            d = sysfs / node / "device"
            d.mkdir(parents=True)
            (d / "name").write_text(name + "\n")
        return sysfs

    return _build


@pytest.fixture()
def fifo_factory(tmp_path: Path) -> Callable[[str], Path]:
    """Create named FIFOs inside a tmp_path subdirectory.

    Returns a callable ``make_fifo(name) -> Path`` that creates a FIFO
    at ``tmp_path/fifos/<name>`` and returns its path.
    """
    fifo_dir = tmp_path / "fifos"
    fifo_dir.mkdir()

    def make_fifo(name: str) -> Path:
        """Create a named FIFO and return its Path."""
        path = fifo_dir / name
        os.mkfifo(path)
        return path

    return make_fifo


@pytest.fixture()
def write_to_fifo() -> Callable[[Path, bytes], int]:
    """Return a callable that forks a child to write bytes to a FIFO.

    Usage::

        pid = write_to_fifo(fifo_path, b"raw bytes")
        # ... read from the FIFO ...
        os.waitpid(pid, 0)

    The caller is responsible for calling ``os.waitpid`` on the returned PID.
    """

    def write(path: Path, raw_bytes: bytes) -> int:
        """Fork a child that writes raw_bytes to path, then exits.

        Returns the child PID.
        """
        pid = os.fork()
        if pid == 0:
            fd = os.open(str(path), os.O_WRONLY)
            os.write(fd, raw_bytes)
            os.close(fd)
            os._exit(0)
        return pid

    return write


@pytest.fixture(scope="session")
def publish(scripts_dir: Path) -> ModuleType:
    """Load scripts/publish.py, which is a script and not a package module."""
    loader = SourceFileLoader("publish", str(scripts_dir / "publish.py"))
    module = ModuleType(loader.name)
    loader.exec_module(module)
    return module


@pytest.fixture
def rules_dir(tmp_path: Path) -> Callable[..., Path]:
    """Write a private rules directory for scripts/publish.py.

    Returns ``make(replacements=(), deny=DENY, mailmap="", remove=()) -> Path``.
    Each replacement, deny entry and path to remove is one line of its file.
    The default deny list holds one entry that no test content contains.
    """

    def make(
        replacements: tuple[str, ...] = (),
        deny: tuple[str, ...] = ("a-name-no-test-writes",),
        mailmap: str = "",
        remove: tuple[str, ...] = (),
    ) -> Path:
        directory = tmp_path / "rules"
        directory.mkdir(exist_ok=True)
        (directory / "replacements.txt").write_bytes(
            "".join(f"{line}\n" for line in replacements).encode()
        )
        (directory / "deny.txt").write_text(
            "".join(f"{line}\n" for line in deny), encoding="utf-8"
        )
        (directory / "mailmap").write_text(mailmap, encoding="utf-8")
        (directory / "remove.txt").write_text(
            "".join(f"{line}\n" for line in remove), encoding="utf-8"
        )
        return directory

    return make


HANDLE = ("piotr-yuxuan", "piotr-yuxuan@users.noreply.github.com")


@pytest.fixture
def commit(publish: ModuleType) -> Callable[..., None]:
    """Add commits whose identity does not depend on the environment.

    Returns ``add(repository, files, message="Add files", author=HANDLE,
    committer=HANDLE)``. ``files`` maps a path to its bytes, or to ``None`` to
    delete it; ``author`` and ``committer`` are ``(name, e-mail)`` pairs.
    """

    def add(
        repository: Path,
        files: dict[str, bytes | None],
        message: str = "Add files",
        author: tuple[str, str] = HANDLE,
        committer: tuple[str, str] = HANDLE,
    ) -> None:
        for path, data in files.items():
            if data is None:
                (repository / path).unlink()
            else:
                (repository / path).parent.mkdir(parents=True, exist_ok=True)
                (repository / path).write_bytes(data)
        publish.git(repository, "add", "--all")
        # Where the file system ignores case, as on macOS, two paths that differ by
        # case only are one file, and git staged one name. The index takes the other
        # one directly.
        staged = publish.git(repository, "ls-files", "-z").split(b"\0")
        for path, data in files.items():
            if data is not None and path.encode() not in staged:
                blob = publish.git(
                    repository, "hash-object", "-w", "--stdin", stdin=data
                )
                entry = f"100644,{blob.decode().strip()},{path}"
                publish.git(repository, "update-index", "--add", "--cacheinfo", entry)
        identity = {
            "GIT_AUTHOR_NAME": author[0],
            "GIT_AUTHOR_EMAIL": author[1],
            "GIT_COMMITTER_NAME": committer[0],
            "GIT_COMMITTER_EMAIL": committer[1],
        }
        publish.git(
            repository,
            *("commit", "--quiet", "--allow-empty", f"--message={message}"),
            env={**os.environ, **identity},
        )

    return add


@pytest.fixture
def git_repo(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    publish: ModuleType,
    commit: Callable[..., None],
) -> Callable[[str, dict[str, bytes]], Path]:
    """Create git repositories isolated from the user's git configuration.

    Returns ``make(name, files) -> Path``: a repository at ``tmp_path/name``
    whose single commit holds ``files``, a mapping from path to bytes. Every
    git process of the test, the tool's included, ignores the system and the
    user configuration.
    """
    monkeypatch.setenv("GIT_CONFIG_GLOBAL", os.devnull)
    monkeypatch.setenv("GIT_CONFIG_NOSYSTEM", "1")

    def make(name: str, files: dict[str, bytes]) -> Path:
        publish.git(tmp_path, "init", "--quiet", "--initial-branch=main", name)
        commit(tmp_path / name, files, "Initial commit")
        return tmp_path / name

    return make


@pytest.fixture
def tree_of(publish: ModuleType) -> Callable[[Path], dict[str, bytes]]:
    """Return ``read(repository) -> {path: content}`` for its HEAD commit.

    It asks git for each path and each blob, without the tool's own readers.
    """

    def read(repository: Path) -> dict[str, bytes]:
        names = publish.git(repository, "ls-tree", "-r", "-z", "--name-only", "HEAD")
        return {
            path.decode(): publish.git(repository, "cat-file", "blob", b"HEAD:" + path)
            for path in names.split(b"\0")[:-1]
        }

    return read


@pytest.fixture(scope="session")
def gpg_home() -> Iterator[tuple[Path, str]]:
    """Create a GnuPG home holding one signing key without passphrase.

    Yields ``(home, fingerprint)`` and stops the agent of that home afterwards.
    """
    # The agent listens on sockets inside this directory, and the path of a socket is
    # limited to about a hundred characters. The temporary directory of pytest is too
    # deep for that on macOS, so the home sits directly below /tmp.
    with tempfile.TemporaryDirectory(prefix="gnupg-", dir="/tmp") as directory:
        home = Path(directory)
        env = {**os.environ, "GNUPGHOME": str(home)}
        generate = ["--pinentry-mode", "loopback", "--passphrase", ""]
        generate += ["--quick-generate-key", "Export test", "ed25519", "sign", "never"]
        # What gpg says is left to pytest, which shows it when the fixture fails.
        subprocess.run(
            ["gpg", "--batch", *generate],
            env=env,
            check=True,
            stdout=subprocess.DEVNULL,
        )
        listing = subprocess.run(
            ["gpg", "--batch", "--list-secret-keys", "--with-colons"],
            env=env,
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        )
        fingerprint = next(
            line.split(":")[9]
            for line in listing.stdout.splitlines()
            if line.startswith("fpr")
        )
        yield home, fingerprint
        subprocess.run(
            ["gpgconf", "--kill", "all"], env=env, check=False, capture_output=True
        )


@pytest.fixture
def signing_key(gpg_home: tuple[Path, str], monkeypatch: pytest.MonkeyPatch) -> str:
    """Point GnuPG at a throwaway home; return the fingerprint of its key."""
    home, fingerprint = gpg_home
    monkeypatch.setenv("GNUPGHOME", str(home))
    return fingerprint


@pytest.fixture
def public_clone(git_repo: Callable[[str, dict[str, bytes]], Path]) -> Path:
    """Create a public clone whose single commit holds a ``README``."""
    return git_repo("public", {"README": b"before the export\n"})


@pytest.fixture
def export(
    publish: ModuleType, rules_dir: Callable[..., Path], signing_key: str
) -> Callable[..., int]:
    """Run ``publish.py export`` on the HEAD commit of a private repository.

    Returns ``run(source, public, replacements=(), deny=None, commit="HEAD")
    -> exit status``; without ``deny`` the rules keep their default entry.
    """

    def run(
        source: Path,
        public: Path,
        replacements: tuple[str, ...] = (),
        deny: tuple[str, ...] | None = None,
        commit: str = "HEAD",
    ) -> int:
        rules = rules_dir(replacements=replacements, **({"deny": deny} if deny else {}))
        arguments = ["--source", str(source), "--commit", commit]
        arguments += ["--rules", str(rules), "--public", str(public)]
        return publish.main(["export", *arguments, "--signing-key", signing_key])

    return run


@pytest.fixture
def export_files(
    export: Callable[..., int],
    git_repo: Callable[[str, dict[str, bytes]], Path],
    public_clone: Path,
    tree_of: Callable[[Path], dict[str, bytes]],
) -> Callable[..., tuple[int, dict[str, bytes]]]:
    """Export a private repository made of ``files`` into the public clone.

    Returns ``run(files, replacements=(), deny=None) -> (exit status, public
    tree)``, the tree being that of the public HEAD after the export.
    """

    def run(
        files: dict[str, bytes],
        replacements: tuple[str, ...] = (),
        deny: tuple[str, ...] | None = None,
    ) -> tuple[int, dict[str, bytes]]:
        status = export(git_repo("private", files), public_clone, replacements, deny)
        return status, tree_of(public_clone)

    return run


@pytest.fixture
def work_identity(monkeypatch: pytest.MonkeyPatch) -> None:
    """Surround the test with a work identity, in git's configuration and env.

    The configuration is given through ``GIT_CONFIG_COUNT``, which no
    configuration file overrides.
    """
    settings = {
        "user.name": "Work Name",
        "user.email": "work@corp.example",
        "user.signingKey": "WORK-KEY",
        "gpg.format": "ssh",
        "log.showSignature": "true",
    }
    monkeypatch.setenv("GIT_CONFIG_COUNT", str(len(settings)))
    for index, (key, value) in enumerate(settings.items()):
        monkeypatch.setenv(f"GIT_CONFIG_KEY_{index}", key)
        monkeypatch.setenv(f"GIT_CONFIG_VALUE_{index}", value)
    for variable in ("GIT_AUTHOR_NAME", "GIT_COMMITTER_NAME"):
        monkeypatch.setenv(variable, "Work Name")
    for variable in ("GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL", "EMAIL"):
        monkeypatch.setenv(variable, "work@corp.example")


@pytest.fixture
def check_history(
    publish: ModuleType,
    rules_dir: Callable[..., Path],
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> Callable[..., tuple[int, str]]:
    """Run ``publish.py check`` on a repository.

    Returns ``run(repository, allow="", deny=None) -> (exit status, report)``.
    ``allow`` is the text of the allowlist; the private rules are given only
    when ``deny`` is, as public CI runs without them.
    """

    def run(
        repository: Path, allow: str = "", deny: tuple[str, ...] | None = None
    ) -> tuple[int, str]:
        allowlist = tmp_path / "allow.toml"
        allowlist.write_text(allow, encoding="utf-8")
        arguments = ["check", str(repository), "--allow", str(allowlist)]
        if deny is not None:
            arguments += ["--rules", str(rules_dir(deny=deny))]
        status = publish.main(arguments)
        return status, capsys.readouterr().out

    return run


@pytest.fixture
def rewrite(
    publish: ModuleType,
    rules_dir: Callable[..., Path],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> Callable[..., tuple[int, Path]]:
    """Run ``publish.py rewrite-history`` on a repository, with an empty allowlist.

    Returns ``run(origin, replacements=(), mailmap="", remove=()) -> (exit
    status, rewritten bare repository)``. The command runs from ``tmp_path``
    with relative paths, the origin's included, and writes into a directory
    below it, as from a repository root.
    """

    def run(
        origin: Path,
        replacements: tuple[str, ...] = (),
        mailmap: str = "",
        remove: tuple[str, ...] = (),
    ) -> tuple[int, Path]:
        (tmp_path / "allow.toml").write_text("", encoding="utf-8")
        rules = rules_dir(replacements=replacements, mailmap=mailmap, remove=remove)
        monkeypatch.chdir(tmp_path)
        (tmp_path / "out").mkdir(exist_ok=True)
        arguments = ["--origin", origin.relative_to(tmp_path).as_posix()]
        arguments += ["--rules", rules.name, "--allow", "allow.toml"]
        status = publish.main(["rewrite-history", *arguments, "--out", "out/new.git"])
        return status, tmp_path / "out/new.git"

    return run


@pytest.fixture(scope="session")
def release(scripts_dir: Path) -> ModuleType:
    """Load scripts/release.py, which is a script and not a package module."""
    loader = SourceFileLoader("release", str(scripts_dir / "release.py"))
    module = ModuleType(loader.name)
    loader.exec_module(module)
    return module


@pytest.fixture
def fake_gh(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> Callable[..., Callable[[], list[list[object]]]]:
    """Put ``tests/helpers/fake_gh.py`` first on the ``PATH``, as ``gh``.

    Returns ``install(replies, failing=()) -> sent``. ``replies`` maps
    ``"METHOD path"`` to the JSON value that ``gh api`` prints for that request;
    a request named in ``failing`` exits with status 1 instead. ``sent()`` lists
    the requests received so far, each as ``[method, path, body]``. No request
    leaves the machine.
    """
    home = tmp_path / "fake-gh"
    (home / "bin").mkdir(parents=True)
    (home / "bin/gh").symlink_to(Path(__file__).parent / "helpers/fake_gh.py")
    monkeypatch.setenv("FAKE_GH_HOME", str(home))
    monkeypatch.setenv("PATH", f"{home / 'bin'}{os.pathsep}{os.environ['PATH']}")

    def install(
        replies: dict[str, object], failing: tuple[str, ...] = ()
    ) -> Callable[[], list[list[object]]]:
        script = {"replies": replies, "failing": list(failing)}
        (home / "replies.json").write_text(json.dumps(script), encoding="utf-8")

        def sent() -> list[list[object]]:
            calls = home / "calls.jsonl"
            lines = (
                calls.read_text(encoding="utf-8").splitlines() if calls.exists() else []
            )
            return [json.loads(line) for line in lines]

        return sent

    return install


@pytest.fixture
def release_job(
    publish: ModuleType, monkeypatch: pytest.MonkeyPatch
) -> Callable[..., str]:
    """Stand where the release job of the public pipeline stands.

    Returns ``enter(repository, **settings) -> commit``: the repository becomes
    the working directory, and the environment says what the runner says of a
    push of its HEAD commit to ``master`` of ``example/config``, without
    ``BUMP``. Each of ``settings`` then sets one variable, or removes it when
    its value is ``None``.
    """

    def enter(repository: Path, **settings: str | None) -> str:
        commit = publish.git(repository, "rev-parse", "HEAD").decode().strip()
        monkeypatch.chdir(repository)
        job = {
            "GITHUB_REPOSITORY": "example/config",
            "GITHUB_REF": "refs/heads/master",
            "GITHUB_SHA": commit,
            "GITHUB_SERVER_URL": "https://github.example",
            "BUMP": None,
        }
        for variable, value in {**job, **settings}.items():
            if value is None:
                monkeypatch.delenv(variable, raising=False)
            else:
                monkeypatch.setenv(variable, value)
        return commit

    return enter

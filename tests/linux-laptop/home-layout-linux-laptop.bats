#!/usr/bin/env bats
# Tests for scripts/home-layout-linux-laptop.sh (linux-laptop/Linux HOME layout additions).
#
# Isolation guarantees:
#   - setup() asserts tmpdir is non-empty before any test body runs.
#   - teardown() uses ${tmpdir:?} so Bash aborts the rm -rf instead of
#     expanding to rm -rf "" if the variable were somehow empty or unset.
#   - All paths are passed to Bash subprocesses via exported environment
#     variables, never interpolated into the -c string, so a path that
#     contains single quotes or other metacharacters cannot inject code.

SCRIPT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/home-layout-linux-laptop.sh"

setup() {
    tmpdir=$(mktemp -d)
    [[ -n $tmpdir ]]
}

teardown() {
    rm -rf "${tmpdir:?}"
}

# Path to the simulated Dropbox tree.
dropbox() { printf '%s/Dropbox (Maestral)/Example' "$tmpdir"; }

# Run the script live (actual filesystem changes).
# Paths flow in via env vars to keep the -c body injection-safe.
live() {
    TEST_HOME="$tmpdir" TEST_SCRIPT="$SCRIPT" bash -c '
        export HOME=$TEST_HOME
        DRY_RUN_CMD=
        source "$TEST_SCRIPT"
    '
}

# Run in dry-run mode and capture output+status via bats 'run'.
dry() {
    run env TEST_HOME="$tmpdir" TEST_SCRIPT="$SCRIPT" bash -c '
        export HOME=$TEST_HOME
        DRY_RUN_CMD=echo
        source "$TEST_SCRIPT"
    '
}

# ---------------------------------------------------------------------------
# mov symlink
# ---------------------------------------------------------------------------

@test "creates mov symlink pointing to Videos" {
    mkdir -p "$tmpdir/Videos"
    live
    [[ -L $tmpdir/mov ]]
    [[ $(readlink "$tmpdir/mov") == "$tmpdir/Videos" ]]
}

@test "does not overwrite an existing mov symlink" {
    mkdir -p "$tmpdir/Videos"
    ln -s "$tmpdir/other" "$tmpdir/mov"
    live
    [[ $(readlink "$tmpdir/mov") == "$tmpdir/other" ]]
}

@test "does not overwrite a real mov directory" {
    mkdir -p "$tmpdir/Videos" "$tmpdir/mov"
    live
    [[ -d $tmpdir/mov && ! -L $tmpdir/mov ]]
}

# ---------------------------------------------------------------------------
# redirect_to_dropbox: Dropbox absent
# ---------------------------------------------------------------------------

@test "leaves Documents untouched when Dropbox is not yet synced" {
    mkdir -p "$tmpdir/Documents"
    live
    [[ -d $tmpdir/Documents && ! -L $tmpdir/Documents ]]
}

# ---------------------------------------------------------------------------
# redirect_to_dropbox: standard redirects
# ---------------------------------------------------------------------------

@test "replaces empty Documents with Dropbox symlink" {
    mkdir -p "$tmpdir/Documents"
    mkdir -p "$(dropbox)/Documents"
    live
    [[ -L $tmpdir/Documents ]]
    [[ $(readlink "$tmpdir/Documents") == "$(dropbox)/Documents" ]]
}

@test "replaces empty Downloads with Dropbox symlink" {
    mkdir -p "$tmpdir/Downloads"
    mkdir -p "$(dropbox)/Downloads"
    live
    [[ -L $tmpdir/Downloads ]]
    [[ $(readlink "$tmpdir/Downloads") == "$(dropbox)/Downloads" ]]
}

@test "replaces empty Music with Dropbox symlink" {
    mkdir -p "$tmpdir/Music"
    mkdir -p "$(dropbox)/Music"
    live
    [[ -L $tmpdir/Music ]]
    [[ $(readlink "$tmpdir/Music") == "$(dropbox)/Music" ]]
}

@test "replaces Pictures dir (with screenshots placeholder) with Dropbox symlink" {
    mkdir -p "$tmpdir/Pictures/screenshots"
    mkdir -p "$(dropbox)/Pictures"
    live
    [[ -L $tmpdir/Pictures ]]
    [[ $(readlink "$tmpdir/Pictures") == "$(dropbox)/Pictures" ]]
}

@test "replaces empty Videos with Dropbox Movies symlink" {
    mkdir -p "$tmpdir/Videos"
    mkdir -p "$(dropbox)/Movies"
    live
    [[ -L $tmpdir/Videos ]]
    [[ $(readlink "$tmpdir/Videos") == "$(dropbox)/Movies" ]]
}

@test "replaces src dir (with github.com placeholder) with Dropbox symlink" {
    mkdir -p "$tmpdir/src/github.com"
    mkdir -p "$(dropbox)/src"
    live
    [[ -L $tmpdir/src ]]
    [[ $(readlink "$tmpdir/src") == "$(dropbox)/src" ]]
}

@test "creates Documents symlink when the local path does not exist yet" {
    mkdir -p "$(dropbox)/Documents"
    live
    [[ -L $tmpdir/Documents ]]
    [[ $(readlink "$tmpdir/Documents") == "$(dropbox)/Documents" ]]
}

# ---------------------------------------------------------------------------
# redirect_to_dropbox: already a symlink (no-op)
# ---------------------------------------------------------------------------

@test "no-op when Documents is already a symlink" {
    mkdir -p "$(dropbox)/Documents"
    ln -s "$(dropbox)/Documents" "$tmpdir/Documents"
    live
    [[ $(readlink "$tmpdir/Documents") == "$(dropbox)/Documents" ]]
}

# ---------------------------------------------------------------------------
# redirect_to_dropbox: non-empty directory
# ---------------------------------------------------------------------------

@test "preserves non-empty Documents and prints warning to stderr" {
    local dropbox_path; dropbox_path=$(dropbox)
    mkdir -p "$tmpdir/Documents"
    touch "$tmpdir/Documents/important.txt"
    mkdir -p "$dropbox_path/Documents"
    run env TEST_HOME="$tmpdir" TEST_SCRIPT="$SCRIPT" bash -c '
        export HOME=$TEST_HOME
        DRY_RUN_CMD=
        source "$TEST_SCRIPT" 2>&1
    '
    [[ -d $tmpdir/Documents && ! -L $tmpdir/Documents ]]
    [[ $output == *"non-empty"* ]]
}

# ---------------------------------------------------------------------------
# Dry-run mode (DRY_RUN_CMD=echo)
# ---------------------------------------------------------------------------

@test "dry run: no symlinks created" {
    mkdir -p "$tmpdir/Documents"
    mkdir -p "$(dropbox)/Documents"
    dry
    [[ $status -eq 0 ]]
    [[ ! -L $tmpdir/Documents ]]
}

@test "dry run: ln -s commands are printed to stdout" {
    mkdir -p "$tmpdir/Documents"
    mkdir -p "$(dropbox)/Documents"
    dry
    [[ $output == *"ln -s"* ]]
}

@test "dry run: mov ln -s command is printed to stdout" {
    mkdir -p "$tmpdir/Videos"
    dry
    [[ $output == *"ln -s"*"Videos"*"mov"* ]]
}

# ---------------------------------------------------------------------------
# Screenshots symlink
# ---------------------------------------------------------------------------

@test "creates Pictures/Screenshots symlink pointing to screenshots" {
    mkdir -p "$tmpdir/Pictures/screenshots"
    live
    [[ -L $tmpdir/Pictures/Screenshots ]]
    [[ $(readlink "$tmpdir/Pictures/Screenshots") == "screenshots" ]]
}

@test "does not overwrite an existing Pictures/Screenshots entry" {
    mkdir -p "$tmpdir/Pictures/screenshots"
    mkdir -p "$tmpdir/Pictures/Screenshots"
    live
    [[ -d $tmpdir/Pictures/Screenshots && ! -L $tmpdir/Pictures/Screenshots ]]
}

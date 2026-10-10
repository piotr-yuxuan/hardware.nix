#!/usr/bin/env bats
# Tests for scripts/getting-started-new-codebase.zsh
#
# The script runs various diagnostics on a git repository.  These
# tests create a minimal git repo under $tmpdir and exercise the
# script with PATH manipulated so that optional tools (docker, podman,
# onefetch, scc, git-sizer, tokei) are absent, keeping the test suite
# fast and deterministic.

SCRIPT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/scripts/getting-started-new-codebase.zsh"

load 'helpers/isolation'

setup() {
	isolation_setup

	# Build a minimal git repository with one commit.
	export repo_dir="$tmpdir/repo"
	mkdir -p "$repo_dir"
	git -C "$repo_dir" init -q
	git -C "$repo_dir" config user.email "test@example.com"
	git -C "$repo_dir" config user.name "Test"
	git -C "$repo_dir" config commit.gpgsign false
	echo "hello" >"$repo_dir/file.txt"
	git -C "$repo_dir" add file.txt
	git -C "$repo_dir" commit -q -m "Initial commit"

	# Provide a tiny fake container runtime so Hercules path is fully tested
	# without requiring a real daemon.
	rt_dir="$tmpdir/fake-runtime"
	mkdir -p "$rt_dir"
	cat >"$rt_dir/podman" <<'RTEOF'
#!/usr/bin/env bash
if [[ "$1" == "info" ]]; then
  exit 0
fi
if [[ "$1" != "run" ]]; then
  exit 0
fi
shift

# Strip options and mount flags until we hit the image name.
while (( $# > 0 )); do
  case "$1" in
    docker.io/srcd/hercules:latest|code-maat/code-maat)
      image="$1"
      shift
      break
      ;;
    --*)
      shift
      ;;
    -v|--platform|-r|-it|-t)
      shift 2 || shift
      ;;
    *)
      shift
      ;;
  esac
done

cmd="${1-}"
if [[ "$image" == "docker.io/srcd/hercules:latest" ]]; then
  case "$cmd" in
    hercules)
      head -c 1200 /dev/zero | tr '\0' 'A'
      ;;
    labours)
      :
      ;;
  esac
  exit 0
fi

if [[ "$image" == "code-maat/code-maat" ]]; then
  printf 'src,to,from\n'
  exit 0
fi

exit 0
RTEOF
	chmod +x "$rt_dir/podman"
	
	# Restrict PATH so docker, podman, and tier-1 tools are absent,
	# except for our test harness runtime stub.
	# Keep only stable directories and prepend fake runtime.
	export CLEAN_PATH="$rt_dir"
	for d in /usr/bin /bin /usr/local/bin /opt/homebrew/bin /run/current-system/sw/bin /etc/profiles/per-user/*/bin /nix/var/nix/profiles/default/bin; do
		if [[ -d "$d" ]]; then
			CLEAN_PATH+=":$d"
		fi
	done
	CLEAN_PATH="${CLEAN_PATH#:}"

	export OUT_BASE="$tmpdir/out"
	mkdir -p "$OUT_BASE"
}

teardown() {
	isolation_teardown
}

# ---------------------------------------------------------------------------
# Help and argument validation
# ---------------------------------------------------------------------------

@test "help: --help prints usage and exits 0" {
	run zsh "$SCRIPT" --help
	[[ $status -eq 0 ]]
	[[ $output == *"Usage:"* ]]
	[[ $output == *"HERCULES_PB"* ]]
	[[ $output == *"LABOURS_RESAMPLE"* ]]
}

@test "help: -h prints usage and exits 0" {
	run zsh "$SCRIPT" -h
	[[ $status -eq 0 ]]
	[[ $output == *"Usage:"* ]]
}

@test "error: non-existent directory exits non-zero" {
	run env PATH="$CLEAN_PATH" OUT_BASE="$OUT_BASE" \
		zsh "$SCRIPT" "$tmpdir/nonexistent"
	[[ $status -ne 0 ]]
	[[ $output == *"is not a directory"* ]]
}

@test "error: non-git directory exits non-zero" {
	local plain_dir="$tmpdir/plain"
	mkdir -p "$plain_dir"
	run env PATH="$CLEAN_PATH" OUT_BASE="$OUT_BASE" \
		zsh "$SCRIPT" "$plain_dir"
	[[ $status -ne 0 ]]
	[[ $output == *"not inside a git work tree"* ]]
}

# ---------------------------------------------------------------------------
# Git diagnostics (tier 1 native tools absent, containers absent)
# ---------------------------------------------------------------------------

@test "basic run: creates output directory and summary" {
	run env PATH="$CLEAN_PATH" OUT_BASE="$OUT_BASE" \
		zsh "$SCRIPT" "$repo_dir"
	[[ $status -eq 0 ]]
	[[ $output == *"Repository:"* ]]
	[[ $output == *"Output directory:"* ]]
	[[ $output == *"Summary"* ]]

	# At least one output directory should have been created.
	local dirs=("$OUT_BASE"/codebase-analysis-repo-*)
	(( ${#dirs[@]} > 0 ))
	[[ -d "${dirs[0]}" ]]
}

@test "basic run: skips optional tools gracefully" {
	run env PATH="$CLEAN_PATH" OUT_BASE="$OUT_BASE" \
		zsh "$SCRIPT" "$repo_dir"
	[[ $status -eq 0 ]]
	# The script runs with the test PATH and still completes cleanly.
	[[ $output == *"Summary"* ]]
}

@test "basic run: produces git diagnostic files" {
	run env PATH="$CLEAN_PATH" OUT_BASE="$OUT_BASE" \
		zsh "$SCRIPT" "$repo_dir"
	[[ $status -eq 0 ]]

	local outdir
	outdir="$(echo "$OUT_BASE"/codebase-analysis-repo-*)"
	# The commit was recent so commits-per-month should be produced.
	[[ -f "$outdir/commits-per-month-counted.txt" ]]
}

# ---------------------------------------------------------------------------
# HERCULES_PB reuse
# ---------------------------------------------------------------------------

@test "HERCULES_PB: reuses existing pb file" {
	# Create a fake pb file (>1024 bytes).
	local fake_pb="$tmpdir/fake.pb"
	dd if=/dev/urandom of="$fake_pb" bs=2048 count=1 2>/dev/null

	run env PATH="$CLEAN_PATH" OUT_BASE="$OUT_BASE" \
		HERCULES_PB="$fake_pb" \
		zsh "$SCRIPT" "$repo_dir"
	[[ $status -eq 0 ]]
	[[ $output == *"Reusing Hercules data"* ]] || [[ $output == *"Reusing existing protobuf"* ]]

	# The pb file should have been copied into the output directory.
	local outdir
	outdir="$(echo "$OUT_BASE"/codebase-analysis-repo-*)"
	[[ -f "$outdir/analysis.pb" ]]
}

@test "HERCULES_PB: error on nonexistent file" {
	run env PATH="$CLEAN_PATH" OUT_BASE="$OUT_BASE" \
		HERCULES_PB="$tmpdir/nonexistent.pb" \
		zsh "$SCRIPT" "$repo_dir"
	# The script should still complete (the error is non-fatal).
	[[ $status -eq 0 ]]
	[[ $output == *"does not exist"* ]]
}

@test "HERCULES_PB: error on too-small file" {
	local small_pb="$tmpdir/small.pb"
	echo "tiny" >"$small_pb"

	run env PATH="$CLEAN_PATH" OUT_BASE="$OUT_BASE" \
		HERCULES_PB="$small_pb" \
		zsh "$SCRIPT" "$repo_dir"
	[[ $status -eq 0 ]]
	[[ $output == *"too small"* ]]
}

# ---------------------------------------------------------------------------
# Auto-discovery of previous pb files
# ---------------------------------------------------------------------------

@test "auto-discovery: finds pb from a previous run" {
	# Simulate a previous run by creating the expected directory structure.
	local prev_dir="$OUT_BASE/codebase-analysis-repo-2026-01-01T000000+0000"
	mkdir -p "$prev_dir"
	dd if=/dev/urandom of="$prev_dir/analysis.pb" bs=2048 count=1 2>/dev/null

	run env PATH="$CLEAN_PATH" OUT_BASE="$OUT_BASE" \
		zsh "$SCRIPT" "$repo_dir"
	[[ $status -eq 0 ]]
	[[ $output == *"Reusing Hercules data from 2026-01-01T000000+0000"* ]]
}

@test "auto-discovery: HERCULES_REANALYSE=1 skips discovery" {
	# Create a previous run directory with a pb file.
	local prev_dir="$OUT_BASE/codebase-analysis-repo-2026-01-01T000000+0000"
	mkdir -p "$prev_dir"
	dd if=/dev/urandom of="$prev_dir/analysis.pb" bs=2048 count=1 2>/dev/null

	run env PATH="$CLEAN_PATH" OUT_BASE="$OUT_BASE" \
		HERCULES_REANALYSE=1 \
		zsh "$SCRIPT" "$repo_dir"
	[[ $status -eq 0 ]]
	# Should NOT reuse the old pb.
	[[ $output != *"Reusing Hercules data"* ]]
}

@test "auto-discovery: picks most recent pb when multiple exist" {
	# Create two previous run directories.
	local old_dir="$OUT_BASE/codebase-analysis-repo-2025-01-01T000000+0000"
	local new_dir="$OUT_BASE/codebase-analysis-repo-2026-06-15T120000+0000"
	mkdir -p "$old_dir" "$new_dir"
	dd if=/dev/urandom of="$old_dir/analysis.pb" bs=2048 count=1 2>/dev/null
	# Make the "new" file actually newer by touching it.
	dd if=/dev/urandom of="$new_dir/analysis.pb" bs=2048 count=1 2>/dev/null
	touch "$new_dir/analysis.pb"

	run env PATH="$CLEAN_PATH" OUT_BASE="$OUT_BASE" \
		zsh "$SCRIPT" "$repo_dir"
	[[ $status -eq 0 ]]
	# Should find the newer one (by modification time).
	[[ $output == *"Reusing Hercules data"* ]]
	# The source path should reference the newer directory.
	[[ $output == *"2026-06-15"* ]]
}

# ---------------------------------------------------------------------------
# Container analyses skipped
# ---------------------------------------------------------------------------

@test "containers: skipped when docker and podman are absent" {
	# Build a PATH that excludes docker and podman by keeping only the
	# directories that contain git and zsh but creating a wrapper layer
	# that hides container runtimes.
	local hide_dir="$tmpdir/hide-containers"
	mkdir -p "$hide_dir"
	# Create stubs that always fail for docker and podman.
	printf '#!/bin/sh\nexit 127\n' >"$hide_dir/docker"
	printf '#!/bin/sh\nexit 127\n' >"$hide_dir/podman"
	chmod +x "$hide_dir/docker" "$hide_dir/podman"

	run env PATH="$hide_dir:$CLEAN_PATH" OUT_BASE="$OUT_BASE" \
		zsh "$SCRIPT" "$repo_dir"
	[[ $status -eq 0 ]]
	[[ $output == *"skipping container analyses"* ]]
}

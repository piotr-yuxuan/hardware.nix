# shellcheck shell=bash
# tests/helpers/isolation.bash
#
# Shared setup/teardown helpers for BATS test suites in this repository.
# Load with:  load '../helpers/isolation'
# All suites that source activation scripts must use these helpers to
# guarantee a safe, reproducible, and injection-free environment.

# isolation_setup
#
# Creates a fresh temporary HOME directory and asserts it is non-empty so
# that teardown can never accidentally receive an empty path.  Stores the
# path in $tmpdir (exported for use in test bodies).
isolation_setup() {
	tmpdir=$(mktemp -d)
	[[ -n $tmpdir ]] || {
		echo "isolation_setup: mktemp failed" >&2
		return 1
	}
	export tmpdir
}

# isolation_teardown
#
# Removes the temporary HOME directory created by isolation_setup.
# Uses ${tmpdir:?} so the shell aborts with an error rather than
# expanding to rm -rf "" if the variable is somehow empty or unset.
isolation_teardown() {
	rm -rf "${tmpdir:?}"
}

# run_script SCRIPT_PATH [VAR=VALUE ...]
#
# Source SCRIPT_PATH inside an isolated subshell where HOME=$tmpdir.
# Additional VAR=VALUE pairs are exported into the subshell environment.
# All paths are passed via environment variables; the subshell -c body
# is a static string, never subject to word splitting from caller variables.
# DRY_RUN_CMD defaults to empty (live mode) unless the caller sets it.
run_script() {
	local script_path="$1"
	shift
	local extra_env=("$@")
	env HOME="$tmpdir" TEST_SCRIPT="$script_path" "${extra_env[@]}" bash -c '
        export HOME
        source "$TEST_SCRIPT"
    '
}

# run_script_dry SCRIPT_PATH [VAR=VALUE ...]
#
# Same as run_script but sets DRY_RUN_CMD=echo so no filesystem changes
# are made.  Capture stdout/stderr with the bats `run` builtin.
run_script_dry() {
	local script_path="$1"
	shift
	local extra_env=("$@")
	env HOME="$tmpdir" TEST_SCRIPT="$script_path" DRY_RUN_CMD=echo \
		"${extra_env[@]}" bash -c '
        export HOME DRY_RUN_CMD
        source "$TEST_SCRIPT"
    '
}

# make_fake_bin NAME BODY
#
# Write a fake executable named NAME into $tmpdir/bin/ with the given BODY
# (a shell script body, without the shebang line).  The created script
# appends each invocation as "NAME ARGS..." to $tmpdir/.fake-calls so
# tests can assert what was called.
make_fake_bin() {
	local name="$1" body="$2"
	mkdir -p "$tmpdir/bin"
	{
		printf '#!/bin/sh\n'
		printf 'echo "%s $*" >> "$HOME/.fake-calls"\n' "$name"
		printf '%s\n' "$body"
	} >"$tmpdir/bin/$name"
	chmod +x "$tmpdir/bin/$name"
}

# fake_calls
#
# Print the contents of the call log produced by make_fake_bin, or an
# empty string if no fake binary has been invoked yet.
fake_calls() {
	cat "$tmpdir/.fake-calls" 2>/dev/null || true
}

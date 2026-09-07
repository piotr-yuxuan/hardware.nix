#!/usr/bin/env zsh
# getting-started-new-codebase.zsh: comprehensive codebase analysis.
#
# Runs every available diagnostic on a git repository and collects the
# output in a single timestamped directory.  Each tool is optional: the
# script checks for its presence and skips gracefully when missing.
#
# Tools integrated (tier 1, native):
#   git log diagnostics (churn, bus factor, bug clusters, momentum, firefighting)
#   onefetch, scc, git-sizer, tokei
#
# Tools integrated (tier 2, containers):
#   Hercules (docker.io/srcd/hercules:latest), code-maat (code-maat/code-maat)
#   Runtime: prefers Podman, falls back to Docker
#   Images are auto-pulled when missing
#
# Usage:
#   getting-started-new-codebase.zsh [/path/to/repo]
#
# Defaults to the current directory when the argument is omitted.

setopt ERR_EXIT PIPE_FAIL NO_UNSET

# ── Helpers ──────────────────────────────────────────────────────────

# Portable timestamp that works on both GNU date (Linux) and
# BSD date (macOS), and is safe for directory names.
portable_timestamp() {
  local ts
  ts="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)"

  # Filesystem-friendly: avoid ':' which is awkward on macOS.
  ts="${ts//:/}"

  print -r -- "$ts"
}

has() { command -v "$1" >/dev/null 2>&1 }

# Container runtime selection.
# Prefers Podman (if usable); falls back to Docker.
container_runtime=()
container_run_flags=()

if has podman && podman info >/dev/null 2>&1; then
  container_runtime=(podman)
elif has docker && docker info >/dev/null 2>&1; then
  container_runtime=(docker)
fi

if (( ${#container_runtime} > 0 )); then
  container_run_flags+=(--pull="${CONTAINER_PULL:-missing}")

  # Platform selection.
  # Prefer CONTAINER_PLATFORM, keep DOCKER_PLATFORM for backward compatibility.
  local container_platform="${CONTAINER_PLATFORM:-${DOCKER_PLATFORM-}}"
  if [[ -n "$container_platform" ]]; then
    container_run_flags+=(--platform "$container_platform")
  fi
fi

# Print a section banner.
banner() {
  printf '\n\e[1;34m── %s ──\e[0m\n' "$1"
}

# Print a warning indented to match run_to_file output.
warn() {
  printf '    \e[33mwarning:\e[0m %s\n' "$1"
}

# Rank lines by frequency and replace the raw file with the result.
# Usage: rank_file RAW_FILE RANKED_FILE [LIMIT]
rank_file() {
  local raw=$1 ranked=$2 limit=${3:-40}
  [[ -f "$raw" ]] || return 0
  sort "$raw" | grep -v '^$' | uniq -c | sort -nr | head -"$limit" \
    > "$ranked" && rm "$raw"
}

# Run a command, redirect stdout to a file, tolerate failure.
run_to_file() {
  local label=$1 outfile=$2
  shift 2
  printf '  %s -> %s\n' "$label" "${outfile:t}"
  if ! "$@" > "$outfile" 2>/dev/null; then
    warn "$label produced no output or failed"
    rm -f "$outfile"
  elif [[ ! -s "$outfile" ]]; then
    rm -f "$outfile"
  fi
}

# ── Argument handling ────────────────────────────────────────────────

usage() {
  cat <<'EOF'
Usage:
  scripts/getting-started-new-codebase.zsh [/path/to/repo]

Environment:
  OUT_BASE                      Directory where analysis output is written (default: current directory)
  CONTAINER_PULL                Container image pull policy: missing|always|never (default: missing)
  CONTAINER_PLATFORM            Container platform override, e.g. linux/amd64
  DOCKER_PLATFORM               Back-compat alias for CONTAINER_PLATFORM
  HERCULES_ENABLE_COUPLES       Enable Hercules couples analysis (default: 0)
  HERCULES_ENABLE_FILE_BURNDOWN Enable per-file burndown (default: 0)
  HERCULES_PB                   Path to an existing .pb file (default: auto-discover most recent)
  HERCULES_REANALYSE            Set to 1 to force a fresh Hercules analysis (default: 0)
  LABOURS_SIZE                  Output plot size in inches, e.g. 18,12 (default: 18,12)
  LABOURS_FONT_SIZE             Plot font size (default: 14)
  LABOURS_RESAMPLE              Time series granularity: W (week), month, year, raw (default: month)
  LABOURS_START_DATE            Start date for plots, e.g. "2026-01-01" or "January 2026"
  LABOURS_END_DATE              End date for plots, same formats as LABOURS_START_DATE

  On subsequent runs the script automatically reuses the most recent
  analysis.pb found in OUT_BASE for the same repository. This makes it
  fast to iterate on plot settings. Set HERCULES_REANALYSE=1 to force a
  fresh Hercules pass, or point HERCULES_PB at a specific file.

  Each Hercules mode produces both PNG plots and JSON data exports.

Examples:
  # First run (slow): analyse and keep the .pb for later
  ./scripts/getting-started-new-codebase.zsh /path/to/repo

  # Second run (fast): auto-reuses .pb, tweak plot settings
  LABOURS_RESAMPLE=W LABOURS_START_DATE="2026-01-01" \
    ./scripts/getting-started-new-codebase.zsh /path/to/repo

  # Force a fresh analysis
  HERCULES_REANALYSE=1 \
    ./scripts/getting-started-new-codebase.zsh /path/to/repo
EOF
}

if [[ "${1-}" == (-h|--help) ]]; then
  usage
  exit 0
fi

if ! has git; then
  print -u2 "Error: git is required but not installed."
  exit 1
fi

REPO="${${1:-.}:A}"  # resolve to absolute path

if [[ ! -d "$REPO" ]]; then
  print -u2 "Error: $REPO is not a directory."
  exit 1
fi

REPO="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" || true
if [[ -z "$REPO" ]]; then
  print -u2 "Error: ${${1:-.}:A} is not inside a git work tree."
  exit 1
fi

REPO_NAME="${REPO:t}"

TIMESTAMP="$(portable_timestamp)"
OUT_BASE="${OUT_BASE:-$PWD}"
OUT_BASE="${OUT_BASE:A}"
OUTDIR="$OUT_BASE/codebase-analysis-${REPO_NAME}-${TIMESTAMP}"
mkdir -p "$OUTDIR"

# Track per-section pass/skip/fail counts for the final summary.
typeset -i sections_run=0 sections_skipped=0 sections_failed=0

print "Repository:       $REPO"
print "Output directory: $OUTDIR"

# ── Part 1: git diagnostic commands ─────────────────────────────────

banner "Git diagnostics"

# 1. Churn hotspots (most-changed files in the last year)
run_to_file "churn hotspots" "$OUTDIR/churn-hotspots.txt" \
  git -C "$REPO" log --format=format: --name-only --since="1 year ago"
rank_file "$OUTDIR/churn-hotspots.txt" "$OUTDIR/churn-hotspots-ranked.txt"

# 2. Bus factor (contributors ranked by commit count)
run_to_file "bus factor (all time)" "$OUTDIR/contributors-all-time.txt" \
  git -C "$REPO" shortlog -sn --no-merges

run_to_file "bus factor (6 months)" "$OUTDIR/contributors-6months.txt" \
  git -C "$REPO" shortlog -sn --no-merges --since="6 months ago"

# 3. Bug clusters
run_to_file "bug clusters (raw)" "$OUTDIR/bug-clusters.txt" \
  git -C "$REPO" log -i -E --grep="fix|bug|broken" --name-only --format=''
rank_file "$OUTDIR/bug-clusters.txt" "$OUTDIR/bug-clusters-ranked.txt"

# 4. Project momentum (commits per month)
run_to_file "commits per month" "$OUTDIR/commits-per-month.txt" \
  git -C "$REPO" log --format='%ad' --date=format:'%Y-%m'
if [[ -f "$OUTDIR/commits-per-month.txt" ]]; then
  sort "$OUTDIR/commits-per-month.txt" | uniq -c \
    > "$OUTDIR/commits-per-month-counted.txt" && rm "$OUTDIR/commits-per-month.txt"
fi

# 5. Firefighting frequency (reverts, hotfixes)
run_to_file "firefighting" "$OUTDIR/firefighting.txt" \
  git -C "$REPO" log --oneline --since="1 year ago"
if [[ -f "$OUTDIR/firefighting.txt" ]]; then
  grep -iE 'revert|hotfix|emergency|rollback' "$OUTDIR/firefighting.txt" \
    > "$OUTDIR/firefighting-filtered.txt" 2>/dev/null || true
  rm -f "$OUTDIR/firefighting.txt"
fi

(( ++sections_run ))

# ── Part 2: native analysis tools (tier 1) ──────────────────────────

# onefetch
if has onefetch; then
  banner "onefetch"
  run_to_file "onefetch (text)" "$OUTDIR/onefetch.txt" \
    onefetch "$REPO" --no-art
  run_to_file "onefetch (json)" "$OUTDIR/onefetch.json" \
    onefetch "$REPO" -o json
  (( ++sections_run ))
else
  print "\n  skipping onefetch (not installed)"
  (( ++sections_skipped ))
fi

# scc
if has scc; then
  banner "scc"
  run_to_file "scc (text)" "$OUTDIR/scc.txt" \
    scc "$REPO"
  run_to_file "scc (json)" "$OUTDIR/scc.json" \
    scc "$REPO" --format json
  (( ++sections_run ))
else
  print "\n  skipping scc (not installed)"
  (( ++sections_skipped ))
fi

# git-sizer
if has git-sizer; then
  banner "git-sizer"
  run_to_file "git-sizer (verbose)" "$OUTDIR/git-sizer.txt" \
    git-sizer --path "$REPO" --verbose
  run_to_file "git-sizer (json)" "$OUTDIR/git-sizer.json" \
    git-sizer --path "$REPO" --json
  (( ++sections_run ))
else
  print "\n  skipping git-sizer (not installed)"
  (( ++sections_skipped ))
fi

# tokei
if has tokei; then
  banner "tokei"
  run_to_file "tokei" "$OUTDIR/tokei.txt" \
    tokei "$REPO"
  (( ++sections_run ))
else
  print "\n  skipping tokei (not installed)"
  (( ++sections_skipped ))
fi

# ── Part 3: container analyses (tier 2) ─────────────────────────────

if (( ${#container_runtime} > 0 )); then
  # Hercules
  banner "Hercules (${container_runtime[1]})"
  HERCULES_IMAGE="docker.io/srcd/hercules:latest"

  hercules_enable_couples="${HERCULES_ENABLE_COUPLES:-0}"
  hercules_enable_file_burndown="${HERCULES_ENABLE_FILE_BURNDOWN:-0}"
  hercules_pb="${HERCULES_PB-}"
  hercules_reanalyse="${HERCULES_REANALYSE:-0}"

  # Resolve an existing protobuf file.  Priority:
  #   1. Explicit HERCULES_PB path.
  #   2. Most recent analysis.pb from a previous run for the same repo
  #      (unless HERCULES_REANALYSE is set).
  #   3. Fresh Hercules analysis.
  if [[ -z "$hercules_pb" && "$hercules_reanalyse" != (1|true|yes|on) ]]; then
    typeset -a previous_pbs=("$OUT_BASE"/codebase-analysis-"${REPO_NAME}"-*/analysis.pb(N-om))
    if (( ${#previous_pbs} > 0 )); then
      hercules_pb="${previous_pbs[1]}"
    fi
  fi

  if [[ -n "$hercules_pb" ]]; then
    hercules_pb="${hercules_pb:A}"
    if [[ ! -f "$hercules_pb" ]]; then
      print -u2 "Error: HERCULES_PB=$hercules_pb does not exist."
      (( ++sections_failed ))
      hercules_pb=""
    elif (( $(wc -c < "$hercules_pb" 2>/dev/null || print 0) < 1024 )); then
      print -u2 "Error: HERCULES_PB=$hercules_pb is too small to be a valid protobuf dump."
      (( ++sections_failed ))
      hercules_pb=""
    else
      # Show the directory timestamp so the user knows how old the data is.
      local pb_dir="${hercules_pb:h}"
      local pb_dir_name="${pb_dir:t}"
      local pb_age="${pb_dir_name#codebase-analysis-${REPO_NAME}-}"
      printf '\n  \e[1;33m*** Reusing Hercules data from %s ***\e[0m\n' "$pb_age"
      printf '  Source: %s\n' "$hercules_pb"
      printf '  Set HERCULES_REANALYSE=1 to force a fresh analysis.\n\n'
      cp "$hercules_pb" "$OUTDIR/analysis.pb"
    fi
  fi

  PB_FILE="$OUTDIR/analysis.pb"

  if [[ -z "$hercules_pb" ]]; then
    print "  Running Hercules analysis (may take a while for large repos)..."

    typeset -a hercules_args=(
      --burndown
      --burndown-people
      --devs
      --pb
      /repo
    )

    if [[ "$hercules_enable_file_burndown" == (1|true|yes|on) ]]; then
      hercules_args=(--burndown-files "${hercules_args[@]}")
    fi

    if [[ "$hercules_enable_couples" == (1|true|yes|on) ]]; then
      hercules_args=(--couples "${hercules_args[@]}")
    fi

    if ! "${container_runtime[@]}" run --rm "${container_run_flags[@]}" \
         -v "$REPO":/repo:ro \
         "$HERCULES_IMAGE" hercules "${hercules_args[@]}" > "$PB_FILE" 2>/dev/null || [[ ! -s "$PB_FILE" ]]; then
      warn "Hercules analysis failed"
      rm -f "$PB_FILE"
      (( ++sections_failed ))
    fi

    # Guard against a truncated protobuf dump.
    if [[ -f "$PB_FILE" ]] && (( $(wc -c < "$PB_FILE" 2>/dev/null || print 0) < 1024 )); then
      warn "Hercules output is unexpectedly small; skipping rendering"
      rm -f "$PB_FILE"
      (( ++sections_failed ))
    fi
  fi

  if [[ -f "$PB_FILE" ]]; then
    LABOURS_SIZE="${LABOURS_SIZE:-18,12}"
    LABOURS_FONT_SIZE="${LABOURS_FONT_SIZE:-14}"
    LABOURS_RESAMPLE="${LABOURS_RESAMPLE:-month}"
    labours_start_date="${LABOURS_START_DATE-}"
    labours_end_date="${LABOURS_END_DATE-}"

    # Build the common labours argument list.
    typeset -a labours_common=(
      -f pb
      -i /out/analysis.pb
      --disable-projector
      --size "$LABOURS_SIZE"
      --font-size "$LABOURS_FONT_SIZE"
      --resample "$LABOURS_RESAMPLE"
    )

    if [[ -n "$labours_start_date" ]]; then
      labours_common+=(--start-date "$labours_start_date")
    fi

    if [[ -n "$labours_end_date" ]]; then
      labours_common+=(--end-date "$labours_end_date")
    fi

    typeset -a labours_modes=(
      burndown-project
      burndown-person
      overwrites-matrix
      ownership
      devs
      devs-efforts
      old-vs-new
    )

    if [[ "$hercules_enable_file_burndown" == (1|true|yes|on) ]]; then
      labours_modes+=(burndown-file)
    fi

    if [[ "$hercules_enable_couples" == (1|true|yes|on) ]]; then
      labours_modes+=(couples-files couples-people)
    fi

    # Run labours for a single mode, producing the given output path.
    # Silently removes the output on failure.
    run_labours() {
      local mode=$1 out_path=$2
      "${container_runtime[@]}" run --rm "${container_run_flags[@]}" \
        -v "$OUTDIR":/out \
        "$HERCULES_IMAGE" labours \
          "${labours_common[@]}" \
          -m "$mode" \
          -o "$out_path" \
        >/dev/null 2>&1
    }

    for mode in "${labours_modes[@]}"; do
      printf '  Rendering: %s\n' "$mode"

      # labours appends .png when the -o path lacks an extension and
      # creates a directory for multi-output modes (burndown-*).
      if ! run_labours "$mode" "/out/hercules-${mode}"; then
        warn "$mode rendering failed"
        rm -rf "$OUTDIR/hercules-${mode}" "$OUTDIR/hercules-${mode}.png"
      fi

      # Export the same data as JSON for programmatic consumption.
      if ! run_labours "$mode" "/out/hercules-${mode}.json"; then
        rm -rf "$OUTDIR/hercules-${mode}.json"
      fi
    done

    (( ++sections_run ))
  fi

  # code-maat
  banner "code-maat (${container_runtime[1]})"
  CODEMAAT_IMAGE="code-maat/code-maat"
  GITLOG_FILE="$OUTDIR/gitlog-codemaat.txt"

  print "  Exporting git log for code-maat..."
  if git -C "$REPO" log --all --numstat --date=short \
       --pretty=format:'--%h--%ad--%aN' --no-renames \
       > "$GITLOG_FILE" 2>/dev/null && [[ -s "$GITLOG_FILE" ]]; then

    typeset -a codemaat_analyses=(coupling abs-churn entity-ownership)
    typeset codemaat_ok=false

    for analysis in "${codemaat_analyses[@]}"; do
      printf '  Running code-maat: %s\n' "$analysis"
      if "${container_runtime[@]}" run --rm "${container_run_flags[@]}" \
           -v "$OUTDIR":/data:ro \
           "$CODEMAAT_IMAGE" -l /data/gitlog-codemaat.txt -c git2 -a "$analysis" \
           > "$OUTDIR/codemaat-${analysis}.csv" 2>/dev/null && [[ -s "$OUTDIR/codemaat-${analysis}.csv" ]]; then
        codemaat_ok=true
      else
        warn "$analysis failed"
        rm -f "$OUTDIR/codemaat-${analysis}.csv"
      fi
    done

    if $codemaat_ok; then
      (( ++sections_run ))
    else
      warn "all code-maat analyses failed"
      (( ++sections_failed ))
    fi
  else
    print "  warning: git log export failed; skipping code-maat"
    rm -f "$GITLOG_FILE"
    (( ++sections_failed ))
  fi
else
  print "\n  skipping container analyses (podman/docker not available or not running)"
  (( ++sections_skipped ))
fi

# ── Summary ──────────────────────────────────────────────────────────

banner "Summary"
print "Sections run: $sections_run  skipped: $sections_skipped  failed: $sections_failed"
print ""

# List only files that were actually produced.
typeset -a produced=("$OUTDIR"/*(N))
if (( ${#produced} == 0 )); then
  print "No output files were generated."
else
  print "Generated files in $OUTDIR:"
  for f in "${produced[@]}"; do
    printf '  %s  (%s)\n' "${f:t}" "$(du -h "$f" 2>/dev/null | cut -f1)"
  done
fi

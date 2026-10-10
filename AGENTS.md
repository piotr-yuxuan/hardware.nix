If `AGENTS.local.md` exists at the repository root, read it first.

# NixOS fleet configuration

Declarative NixOS + nix-darwin configuration managed as a Nix flake.

## Agent workflow

### Worktree and branch setup

Each agent works in its own dedicated worktree under `.worktree/` so
that it never touches the live `main` checkout. When starting work on
a plan, create the worktree and its branch in one step:

``` zsh
# nnn is a zero-padded three-digit sequence number, slug is kebab-case
git worktree add .worktree/nnn-slug -b plan/nnn-slug main
```

Once inside the worktree, verify the context before touching anything:

``` zsh
git rev-parse --show-toplevel  # must print the worktree root, not the main repo
git branch --show-current      # must print plan/nnn-slug
```

### Autonomous execution

Agents make every effort to work autonomously and make reasonable
assumptions. They work until all goals are met and all test suites are
green; they must not stop early.

Assumptions are collected and presented in full in the pre-merge
summary (see "Pre-merge confirmation" below).

There are two absolute exceptions to autonomous execution:

1. **Destructive commands.** Never run any command that is
   irreversible or that destroys data without explicit, informed user
   confirmation first. This includes, but is not limited to:
   `git reset --hard`, `git clean -fd`, `rm -rf`, `git push --force`,
   overwriting files that have untracked or uncommitted changes, and
   any other operation whose effects cannot be undone with a single
   `git revert` or equivalent. State precisely what will be destroyed
   and why it is necessary before asking.

2. **Too many deep assumptions.** If the goals are unclear or
   underspecified to the point where proceeding would require making
   several assumptions of significant consequence, do not proceed.
   Abort, and present the user with a set of detailed, contextualised
   clarifying questions that explain exactly what is ambiguous, what
   the realistic options are, and what the consequences of each choice
   would be. This is not a failure: it is the correct response to an
   underspecified plan.

### Clarifying questions

Agents may ask a minimal set of clarifying questions at the beginning,
but only for genuine blockers: values that cannot be inferred,
defaulted safely, or looked up in the codebase. A question about
something that is answerable by reading the code is not acceptable.

Needing to ask many questions is a signal that the plan was
underspecified and should be improved before the next run.

### Commits

The output of a plan is committed in small, meaningful, well-contained
commits on the plan branch. Each commit must build and pass static
checks on its own (no broken intermediate states). Commit messages use
the imperative mood and sentence case, consistent with the rest of
this project. Never add an attribution trailer such as
`Co-Authored-By` to a commit message.

### Testing

Run all applicable checks after every non-trivial change:

``` zsh
nix flake check           # evaluates all NixOS and nix-darwin configs
                          # (macOS through the darwin-macOS-eval check,
                          # defined for x86_64-linux and aarch64-darwin)
statix check              # Nix anti-pattern linter
deadnix                   # dead-code detection
shellcheck scripts/**/*.sh
```

For NixOS-specific integration tests, use `nixos-test` expressions
where they exist, or add new ones when the change warrants it. For
Home Manager changes, build the activation package without activating
it:

``` zsh
nix build .#nixosConfigurations.nixOS.config.home-manager.users.example.home.activationPackage
```

nixOS cannot build aarch64-darwin derivations. For macOS changes,
`nix flake check` proves that the configuration evaluates, and a dry
run lists what the Mac will build or fetch:

``` zsh
nix build --dry-run .#darwinConfigurations.macOS.system
```

Tests must be passing before any commit is made. LSP servers (nil,
nixd, shellcheck) must not report errors on touched files.

### Code quality

Respect the principle of code locality, simplicity, and KISS. Prefer
the simplest solution that works. Do not introduce abstractions ahead
of need. Keep related code together. When in doubt, inline rather than
abstract.

### Pre-merge confirmation

Before merging into `main`, present the user with a structured summary
covering:

1. What changed and why.
2. All assumptions made during execution and why they were reasonable.
3. Tradeoffs and alternative approaches considered but not taken.
4. Which tests were run and their results.
5. Any known limitations or follow-up work.
6. A request for the user to run manual tests where automated coverage
   is absent.

Do not merge until the user explicitly confirms.

### Merging

Once the user confirms, merge with a meaningful merge a commit message
with the plan slug as first line (as a sentence) that briefly
describes the change:

``` zsh
git -C <main-repo-root> merge --no-ff plan/nnn-slug \
  -m "Add zsh completions for custom scripts"
```

Use sentence case. Preserve branch topology in the merge.

### Worktree cleanup

After you've merged the plan, remove the worktree and delete the plan
branch:

``` zsh
git worktree remove .worktree/nnn-slug
git branch -d plan/nnn-slug
```

## Public and private boundary

`scripts/publish.py` exports this repository to a public one: a
manifest selects the files, private rules rewrite names, and a gate
refuses personal data. `docs/how-to/publish-to-public.org` describes
it.

- Personal values (a name other than the public handle, an address, a
  key identifier, a hardware address, a location, the time zone, the
  locale, the keyboard layout) go only in files that the manifest
  excludes, such as `home/<host>/personal.nix` and
  `hosts/<host>/personal.nix`. The shared files must evaluate without
  them.
- A new file is classified in `publish/manifest.toml` in the commit
  that adds it: included or excluded, never left undecided.
- Work values (an employer's name, a work address, a forge host, a
  certificate) never enter this repository. They live in the local
  flake of the Mac, created from `templates/macOS`.

## Machines

| Host           | OS                 | Arch           | Notes                                                    |
|----------------|--------------------|----------------|----------------------------------------------------------|
| `nixOS`       | NixOS 26.05        | x86_64-linux   | Framework 16 AMD 7040, GNOME/Wayland, Secure Boot        |
| `macOS`        | macOS (nix-darwin) | aarch64-darwin | Corporate Mac, Homebrew fallback for unmigrated GUI apps |

## Repository layout

- `flake.nix`: Flake inputs and machine definitions.
- `hosts/<name>.nix`: Per-host NixOS/nix-darwin system config.
- `home/base.nix`: Cross-platform Home Manager config (shared by all
  machines).
- `home/<name>.nix`: Per-host Home Manager overrides.
- `fonts.nix`: Shared font list, imported by `home/base.nix` and
  `hosts/macOS.nix`.
- `packages/`: Custom Nix derivations (e.g. `zapfino.nix`,
  `tw-moe-fonts.nix`).
- `config/`: Dotfiles and static config snippets symlinked by Home
  Manager.
- `docs/`: Documentation, organised as described in "Documentation
  layout" below.
- `templates/macOS/`: The local flake of a Mac, which takes this
  repository as an input.
- `scripts/publish.py`: Exports this repository to its public mirror.

## Documentation layout

The documentation follows [Diátaxis](https://diataxis.fr/). Every page
is an Org file at `docs/<quadrant>/<name>.org` and holds one type of
documentation:

- `docs/tutorials/`: a lesson that a newcomer follows step by step to a
  guaranteed result, with a check after every step.
- `docs/how-to/`: directions for a competent reader who has one real
  problem to solve. Name the page after the goal, for example
  `rebuild-and-roll-back.org`.
- `docs/reference/`: an austere, accurate description of the machinery
  (options, files, jobs, commands), checked against the configuration.
- `docs/explanation/`: why the configuration is the way it is, with the
  alternatives and their trade-offs.

Split a page that mixes types. Keep it whole only when splitting would
hurt it, as for the incident record
`docs/explanation/nixOS-iiyama-display.org`.

Prefix the file name of a host-specific page with `nixOS-` or
`macOS-`; a page that applies to both hosts has no prefix. Every page
sits at the same depth, so a link to another page is
`../<quadrant>/<name>.org` and a link to a repository file is
`../../<path>`. A page whose steps could not be run on the target
machine says so. `tests/README.org` stays outside this structure,
next to what it describes.

When you add, rename or remove a page:

- Keep the documentation map in `readme.org` complete: every page under
  `docs/` appears in its quadrant as
  `- [[file:docs/<quadrant>/<name>.org][Title]]: one-line purpose.`
- Add a row to the symptom index of
  `docs/how-to/troubleshoot-common-problems.org` for each symptom the
  page resolves.
- Update every link to the old path.

After every documentation change, run the documentation checks from the
repository root over every `.org` file:

- Links: org-lint's link checkers, plus the `::*Heading` part of file
  links, which org-lint skips.
- Tables of contents: regenerating each `toc-org` table of contents
  changes nothing.
- Style: headings in sentence case, and no dash used as punctuation
  (see "Style rules").

The table of contents check needs `toc-org` on the Emacs load path, for
example `~/.emacs.d/straight/build/toc-org`.

## Package channels

- **`unstable`** is the default for all user-facing packages in
  `home/base.nix`, `home/<name>.nix`, and `fonts.nix`. It is passed
  via `extraSpecialArgs` from the flake.
- **`pkgs`** (stable) is used only at the NixOS system level
  (`flake.nix` `sharedModule`, `hosts/nixOS.nix`).
- `home/base.nix` does **not** take `pkgs` as an argument. Everything
  goes through `unstable`.

## Dependency upgrade

When you update, add, or remove a dependency, make sure to also keep
the relevant section in sync in `./docs/reference/package-guide.org`.

## Platform conditionals: mandatory rule

**Never assume that "not Darwin" means "Linux", or vice-versa.**

When behaviour differs by platform, always test both conditions
explicitly and throw on an unrecognised platform:

```nix
if      unstable.stdenv.hostPlatform.isDarwin then «darwin value»
else if unstable.stdenv.hostPlatform.isLinux  then «linux value»
else throw "«context»: unsupported platform";
```

Always inline `unstable.stdenv.hostPlatform.isDarwin` / `.isLinux` at
the point of use. Do not extract them into `let` bindings: the full
path makes the intent unambiguous when reading the code.

## Architecture conditionals on macOS

This repository targets Apple Silicon macOS only (=aarch64-darwin=) via
the `macOS` flake output.

Avoid keeping Intel-only branches around. When a package is only
available (or broken) on a subset of platforms, use `meta.availableOn`
or an explicit platform guard at the point of use.

Prefer `lib.optionals` over `if/then/else` for list elements so that
they compose cleanly. For non-list options (services, settings), use
`lib.mkIf`:

```nix
home.packages =
  (with unstable; [
    glab
  ])
  ++ unstable.lib.optionals unstable.stdenv.hostPlatform.isAarch64 [
    unstable.some-arm-only-package
  ];

services.example.enable = unstable.lib.mkIf unstable.stdenv.hostPlatform.isAarch64 true;
```

## Style rules

Use sentence case for all headings and titles. Do not use emdashes or
hyphens as punctuation; restructure the sentence instead. Hyphenated
words (e.g. "platform-specific") are fine.

## Inline scripts

Almost never use Nix double single-quoted strings (`'' ... ''`) for
multi-line shell scripts or config snippets. Put the content in a
standalone file under `./scripts/` or `./config/` and reference it
with `builtins.readFile`, `pkgs.writeShellScript`, or similar.

An exception is tolerated when the snippet is self-contained and will
not be reused, for example an `installPhase` in a one-off derivation.

#!/usr/bin/env bats

# Maestral matches its ignore list with pathspec's gitwildmatch, which
# follows git's syntax: git itself answers, in a scratch repository that
# stands for the Dropbox folder.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
MIGNORE="$REPO_ROOT/config/maestral/mignore"

load '../helpers/isolation'

setup() {
	isolation_setup
	export HOME="$tmpdir" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
	git init -q "$tmpdir/dropbox"
}

teardown() {
	isolation_teardown
}

# check_ignore PATH: exit 0 when ignored, 1 when kept, 128 on error.
check_ignore() {
	git -C "$tmpdir/dropbox" -c core.excludesFile="$MIGNORE" \
		check-ignore --no-index -q -- "$1"
}

assert_ignored() {
	local path
	for path in "$@"; do
		check_ignore "$path" || {
			echo "kept, expected ignored: $path"
			return 1
		}
	done
}

assert_kept() {
	local path code
	for path in "$@"; do
		code=0
		check_ignore "$path" || code=$?
		[[ $code -eq 1 ]] || {
			echo "exit code $code, expected kept: $path"
			return 1
		}
	done
}

@test "the list ignores itself at the root of the Dropbox folder" {
	assert_ignored .mignore
	assert_kept example/.mignore
}

@test "Git worktrees are ignored at any depth of the source tree" {
	assert_ignored \
		example/src/.worktree/001-plan/readme.org \
		example/src/github.com/owner/repo/.worktree/001-plan/readme.org \
		example/src/github.com/owner/repo/.worktrees/feature/main.py
}

@test "Emacs leaves its temporary files behind" {
	assert_ignored \
		example/src/repo/.#init.el \
		example/src/repo/init.el~ \
		'example/src/repo/#init.el#' \
		example/src/repo/eln-cache/31.0/mode.eln
}

@test "Clojure tools leave their caches behind" {
	assert_ignored \
		example/src/repo/.cpcache/123.cp \
		example/src/repo/.shadow-cljs/builds/app/dev/out/main.js \
		example/src/repo/.clj-kondo/.cache/v1/lock \
		example/src/repo/.lsp/.cache/db.transit.json \
		example/src/repo/.nrepl-port \
		example/src/repo/.lein-repl-history \
		example/src/repo/target/default/classes/app/core.class
}

@test "Java and Rust builds are ignored" {
	assert_ignored \
		example/src/repo/target/classes/App.class \
		example/src/repo/target/debug/app \
		example/src/repo/.gradle/8.10/checksums/checksums.lock
}

@test "Python environments and caches are ignored" {
	assert_ignored \
		example/src/repo/__pycache__/app.cpython-314.pyc \
		example/src/repo/legacy.pyc \
		example/src/repo/.venv/bin/python \
		example/src/repo/venv/bin/python \
		example/src/repo/app.egg-info/PKG-INFO \
		example/src/repo/.eggs/README.txt \
		example/src/repo/.pytest_cache/v/cache/nodeids \
		example/src/repo/.ruff_cache/0.14.0/123 \
		example/src/repo/.mypy_cache/3.14/app.data.json \
		example/src/repo/.dmypy.json \
		example/src/repo/.hypothesis/examples/abc \
		example/src/repo/.tox/py314/bin/python \
		example/src/repo/.nox/tests/bin/python \
		example/src/repo/.coverage \
		example/src/repo/.coverage.host.123 \
		example/src/repo/htmlcov/index.html \
		example/src/repo/.ipynb_checkpoints/notes-checkpoint.ipynb
}

@test "JavaScript and TypeScript dependencies and caches are ignored" {
	assert_ignored \
		example/src/node_modules/react/index.js \
		example/src/repo/web/node_modules/react/index.js \
		example/src/repo/.eslintcache \
		example/src/repo/tsconfig.tsbuildinfo \
		example/src/repo/.next/cache/webpack/1.pack \
		example/src/repo/.nuxt/app.js \
		example/src/repo/.svelte-kit/output/client/app.js \
		example/src/repo/.parcel-cache/data.mdb \
		example/src/repo/.turbo/cookies/1.cookie \
		example/src/repo/.nyc_output/out.json
}

@test "LaTeX intermediate files are ignored" {
	assert_ignored \
		example/src/repo/paper.aux \
		example/src/repo/paper.bcf \
		example/src/repo/paper.blg \
		example/src/repo/paper.fdb_latexmk \
		example/src/repo/paper.fls \
		example/src/repo/paper.lof \
		example/src/repo/paper.lot \
		example/src/repo/slides.nav \
		example/src/repo/slides.snm \
		example/src/repo/paper.synctex.gz \
		'example/src/repo/paper.synctex(busy)' \
		example/src/repo/paper.toc \
		example/src/repo/slides.vrb \
		example/src/repo/paper.xdv \
		example/src/repo/_minted-paper/default.pygstyle
}

@test "Lua, Terraform and Nix caches are ignored" {
	assert_ignored \
		example/src/repo/luac.out \
		example/src/repo/lua_modules/lib/lua/5.4/lfs.so \
		example/src/repo/.luarocks/config-5.4.lua \
		example/src/repo/.terraform/providers/registry.terraform.io/x \
		example/src/repo/crash.log \
		example/src/repo/crash.1729.log \
		example/src/repo/.direnv/flake-profile
}

@test "sources, tool settings and Terraform state are kept" {
	assert_kept \
		example/src/repo/src/main/java/App.java \
		example/src/repo/pom.xml \
		example/src/repo/build.gradle.kts \
		example/src/repo/Cargo.toml \
		example/src/repo/deps.edn \
		example/src/repo/.clj-kondo/config.edn \
		example/src/repo/.lsp/config.edn \
		example/src/repo/pyproject.toml \
		example/src/repo/package.json \
		example/src/repo/package-lock.json \
		example/src/repo/paper.tex \
		example/src/repo/paper.pdf \
		example/src/repo/paper.bbl \
		example/src/repo/main.tf \
		example/src/repo/.terraform.lock.hcl \
		example/src/repo/terraform.tfstate \
		example/src/repo/terraform.tfstate.backup \
		example/src/repo/terraform.tfstate.d/dev/terraform.tfstate \
		example/src/repo/prod.tfvars \
		example/src/repo/flake.nix \
		example/src/repo/.envrc \
		example/src/repo/init.el \
		example/src/repo/bin/run.sh \
		example/src/repo/build/build.clj \
		example/src/repo/.run/App.run.xml \
		example/src/repo/.gitignore
}

@test "names that hold real content in some repositories are kept" {
	assert_kept \
		example/src/repo/dist/app.js \
		example/src/repo/out/main.js \
		example/src/repo/obj/main.o \
		example/src/repo/coverage/lcov.info \
		example/src/repo/auto/paper.el \
		example/src/repo/result \
		example/src/repo/app.out \
		example/src/repo/server.log \
		example/src/repo/.idea/workspace.xml \
		example/src/repo/.classpath \
		example/src/repo/.project \
		example/src/repo/.settings/org.eclipse.jdt.core.prefs
}

@test "build products that some repositories commit are kept" {
	assert_kept \
		example/src/repo/dev-resources/ltximg/org-ltximg_1.png \
		example/src/repo/.cache/maven/repository/lib/1.0/lib-1.0.jar \
		example/src/repo/tests/java/classes/Example.class \
		example/src/repo/test/fixtures/compiled.elc \
		example/src/repo/hs_err_pid4242.log \
		example/src/repo/flycheck_grammalecte.py
}

@test "nothing inside a Git directory is ignored" {
	assert_kept \
		example/src/repo/.git/HEAD \
		example/src/repo/.git/index \
		example/src/repo/.git/logs/HEAD \
		example/src/repo/.git/refs/heads/main \
		example/src/repo/.git/objects/pack/pack-1.idx \
		example/src/repo/.git/objects/pack/pack-1.pack
}

@test "outside the source tree, nothing is ignored" {
	assert_kept \
		example/Documents/thesis/thesis.aux \
		example/Documents/src/repo/target/app.jar \
		example/Music/score/out/score.pdf \
		example/Documents/app/node_modules/react/index.js \
		archive/java/project/target/app.jar \
		archive/src.old/repo/__pycache__/app.pyc
}

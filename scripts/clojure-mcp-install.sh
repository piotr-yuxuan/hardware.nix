#!/usr/bin/env bash
# Install bhauman/clojure-mcp as a Clojure tool.
#
# This makes `clojure -Tmcp start` available from any directory.
# The command is idempotent: it overwrites the existing installation
# if the tool is already present.
#
# @CLOJURE_BIN@ and @GIT_DIR@ are substituted at Nix build time with
# store paths so the script works during activation when the user
# profile PATH is not yet available.

export PATH="@GIT_DIR@:$PATH"

if $DRY_RUN_CMD @CLOJURE_BIN@ -Ttools install-latest \
	:lib io.github.bhauman/clojure-mcp :as mcp; then
	echo "clojure-mcp-install: bhauman/clojure-mcp installed as :mcp"
else
	echo "clojure-mcp-install: install failed (network?), skipping" >&2
fi

# rust-analyzer-mcp, an MCP server in front of rust-analyzer for coding
# agents. Its releases publish no binaries and nixpkgs does not package
# it, so it is built from the tag of its release; the crate on crates.io
# leaves out the sample project its unit tests read. It starts the
# rust-analyzer on PATH.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "rust-analyzer-mcp";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "zeenix";
    repo = "rust-analyzer-mcp";
    tag = "v${finalAttrs.version}";
    hash = "sha256-W9LFTQ4KxUHDFuENRhDsv+jUjzgHdCEn7xXWzVKF6y0=";
  };

  cargoHash = "sha256-LcX9VO1ArCdiq5j57JB/Tkfw6pAl6QvckhzMRv5C5dA=";

  # The integration tests drive rust-analyzer over sample projects, with
  # a toolchain the build sandbox lacks: 25 of 41 fail there. The unit
  # tests run.
  cargoTestFlags = ["--lib" "--bins"];

  meta = {
    description = "MCP server that gives coding agents rust-analyzer's analysis";
    homepage = "https://github.com/zeenix/rust-analyzer-mcp";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "rust-analyzer-mcp";
  };
})

# Allium's command line and language server, from the binaries of its
# release: nixpkgs does not package it. The language server is a Node
# script, the same for every platform.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  nodejs,
}: let
  version = "3.7.2";
  release = "https://github.com/juxt/allium-tools/releases/download/v${version}";
  binaries = {
    x86_64-linux = {
      target = "x86_64-unknown-linux-gnu";
      hash = "sha256-8plUjYQBp2HqUFmr0gLRkY2kxOxEXcbGLbKHdVv5Ydo=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-gnu";
      hash = "sha256-aiGvwTR7/NuC5Wbd9pbh4LWqVv5Ky8NCi9KfM8AKJGU=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      hash = "sha256-Fb9Ojkb7dmNFcqA7kLnMt8U7s6BduMvVCAY0x4ORE5M=";
    };
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-PeOs+8eHTZLGPOT7uS/0MzNIdDRxuIXtFTGOlAH2/DY=";
    };
  };
  binary =
    binaries.${stdenv.hostPlatform.system}
    or (throw "allium: unsupported platform ${stdenv.hostPlatform.system}");
  languageServer = fetchurl {
    url = "${release}/allium-lsp-${version}.tar.gz";
    hash = "sha256-iDUc6OOxIR5S4M8rC32/+VBLmkffCFyV5UXuCNbvAfE=";
  };
in
  stdenv.mkDerivation {
    pname = "allium";
    inherit version;

    src = fetchurl {
      url = "${release}/allium-${binary.target}.tar.gz";
      inherit (binary) hash;
    };
    sourceRoot = ".";

    nativeBuildInputs = [makeWrapper] ++ lib.optionals stdenv.hostPlatform.isLinux [autoPatchelfHook];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [stdenv.cc.cc.lib];

    installPhase = ''
      runHook preInstall
      install -Dm755 allium $out/bin/allium
      mkdir -p $out/lib
      tar -xzf ${languageServer} -C $out/lib
      makeWrapper ${lib.getExe nodejs} $out/bin/allium-lsp \
        --add-flags $out/lib/allium-lsp/allium-lsp
      runHook postInstall
    '';

    meta = {
      description = "Command line and language server of Allium, a specification language for LLMs";
      homepage = "https://allium-lang.org/";
      license = lib.licenses.mit;
      platforms = builtins.attrNames binaries;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      mainProgram = "allium";
    };
  }

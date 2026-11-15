# dbt v2, the Apache 2.0 distribution, from the prebuilt binaries of
# its GitHub release. The hashes are those of the release's SHA256SUMS.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}: let
  version = "2.0.11";
  releases = {
    x86_64-linux = {
      target = "x86_64-unknown-linux-gnu";
      hash = "sha256-v0aPb0P21k62NsLdnet9HrF/fFegnVCcCDa0TGBoi0w=";
    };
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-Os0XKccerDFc8Q+M2IGkSzPGXs7lGgV76UGPMVAKavQ=";
    };
  };
  release =
    releases.${stdenv.hostPlatform.system}
    or (throw "dbt: unsupported platform ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation {
    pname = "dbt";
    inherit version;

    src = fetchurl {
      url = "https://github.com/dbt-labs/dbt/releases/download/v${version}/dbt-core-${version}-${release.target}.tar.gz";
      inherit (release) hash;
    };

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [autoPatchelfHook];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [stdenv.cc.cc.lib];

    # Stripping would break the code signature of the Darwin binary.
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 dbt -t $out/bin
      runHook postInstall
    '';

    # dbt loads database drivers, such as DuckDB's, that need libstdc++.
    # Its RUNPATH does not reach their dependencies, so dbt loads
    # libstdc++ itself and the drivers reuse it.
    postInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
      patchelf --add-needed libstdc++.so.6 $out/bin/dbt
    '';

    meta = {
      description = "Data transformation tool, open source distribution of dbt v2";
      homepage = "https://github.com/dbt-labs/dbt";
      license = lib.licenses.asl20;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      platforms = builtins.attrNames releases;
      mainProgram = "dbt";
    };
  }

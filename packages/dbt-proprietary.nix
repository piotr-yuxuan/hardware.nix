# dbt 2.0.9, dbt Labs' proprietary distribution, from its CDN: the
# open source repository has no 2.0.9. Installed as dbt-2.0.9, beside
# the open source dbt of packages/dbt.nix.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}: let
  version = "2.0.9";
  releases = {
    x86_64-linux = {
      target = "x86_64-unknown-linux-gnu";
      hash = "sha256-zFfh9qQNnWIAjSJCwD/I++XMoonJV6v3hPmmJnvEsO8=";
    };
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-Y6nG1/sQWryqjdbfxWgF72xvczOCR44sPyEDSBtY+Us=";
    };
  };
  release =
    releases.${stdenv.hostPlatform.system}
    or (throw "dbt-proprietary: unsupported platform ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation {
    pname = "dbt-proprietary";
    inherit version;

    src = fetchurl {
      url = "https://public.cdn.getdbt.com/fs/cli/fs-v${version}-${release.target}.tar.gz";
      inherit (release) hash;
    };

    # The tarball holds a bare dbt, with no directory around it.
    sourceRoot = ".";

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [autoPatchelfHook];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [stdenv.cc.cc.lib];

    # Stripping would break the code signature of the Darwin binary.
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 dbt $out/bin/dbt-${version}
      runHook postInstall
    '';

    # As in packages/dbt.nix: the drivers that dbt loads need libstdc++.
    postInstall = lib.optionalString stdenv.hostPlatform.isLinux ''
      patchelf --add-needed libstdc++.so.6 $out/bin/dbt-${version}
    '';

    meta = {
      description = "Data transformation tool, dbt Labs' proprietary distribution of dbt v2";
      homepage = "https://docs.getdbt.com/";
      license = lib.licenses.unfree;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      platforms = builtins.attrNames releases;
      mainProgram = "dbt-${version}";
    };
  }

{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  jq,
  makeWrapper,
  nodejs,
}:
buildNpmPackage rec {
  pname = "pi-mcp-adapter";
  version = "2.27.0";

  src = fetchFromGitHub {
    owner = "nicobailon";
    repo = "pi-mcp-adapter";
    rev = "v${version}";
    hash = "sha256-9ZdYhANu6SRV8ZPAkPHf+6rp3EqOdDd/DBFdEDK+BTo=";
  };

  npmDepsHash = "sha256-zKnaG+QbR7XOrflsIYgr+2bNx9OeJyZpOmpMdEeISW4=";
  npmInstallFlags = ["--omit=dev"];
  nativeBuildInputs = [jq makeWrapper];
  postPatch = ''
    ${lib.getExe jq} 'del(.devDependencies)' package.json > package.json.new
    mv package.json.new package.json
    cp ${./pi-mcp-adapter-package-lock.json} package-lock.json
  '';
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/node_modules/pi-mcp-adapter $out/bin
    cp -R . $out/lib/node_modules/pi-mcp-adapter
    makeWrapper ${nodejs}/bin/node $out/bin/pi-mcp-adapter \
      --add-flags $out/lib/node_modules/pi-mcp-adapter/cli.js

    runHook postInstall
  '';

  meta = {
    description = "Context-efficient MCP adapter extension for Pi";
    homepage = "https://github.com/nicobailon/pi-mcp-adapter";
    license = lib.licenses.mit;
    mainProgram = "pi-mcp-adapter";
  };
}

# dbt-lsp-plus, a language server in front of dbt lsp, built from the
# tag of its release: the release publishes no binaries.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "dbt-lsp-plus";
  version = "0.1.5";

  src = fetchFromGitHub {
    owner = "piotr-yuxuan";
    repo = "dbt-lsp-plus";
    tag = finalAttrs.version;
    hash = "sha256-WudSvl6UZezeMdb/x6EMY+GZPRYF4rZJief7azcvc2E=";
  };

  cargoHash = "sha256-56iLjurXnwahoCAjVn+HF8C3FNfDIx8ly0Ww0dAvz18=";

  # The crate's other binary is a stand-in for dbt lsp that only its
  # integration tests run.
  cargoBuildFlags = ["--bin" "dbt-lsp-plus"];

  # These two cut dbt parse off the network with unshare -rnm, which
  # the build sandbox forbids.
  checkFlags = [
    "--skip=a_parse_is_cut_off_the_network_and_its_project_where_it_can_be"
    "--skip=alone_a_broken_project_file_is_shown_and_a_problem_in_no_file_logged_once"
  ];

  meta = {
    description = "Language server in front of dbt lsp that adds the LSP features it lacks";
    homepage = "https://github.com/piotr-yuxuan/dbt-lsp-plus";
    license = with lib.licenses; [eupl12 gpl3Plus];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "dbt-lsp-plus";
  };
})

# Flake check: Home Manager takes its packages from nixpkgs-unstable.
#
# useGlobalPkgs gives Home Manager the stable `pkgs`, so a module left
# without `package = unstable.…` silently installs a stable package.
# This check reads home.packages and the module packages listed below,
# which do not reach home.packages under their own name, and fails,
# naming each stable one and its host. A package counts as stable when
# its meta.position lies in the stable nixpkgs source.
#
# Not covered: packages that a Home Manager module hard-codes from
# `pkgs` without an option, such as zsh-autosuggestions in the zsh
# module or the default plugins of the tmux module, and module packages
# missing from the list below.
{
  pkgs,
  hosts,
}: let
  inherit (pkgs) lib;

  # Packages that stay on the stable channel on purpose (AGENTS.md,
  # "Package channels"), matched by name on either host.
  allowed = [
    "sqlfluff"
    "audacity"
    # On nixOS the login shell is NixOS's stable zsh; on the Mac
    # nix-darwin puts the stable zsh on PATH.
    "zsh"
    # Hard-coded by Home Manager's zsh module.
    "nix-zsh-completions"
  ];

  stableIn = hostName: host:
    lib.concatMap (hm: let
      stableSource = toString host.pkgs.path;
      packages =
        hm.home.packages
        ++ [
          hm.programs.direnv.nix-direnv.package
          hm.programs.zsh.syntaxHighlighting.package
          hm.programs.pandoc.package
          hm.services.gpg-agent.pinentry.package
        ]
        ++ lib.optional hm.xdg.mime.enable hm.xdg.mime.desktopFileUtilsPackage;
      isStable = p: lib.hasPrefix stableSource (p.meta.position or "") && !(lib.elem (lib.getName p) allowed);
    in
      map (p: "${hostName}: ${p.name}") (lib.filter isStable packages))
    (builtins.attrValues host.config.home-manager.users);

  offenders = lib.unique (lib.concatLists (lib.mapAttrsToList stableIn hosts));
in
  if offenders == []
  then pkgs.writeText "hm-packages-unstable" (lib.concatStringsSep "\n" (builtins.attrNames hosts))
  else throw "Home Manager installs stable packages; give each module `package = unstable.…`:\n  ${lib.concatStringsSep "\n  " offenders}"

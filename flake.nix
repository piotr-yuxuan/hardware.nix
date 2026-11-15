{
  description = "NixOS fleet: nixOS and future machines";

  inputs = {
    # Stable channel: system foundation
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Unstable channel: bleeding-edge CLI tools
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secure Boot support
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hardware profiles; its nixpkgs input follows ours.
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager: user environment managed declaratively.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix-darwin: declarative macOS system configuration.
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Starship's gruvbox-rainbow preset (TOML, not a flake).
    starship-gruvbox-rainbow = {
      url = "https://starship.rs/presets/toml/gruvbox-rainbow.toml";
      flake = false;
    };

    # Practicalli's deps.edn: community aliases for the Clojure CLI.
    practicalli-clojure-deps-edn = {
      url = "github:practicalli/clojure-deps-edn";
      flake = false;
    };

    # Community Linux packaging for OpenAI's official desktop application.
    codex-desktop-linux = {
      url = "github:ilysenko/codex-desktop-linux";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    claude-desktop = {
      url = "github:aaddrick/claude-desktop-debian";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    hylki = {
      url = "github:clementpoiret/hylki-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    penguin-mail = {
      url = "github:c9dev/penguin-mail";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    inlark = {
      url = "github:inlark/inlark";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-unstable,
    disko,
    lanzaboote,
    nixos-hardware,
    home-manager,
    nix-darwin,
    starship-gruvbox-rainbow,
    practicalli-clojure-deps-edn,
    codex-desktop-linux,
    ...
  }: let
    # Unstable package set for x86_64-linux (nixOS)
    unstable = import nixpkgs-unstable {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
  in {
    nixosConfigurations.nixOS = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit unstable;};
      modules = [
        disko.nixosModules.disko
        ./disko-config.nix
        lanzaboote.nixosModules.lanzaboote
        ./hardware-configuration.nix

        # Framework 16 AMD 7040 hardware profile
        nixos-hardware.nixosModules.framework-16-7040-amd

        codex-desktop-linux.nixosModules.default

        # Home Manager for example: home/base.nix, shared with the Mac, and
        # home/nixOS.nix. `inputs` names nixOS's packages from other
        # flakes where home/nixOS.nix uses them.
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true; # reuse the system nixpkgs instance
            useUserPackages = true; # install into /etc/profiles/per-user
            backupFileExtension = "hm-backup";
            extraSpecialArgs = {
              inherit inputs unstable starship-gruvbox-rainbow practicalli-clojure-deps-edn;
            };
            users.example = {
              imports = [./home/base.nix ./home/nixOS.nix];
              home.stateVersion = "25.11";
            };
          };
        }

        ./hosts/nixOS.nix
      ];
    };

    # A Mac's own flake (templates/macOS) takes this one as `base` and calls
    # this builder, so its account name and identities stay on the Mac.
    lib.mkDarwinHost = {
      system,
      # The account short name, as `id -un` prints it; the home directory
      # and Home Manager's user derive from it.
      user,
      extraHmModules ? [],
      extraHostModules ? [],
    }: let
      unstable-darwin = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in
      nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = {unstable = unstable-darwin;};
        modules =
          [
            ./hosts/macOS.nix

            home-manager.darwinModules.home-manager
            {
              nixpkgs.config.allowUnfree = true;

              system.primaryUser = user;
              users.users.${user}.home = "/Users/${user}";

              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "hm-backup";
                extraSpecialArgs = {
                  unstable = unstable-darwin;
                  inherit starship-gruvbox-rainbow practicalli-clojure-deps-edn;
                };

                users.${user} = {
                  imports = [./home/base.nix ./home/macOS.nix] ++ extraHmModules;
                  home.stateVersion = "25.11";
                };
              };
            }
          ]
          ++ extraHostModules;
      };

    # Starting point of a Mac's own flake:
    #   nix flake init -t github:piotr-yuxuan/hardware.nix/stable#macOS
    templates.macOS = {
      path = ./templates/macOS;
      description = "Local flake of one Mac: account name, identities and machine-local modules";
    };

    # The template evaluated against this checkout: what a Mac receives, for
    # the checks and tests below.
    inherit ((import ./templates/macOS/flake.nix).outputs {base = self;}) darwinConfigurations;

    # `nix flake check` ignores darwinConfigurations, so this check
    # evaluates the Mac in full, on either system, without building it.
    checks = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-darwin"] (system: {
      darwin-macOS-eval =
        nixpkgs.legacyPackages.${system}.writeText "darwin-macOS-eval"
        (builtins.unsafeDiscardStringContext
          self.darwinConfigurations.macOS.config.system.build.toplevel.drvPath);

      # Home Manager's packages come from nixpkgs-unstable on both hosts.
      hm-packages-unstable = import ./tests/hm-packages-unstable.nix {
        pkgs = nixpkgs.legacyPackages.${system};
        hosts = {
          inherit (self.nixosConfigurations) nixOS;
          inherit (self.darwinConfigurations) macOS;
        };
      };
    });
  };
}

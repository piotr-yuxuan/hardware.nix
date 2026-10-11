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

    # Hardware-specific tweaks for known machines.
    # As of its 26.05-era revision nixos-hardware declares its own
    # nixpkgs input, so point it at ours to keep a single nixpkgs in the
    # lock (previously it had none and `follows` would have warned).
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

    # Starship gruvbox-rainbow preset (raw TOML, not a flake).
    # Refreshed automatically on `nix flake update`.
    starship-gruvbox-rainbow = {
      url = "https://starship.rs/presets/toml/gruvbox-rainbow.toml";
      flake = false;
    };

    # Practicalli Clojure deps.edn: community aliases for tools.deps.
    # `nix flake update` bumps to the latest main commit.
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
  };

  outputs = {
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
    claude-desktop,
    ...
  }: let
    # Unstable package set for x86_64-linux (nixOS)
    unstable = import nixpkgs-unstable {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    # Shared NixOS configuration
    # Everything here applies to ALL NixOS machines.
    sharedModule = {pkgs, ...}: {
      nixpkgs.config.allowUnfree = true;

      nix = {
        settings = {
          experimental-features = ["nix-command" "flakes"];
          auto-optimise-store = true;
          # Require every store path fetched from a binary cache to carry a
          # valid cryptographic signature. Stated explicitly to prevent
          # accidental downgrade via an override elsewhere in the module tree.
          require-sigs = true;
          # Allowlist exactly which signing keys are trusted. Hardcoding this
          # prevents a rogue substituter from being silently accepted if a new
          # substituters entry is ever added without a matching key here.
          trusted-public-keys = [
            "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            "nix-wpe-webkit.cachix.org-1:ItCjHkz1Y5QcwqI9cTGNWHzcox4EqcXqKvOygxpwYHE="
          ];
          substituters = [
            "https://cache.nixos.org"
            "https://nix-wpe-webkit.cachix.org"
          ];
        };
        gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 30d";
        };
      };

      i18n.defaultLocale = "en_US.UTF-8";

      # System packages from stable
      environment.systemPackages = with pkgs; [
        vim
        git
        sbctl # for debugging Secure Boot after install
        btrfs-progs
      ];

      networking.networkmanager.enable = true;

      # Firewall
      # Deny all inbound by default. Open ports per-host as needed.
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [];
        allowedUDPPorts = [];
      };

      # SSH is explicitly disabled fleet-wide. Enable per-host only if needed,
      # e.g. services.openssh.enable = lib.mkForce true; in hosts/<name>.nix.
      services.openssh.enable = false;

      # Nix daemon access
      # Only wheel users may talk to the Nix daemon (build, fetch, etc.).
      nix.settings.allowed-users = ["@wheel"];
      # Scoped to example rather than @wheel so that future non-owner
      # accounts cannot push arbitrary store paths bypassing signatures.
      nix.settings.trusted-users = ["root" "example"];

      # sudo: restrict the binary to wheel group members
      security.sudo.execWheelOnly = true;

      # User accounts
      # Immutable users: passwd/useradd/userdel are no-ops.
      # Passwords can ONLY be changed by updating the hashedPasswordFile
      # and running nixos-rebuild. This prevents silent drift.
      users.mutableUsers = false;

      users.users.example = {
        isNormalUser = true;
        description = "Example";
        home = "/home/example";
        shell = pkgs.zsh;
        extraGroups = ["wheel" "networkmanager" "video" "audio" "kvm" "libvirtd" "input"];
        hashedPasswordFile = "/etc/secrets/example-password";
      };

      # Zsh must be enabled at system level so NixOS adds it to /etc/shells.
      # User-level config (plugins, prompt, etc.) is handled by Home Manager.
      programs.zsh.enable = true;
    };

    # Home Manager (NixOS module)
    # Wires Home Manager for user example on NixOS hosts.
    # Per-host HM overrides live in home/<host>.nix; shared config in
    # home/base.nix uses the same pattern as the standalone macOS config.
    homeManagerModule = _: {
      home-manager = {
        useGlobalPkgs = true; # reuse the system nixpkgs instance
        useUserPackages = true; # install into /etc/profiles/per-user
        backupFileExtension = "hm-backup";
        extraSpecialArgs = {
          inherit unstable starship-gruvbox-rainbow practicalli-clojure-deps-edn;
          claudeDesktop = claude-desktop.packages.x86_64-linux.claude-desktop;
        };

        users.example = {
          imports =
            [./home/base.nix]
            ++ (
              if builtins.pathExists ./home/nixOS.nix
              then [./home/nixOS.nix]
              else []
            );
          home.username = "example";
          home.homeDirectory = "/home/example";
          home.stateVersion = "25.11";
        };
      };
    };
  in {
    nixosConfigurations =
      {}
      // (
        if builtins.pathExists ./hosts/nixOS.nix
        then {
          nixOS = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {inherit self unstable;};
            modules = [
              sharedModule
              disko.nixosModules.disko
              ./disko-config.nix
              lanzaboote.nixosModules.lanzaboote
              ./hardware-configuration.nix

              # Framework 16 AMD 7040 hardware profile
              nixos-hardware.nixosModules.framework-16-7040-amd

              codex-desktop-linux.nixosModules.default

              # Home Manager: user example (home/shared.nix + home/nixOS.nix)
              home-manager.nixosModules.home-manager
              homeManagerModule

              ./hosts/nixOS.nix
          ];
          };
        }
        else {}
      );

    # Builder for a macOS host (nix-darwin). A Mac does not clone this
    # repository: its own small flake (templates/macOS) takes this one as
    # the input `base` and calls the builder, so the account name, the
    # identities and any machine-local module stay on that Mac.
    lib.mkDarwinHost = {
      system,
      # The account short name, as printed by `id -un`. Single source of
      # truth: system.primaryUser, the Nix trusted users, the home
      # directory and Home Manager derive from it. nix-darwin aborts
      # activation when it names no existing account.
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

              # Declare the user so nix-darwin and Home Manager can
              # derive home directory and shell automatically.
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

    # The template evaluated against this checkout, so that the check
    # below and the tests cover exactly what a Mac receives.
    # Usage on the Mac, from its own flake: sudo darwin-rebuild switch --flake .#macOS
    inherit ((import ./templates/macOS/flake.nix).outputs {base = self;}) darwinConfigurations;

    # `nix flake check` does not know darwinConfigurations, so evaluate
    # the macOS system here, on nixOS and on the Mac alike (flake check
    # skips other systems' checks). Discarding the string context forces
    # a full evaluation without building anything for aarch64-darwin.
    checks = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-darwin"] (system: {
      darwin-macOS-eval =
        nixpkgs.legacyPackages.${system}.writeText "darwin-macOS-eval"
        (builtins.unsafeDiscardStringContext
          self.darwinConfigurations.macOS.config.system.build.toplevel.drvPath);
    });
  };
}

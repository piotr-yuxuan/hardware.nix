{
  description = "Local flake of one Mac";

  # The shared configuration. `nix flake update base` takes its latest
  # commit.
  inputs.base.url = "github:piotr-yuxuan/hardware.nix";

  outputs = {base, ...}: {
    darwinConfigurations.macOS = base.lib.mkDarwinHost {
      system = "aarch64-darwin";
      # The account short name on this Mac, as printed by `id -un`.
      user = "example";
      # Home Manager modules of this Mac only.
      extraHmModules = [./identity.nix];
      # nix-darwin modules of this Mac only, for example a corporate
      # certificate.
      extraHostModules = [];
    };
  };
}

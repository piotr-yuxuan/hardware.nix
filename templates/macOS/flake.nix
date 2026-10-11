{
  description = "Local flake of one Mac";

  # The shared configuration, at its channel of releases. `nix flake update
  # base` takes the latest release.
  inputs.base.url = "github:piotr-yuxuan/hardware.nix/stable";

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

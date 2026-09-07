{self, pkgs}: let
  linux = self.nixosConfigurations.linux-laptop.config;
  darwin = self.darwinConfigurations.macOS.config;
  homes = [linux.home-manager.users.example darwin.home-manager.users.example];
  inherit (pkgs) lib;
  officialKey = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=";
  trusted = c:
    c.nix.settings.require-sigs
    && lib.unique c.nix.settings.trusted-users == ["root"]
    && lib.unique (map (lib.removeSuffix "/") c.nix.settings.substituters) == ["https://cache.nixos.org"]
    && lib.unique c.nix.settings.trusted-public-keys == [officialKey];
in
  assert lib.assertMsg (trusted linux && trusted darwin)
    "Only root and the official binary cache may supply Nix trust overrides";
  assert lib.assertMsg (linux.networking.firewall.enable
    && linux.networking.firewall.allowedTCPPorts == []
    && linux.networking.firewall.allowedUDPPorts == []
    && linux.networking.firewall.allowedTCPPortRanges == []
    && linux.networking.firewall.allowedUDPPortRanges == []
    && !linux.services.avahi.enable
    && !linux.programs.localsend.openFirewall
    && !linux.services.openssh.enable)
    "The Linux example must not open inbound services by default";
  assert lib.assertMsg (darwin.system.defaults.LaunchServices.LSQuarantine
    && darwin.networking.applicationFirewall.enable
    && darwin.networking.applicationFirewall.blockAllIncoming
    && !darwin.networking.applicationFirewall.allowSignedApp)
    "The macOS example must retain quarantine and inbound firewall restrictions";
  assert lib.assertMsg (lib.all (hm:
    !(hm.home.activation ? clojureMcpInstall)
    && !(hm.home.file ? ".pi/agent/extensions/pi-mcp-adapter")
    && !(hm.xdg.configFile ? "mcp/mcp.json")) homes)
    "Global agent integrations and unpinned activation downloads must remain opt-in";
  assert lib.assertMsg (!(darwin.home-manager.users.example.launchd.agents ? docker-desktop))
    "Docker Desktop must not start automatically at login";
  pkgs.runCommand "security-policy" {} "touch $out"

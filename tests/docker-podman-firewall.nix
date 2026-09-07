# Empirical test: does a published container port obey the host firewall?
#
# Checks how Docker and Podman published ports interact with the Linux firewall:
#   - rootful Docker programs the kernel packet filter (DNAT + FORWARD), so a
#     published port is reachable even when the host firewall denies all
#     inbound traffic -> it BYPASSES an INPUT-based firewall like ufw.
#   - rootless Podman forwards published ports through a userspace process that
#     opens an ordinary host socket, so traffic traverses the INPUT chain and
#     IS filtered by the host firewall.
#
# NixOS `networking.firewall` filters the INPUT chain, exactly like ufw (ufw is
# just an iptables/nftables INPUT frontend), so the result generalises to ufw.
#
# Two nodes so "reachable from outside" is unambiguous: `client` curls `server`
# over the virtual LAN; loopback shortcuts (which the firewall always allows)
# cannot mask the result.
#
# Run from the repository root on an x86_64 Linux builder:
#   nix build --no-link --impure --expr '
#     let f = builtins.getFlake (toString ./.);
#         pkgs = import f.inputs.nixpkgs { system = "x86_64-linux"; };
#     in import ./tests/docker-podman-firewall.nix { inherit pkgs; }
#   '
{pkgs}: let
  # A self-contained image (offline: NixOS tests have no network). Serves an
  # HTTP 200 on port 80 inside the container via the Python stdlib server.
  webImage = pkgs.dockerTools.buildImage {
    name = "web";
    tag = "latest";
    copyToRoot = [pkgs.python3Minimal];
    config.Cmd = ["/bin/python3" "-m" "http.server" "80"];
  };
in
  pkgs.testers.runNixOSTest {
    name = "docker-podman-firewall";

    nodes = {
      server = {pkgs, ...}: {
        # Default-deny inbound, like a hardened server or `ufw default deny`.
        # Port 4000 is explicitly opened as a positive control.
        networking.firewall = {
          enable = true;
          allowedTCPPorts = [4000];
        };

        virtualisation.docker.enable = true; # rootful
        virtualisation.podman.enable = true; # rootless prerequisites

        # Unprivileged user to run rootless Podman. linger => /run/user/1000
        # (the rootless runtime dir) exists at boot; autoSubUidGidRange grants
        # the subuid/subgid ranges user namespaces need.
        users.users.alice = {
          isNormalUser = true;
          uid = 1000;
          linger = true;
          autoSubUidGidRange = true;
        };

        # Positive control: a plain host service on the ALLOWED port, proving
        # client<->server connectivity works when the firewall permits it.
        systemd.services.control-listener = {
          wantedBy = ["multi-user.target"];
          serviceConfig.ExecStart = "${pkgs.python3Minimal}/bin/python3 -m http.server 4000 --bind 0.0.0.0";
        };

        environment.systemPackages = [pkgs.curl pkgs.iptables];
        virtualisation.memorySize = 2048;
      };

      client = {pkgs, ...}: {
        environment.systemPackages = [pkgs.curl];
      };
    };

    testScript = ''
      start_all()
      server.wait_for_unit("docker.service")
      server.wait_for_unit("control-listener.service")
      client.wait_for_unit("multi-user.target")

      # rootful Docker: publish container :80 on host :8080
      server.succeed("docker load -i ${webImage}")
      server.succeed("docker run -d --name web-docker -p 8080:80 web:latest")
      server.wait_until_succeeds("curl -fsS http://localhost:8080/ >/dev/null", timeout=600)

      # rootless Podman (as alice): publish container :80 on host :8081 (>1024,
      # so no privileged-port issue). Same image.
      server.succeed("loginctl enable-linger alice")
      server.wait_for_file("/run/user/1000")
      server.succeed(
          "su - alice -c 'export XDG_RUNTIME_DIR=/run/user/1000; podman load -i ${webImage}'"
      )
      server.succeed(
          "su - alice -c 'export XDG_RUNTIME_DIR=/run/user/1000; "
          "podman run -d --name web-podman -p 8081:80 web:latest'"
      )
      server.wait_until_succeeds(
          "su - alice -c 'export XDG_RUNTIME_DIR=/run/user/1000; curl -fsS http://localhost:8081/ >/dev/null'",
          timeout=600,
      )

      # Positive control: explicitly-allowed port 4000 is reachable from client.
      client.wait_until_succeeds("curl -fsS --max-time 5 http://server:4000/ >/dev/null", timeout=600)

      with subtest("rootful Docker port BYPASSES the deny-all firewall (reachable)"):
          client.succeed("curl -fsS --max-time 5 http://server:8080/ >/dev/null")

      with subtest("rootless Podman port is SUBJECT to the firewall (blocked)"):
          client.fail("curl -fsS --max-time 5 http://server:8081/ >/dev/null")

      # Evidence for the writeup: what is listening, and the ruleset.
      print("=== ss -tlnp (server) ===")
      print(server.succeed("ss -tlnp"))
      print("=== iptables-save (server) ===")
      print(server.succeed("iptables-save"))
    '';
  }

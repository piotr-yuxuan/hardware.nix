{
  config,
  lib,
  pkgs,
  unstable,
  ...
}: let
  # Icons and desktop metadata of the firejail-wrapped apps, for GNOME's
  # grid; their binaries stay behind the firejail wrappers.
  sandboxedAppIcons = pkgs.symlinkJoin {
    name = "sandboxed-app-icons";
    paths = [
      unstable.firefox-devedition
      unstable.vscode
      unstable.signal-desktop
      unstable.vlc
      unstable.discord
      unstable.transmission_4-gtk
    ];
    postBuild = ''
      rm -rf $out/bin $out/lib $out/libexec $out/etc 2>/dev/null || true
      # Why: docs/explanation/nixOS-audio.org, "VLC's launchers".
      rm -f $out/share/applications/vlc-open*.desktop
    '';
  };

  # TODO 2025-06-01: revisit hardware decoding in June 2025
  # after kernel and Mesa updates.
  vlcNoHwDecode = pkgs.writeShellScript "vlc-no-hw-decode" ''
    exec ${unstable.vlc}/bin/vlc --avcodec-hw=none "$@"
  '';

  # VLC's desktop file, naming vlcNoHwDecode so that the firejail module
  # points it at the wrapper. Why: docs/explanation/nixOS-audio.org,
  # "VLC's launchers".
  vlcDesktop = pkgs.runCommand "vlc-desktop" {} ''mkdir -p $out/share/applications && substitute ${unstable.vlc}/share/applications/vlc.desktop $out/share/applications/vlc.desktop --replace-fail "${unstable.vlc}/bin/vlc" "${vlcNoHwDecode}"'';

  # Signal opens links with xdg-open: a portal client first on its PATH
  # makes the host start the sandboxed browser, not one inside Signal's jail.
  signalPortalXdgOpen = pkgs.writeShellApplication {
    name = "xdg-open";
    runtimeInputs = [pkgs.glib];
    text = builtins.readFile ../scripts/signal-open-uri.sh;
  };
  signalDesktopWithPortal = pkgs.writeShellApplication {
    name = "signal-desktop-with-portal";
    runtimeInputs = [signalPortalXdgOpen];
    text = "exec ${unstable.signal-desktop}/bin/signal-desktop \"$@\"";
  };
in {
  imports =
    # Paired Bluetooth devices.
    lib.optional (builtins.pathExists ./nixOS/bluetooth-devices.nix) ./nixOS/bluetooth-devices.nix
    # Locales and keyboard layout.
    ++ lib.optional (builtins.pathExists ./nixOS/personal.nix) ./nixOS/personal.nix;

  networking.hostName = "nixOS";

  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    auto-optimise-store = true;
    # Only wheel users may talk to the Nix daemon (build, fetch, etc.).
    allowed-users = ["@wheel"];
    # example rather than @wheel, so that a future account cannot push
    # store paths that bypass signatures. NixOS adds root itself.
    trusted-users = ["example"];
  };

  networking.networkmanager.enable = true;

  security.sudo.execWheelOnly = true;

  # Passwords change only through hashedPasswordFile and a rebuild.
  users.mutableUsers = false;

  users.users.example = {
    isNormalUser = true;
    description = "Example";
    shell = pkgs.zsh;
    extraGroups = ["wheel" "networkmanager" "video" "audio" "kvm" "libvirtd" "input"];
    hashedPasswordFile = "/etc/secrets/example-password";
  };

  # Puts zsh in /etc/shells; Home Manager configures it.
  programs.zsh.enable = true;

  # Boot
  boot.loader.efi.canTouchEfiVariables = true;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
    autoGenerateKeys.enable = true;
    autoEnrollKeys = {
      enable = true;
      includeMicrosoftKeys = true;
    };
  };

  # The 7.2 series, fixed since 7.2.8 for a crash after hibernation. Why
  # and when to change: docs/explanation/nixOS-kernel-choice.org.
  boot.kernelPackages = pkgs.linuxPackages_7_2;

  # The console and the LUKS prompt use the XKB layout that
  # hosts/nixOS/personal.nix sets.
  console.useXkbConfig = true;
  console.earlySetup = true;

  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Default layout of the Iiyama monitor, at a fixed 120 Hz; GNOME's saved
  # profiles win. Why: docs/explanation/nixOS-iiyama-display.org.
  environment.etc."xdg/monitors.xml".source = ../config/gnome/monitors.xml;

  programs.codexDesktopLinux.enable = true;

  # Sound
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # Bluetooth devices switch to call mode only by hand. Why:
    # docs/explanation/nixOS-audio.org, "Call mode by hand".
    wireplumber.extraConfig."51-bluetooth-policy"."wireplumber.settings"."bluetooth.autoswitch-to-headset-profile" = false;
    # Pauses sandboxed players too when their output goes away. Why:
    # docs/explanation/nixOS-audio.org, "Pausing sandboxed players".
    wireplumber.configPackages = [
      (pkgs.callPackage ../packages/wireplumber-mpris-pause.nix {
        wireplumber = config.services.pipewire.wireplumber.package;
      })
    ];
  };

  # The time zone follows geoclue's location, resolved offline, again at
  # each network change. GNOME drops geoclue-demo-agent from the
  # whitelist, but automatic-timezoned runs it: without it geoclue stops
  # reporting after the first query. Keep geoclue's WiFi source, with
  # GeoIP beside it for tethering: disabling WiFi removes url= from the
  # configuration, and geoclue fails with "Could not parse locate URL ''".
  # gsd-datetime alone failed on Nominatim answers without a time zone.
  services.automatic-timezoned.enable = true;
  services.geoclue2.whitelistedAgents = ["gnome-shell" "geoclue-demo-agent"];

  # Lets the active local session set the time zone without a prompt:
  # GNOME's own automatic time zone (dconf, home/nixOS.nix) and manual
  # changes. automatic-timezoned brings its own rule for its own user.
  security.polkit.extraConfig = builtins.readFile ../config/polkit/set-timezone.rules;

  environment.systemPackages = [
    pkgs.vim
    pkgs.git
    pkgs.sbctl # for debugging Secure Boot after install
    pkgs.compsize
    pkgs.smartmontools
    sandboxedAppIcons
    pkgs.virt-manager
    unstable.torsocks
  ];

  # Rootless Podman and a Docker-compatible CLI for the ordinary user.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };
  # The CLI runs rootlessly without a root-owned API socket.
  systemd.sockets.podman.enable = false;

  virtualisation.containers = {
    # Registry allow-list, including third-party publishers. This does not
    # verify image signatures; HTTPS certificate verification stays enabled.
    policy = {
      default = [{type = "reject";}];
      transports.docker = {
        "docker.io" = [{type = "insecureAcceptAnything";}];
        "public.ecr.aws" = [{type = "insecureAcceptAnything";}];
        "quay.io" = [{type = "insecureAcceptAnything";}];
        "docker.elastic.co" = [{type = "insecureAcceptAnything";}];
        "ghcr.io" = [{type = "insecureAcceptAnything";}];
        "mcr.microsoft.com" = [{type = "insecureAcceptAnything";}];
      };
      transports."containers-storage" = {
        "[overlay@/home/example/.local/share/containers/storage]" = [
          {type = "insecureAcceptAnything";}
        ];
      };
    };
    registries.search = ["docker.io"];
  };

  # QEMU/KVM, with virt-manager. macOS guests on AMD (OSX-KVM) need KVM
  # to ignore unhandled MSRs; nesting allows VMs in VMs.
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
    };
  };

  boot.extraModprobeConfig = ''
    options kvm_amd nested=1
    options kvm ignore_msrs=1 report_ignored_msrs=0
  '';

  # NVMe health, reported to the journal, terminals and GNOME. Any local
  # user may then send notifications, fine on a single-user laptop; the
  # X11 path (xmessage) does not reach Wayland.
  services.smartd = {
    enable = true;
    notifications.systembus-notify.enable = true;
    notifications.x11.enable = false;
  };

  services.btrfs.autoScrub = {
    enable = true;
    # Monthly by default. Named, not derived, because the VM mounts no
    # btrfs and its scrub assertion needs a file system.
    fileSystems = ["/"];
  };

  # Background deduplication; one instance covers every subvolume of the
  # single btrfs file system.
  services.beesd.filesystems.root = {
    spec = "/";
    hashTableSizeMB = 128;
    verbosity = "warning";
    extraOptions = ["--loadavg-target" "4.0"];
  };

  # Hourly snapshots of /home/example in /.snapshots; a run missed while
  # the machine was off happens at the next boot.
  services.btrbk.instances.home = {
    onCalendar = "hourly";
    settings = {
      snapshot_create = "always"; # no remote target, so force local snapshots
      snapshot_preserve_min = "2h";
      snapshot_preserve = "12h 7d 2w"; # 12 hourly, 7 daily, 2 weekly

      volume."/" = {
        snapshot_dir = ".snapshots";
        subvolume."home/example" = {};
      };
    };
  };

  # btrbk runs btrfs through sudo, which execWheelOnly keeps to wheel;
  # its sudoers rules still allow only btrfs, mkdir and readlink.
  users.users.btrbk.extraGroups = ["wheel"];

  # When a snapshot fails: a message in every terminal, Emacs and GNOME.
  systemd.services."btrbk-home".unitConfig.OnFailure = ["btrbk-home-failure-alert.service"];
  systemd.services."btrbk-home-failure-alert" = {
    description = "Alert on btrbk snapshot failure";
    path = [pkgs.libnotify unstable.emacs-pgtk];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${../scripts/btrbk-failure-alert.sh}";
    };
  };

  # Power management
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandlePowerKey = "hibernate";
  };

  systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";

  # Reloads i2c_hid_acpi when the PixArt touchpad sends timestamps but no
  # positions, as it sometimes does: docs/reference/package-guide.org.
  systemd.services."touchpad-watchdog" = {
    description = "PixArt touchpad stuck-state watchdog";
    wantedBy = ["multi-user.target"];
    after = ["systemd-modules-load.service"];
    path = [pkgs.python3 pkgs.kmod];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;
      ExecStart = "${pkgs.bash}/bin/bash ${../scripts/touchpad-watchdog.sh} ${../scripts/touchpad_watchdog.py}";
    };
  };

  # Kernel and network hardening, value by value in
  # docs/explanation/nixOS-security-posture.org. kexec is locked by hand:
  # security.protectKernelImage would also forbid hibernation.
  boot.kernel.sysctl = {
    "kernel.kexec_load_disabled" = true;
    "kernel.yama.ptrace_scope" = 2;
    "kernel.kptr_restrict" = 2;
    "kernel.sysrq" = 0;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "kernel.dmesg_restrict" = 1;

    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = false;
    "net.ipv4.conf.default.accept_redirects" = false;
    "net.ipv6.conf.all.accept_redirects" = false;
    "net.ipv6.conf.default.accept_redirects" = false;
    "net.ipv4.conf.all.send_redirects" = false;
    "net.ipv4.conf.default.send_redirects" = false;
    "net.ipv4.conf.all.secure_redirects" = false;
    "net.ipv4.conf.default.secure_redirects" = false;
    "net.ipv4.conf.all.log_martians" = true;
    "net.ipv4.conf.default.log_martians" = true;
  };

  # GNOME asks before authorising a new Thunderbolt or USB4 device.
  services.hardware.bolt.enable = true;

  # A firmware race of Framework AMD laptops makes the Iiyama's USB hub
  # cycle. The udev rules keep the hub and its controller powered; the
  # watchdog resets the USB-C stack when it sees the cycle. Story and
  # references: docs/reference/package-guide.org.
  services.udev.extraRules =
    builtins.readFile ../config/udev/99-iiyama-usb-hub.rules;

  systemd.services."usbc-monitor-stabilize" = {
    description = "Watchdog for USB-C monitor hub cycling";
    wantedBy = ["multi-user.target"];
    after = ["systemd-journald.service"];
    path = [pkgs.kmod];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;
      ExecStart = "${pkgs.bash}/bin/bash ${../scripts/usbc-monitor-stabilize.sh}";
    };
  };

  boot.kernelParams = [
    "quiet"
  ];

  boot.plymouth.enable = true;

  # VA-API decoding saves battery; Mesa and the rest come with
  # nixos-hardware's profile.
  hardware.graphics.extraPackages = with pkgs; [
    libvdpau-va-gl # VDPAU-over-VA-API shim for apps that use VDPAU
  ];

  # Local model inference through the Radeon 780M's Mesa Vulkan driver.
  # Start and stop explicitly with sudo systemctl start/stop ollama.
  services.ollama = {
    enable = true;
    package = unstable.ollama-vulkan;
    environmentVariables = {
      OLLAMA_NO_CLOUD = "1";
      OLLAMA_DEBUG = "1";
    };
  };
  systemd.services.ollama.wantedBy = lib.mkForce [];

  # Audit: every execve, and writes to the user, Secure Boot and sudo
  # files (docs/explanation/nixOS-security-posture.org).
  security.auditd.enable = true;
  security.audit.rules = [
    "-a always,exit -F arch=b64 -S execve -k exec"
    "-w /etc/shadow -p wa -k shadow"
    "-w /etc/passwd -p wa -k passwd"
    "-w /etc/group -p wa -k group"
    "-w /etc/secureboot -p wa -k secureboot"
    "-w /etc/sudoers -p wa -k sudoers"
    "-w /etc/sudoers.d -p wa -k sudoers"
  ];

  # Directories polkitd looks for, so that it logs no warning at start.
  systemd.tmpfiles.rules = [
    "d /run/polkit-1/rules.d 0755 polkitd root -"
    "d /usr/local/share/polkit-1/rules.d 0755 polkitd root -"
  ];

  # Crash dumps in /var/lib/systemd/coredump, read with coredumpctl.
  systemd.coredump = {
    settings.Coredump = {
      Storage = "external";
      Compress = "yes";
      MaxUse = "2G";
    };
  };

  # /tmp in RAM (half of it at most), so nothing there reaches the disk.
  boot.tmp.useTmpfs = true;

  # Firejail sandboxes for GUI apps. Each profile is an interpolated
  # string: the module applies toString, so a bare path would leave the
  # wrapper without a dependency on its profile, which the garbage
  # collector would then remove.
  programs.firejail = {
    enable = true;
    wrappedBinaries = {
      firefox-devedition = {
        executable = "${unstable.firefox-devedition}/bin/firefox-devedition";
        profile = "${../config/firejail/firefox.profile}";
        desktop = "${unstable.firefox-devedition}/share/applications/firefox-devedition.desktop";
      };
      code = {
        executable = "${unstable.vscode}/bin/code";
        profile = "${../config/firejail/vscode.profile}";
        desktop = "${unstable.vscode}/share/applications/code.desktop";
      };
      signal-desktop = {
        executable = "${signalDesktopWithPortal}/bin/signal-desktop-with-portal";
        profile = "${../config/firejail/signal.profile}";
        desktop = "${unstable.signal-desktop}/share/applications/signal.desktop";
      };
      vlc = {
        executable = "${vlcNoHwDecode}";
        profile = "${../config/firejail/vlc.profile}";
        desktop = "${vlcDesktop}/share/applications/vlc.desktop";
      };
      # The player of Emacs ready-player; not in home.packages, which
      # would shadow this wrapper. Why: docs/explanation/nixOS-audio.org,
      # "mpv for ready-player".
      mpv = {
        executable = "${unstable.mpv.override {scripts = [unstable.mpvScripts.mpris];}}/bin/mpv";
        profile = "${../config/firejail/mpv.profile}";
      };
      Discord = {
        executable = "${unstable.discord}/bin/discord";
        profile = "${../config/firejail/discord.profile}";
        desktop = "${unstable.discord}/share/applications/discord.desktop";
      };
      transmission-gtk = {
        executable = "${unstable.transmission_4-gtk}/bin/transmission-gtk";
        profile = "${../config/firejail/transmission-gtk.profile}";
        desktop = "${unstable.transmission_4-gtk}/share/applications/transmission-gtk.desktop";
      };
    };
  };

  # The picture GDM and GNOME Settings show for the user.
  system.activationScripts.accountsservice-avatar = lib.mkIf (builtins.pathExists ../img/nixOS/avatar.png) (lib.stringAfter ["users"] "install -D -m 0644 ${../img/nixOS/avatar.png} /var/lib/AccountsService/icons/example");

  # LocalSend, file sharing like AirDrop; opens port 53317.
  programs.localsend = {
    enable = true;
    package = unstable.localsend;
  };

  # Run downloaded Linux executables, including tools installed by uv/pip.
  programs.nix-ld.enable = true;

  # Standalone Python uses OpenSSL's conventional CA bundle path.
  # Reuse the NixOS bundle, including any configured additional roots.
  environment.etc."ssl/cert.pem".source = "/etc/ssl/certs/ca-certificates.crt";

  # nh, with a weekly `nh clean`. No flake is set: run `nh os switch .`
  # in the checkout.
  programs.nh = {
    enable = true;
    package = unstable.nh;
    clean = {
      enable = true;
      extraArgs = "--keep 5 --keep-since 7d";
    };
  };

  # Tor runs all the time, on localhost only, so that its circuit is
  # ready when the transparent proxy below starts; SOCKS stays on 9050.
  services.tor = {
    enable = true;
    client.enable = true;
    settings = {
      TransPort = [
        {
          addr = "127.0.0.1";
          port = 9040;
        }
      ];
      DNSPort = [
        {
          addr = "127.0.0.1";
          port = 5353;
        }
      ];
      VirtualAddrNetworkIPv4 = "10.192.0.0/10";
    };
  };

  # Routes all traffic through Tor while started by hand
  # (`sudo systemctl start tor-transparent-proxy`), with nftables rules in
  # a table of their own, apart from the firewall's.
  systemd.services."tor-transparent-proxy" = {
    description = "Tor transparent proxy (nftables redirect)";
    requires = ["tor.service"];
    after = ["tor.service"];
    path = [pkgs.nftables];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash ${../scripts/tor-transparent-proxy-on.sh}";
      ExecStop = "${pkgs.bash}/bin/bash ${../scripts/tor-transparent-proxy-off.sh}";
    };
  };

  system.stateVersion = "25.11";

  # `nixos-rebuild build-vm --flake .#nixOS` builds this configuration as
  # a VM; log in as example, password test.
  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 4096;
      cores = 4;
    };

    users.users.example = {
      password = "test";
      hashedPasswordFile = lib.mkForce null;
    };

    # Lanzaboote (Secure Boot) is not available in the VM, so it boots
    # with systemd-boot.
    boot.lanzaboote.enable = lib.mkForce false;
    boot.loader.systemd-boot.enable = true;

    # The VM has its own disk, not the laptop's disko layout.
    disko.devices = lib.mkForce {};

    # The VM has no amdgpu: without this, the initrd would stall waiting
    # for it.
    hardware.amdgpu.initrd.enable = lib.mkForce false;
  };
}

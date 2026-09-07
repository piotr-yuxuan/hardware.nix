{
  lib,
  pkgs,
  self,
  unstable,
  ...
}: let
  # Provide icons and metadata from firejail-wrapped packages so GNOME
  # can display them in the application grid.  Only share/ is kept;
  # the actual binaries are shadowed by firejail wrappers.
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
    '';
  };

  # Signal's Electron shell opens links by spawning xdg-open.  Put a narrow
  # portal client first on Signal's PATH so the host launches the configured
  # Firejail-wrapped browser instead of nesting Firefox inside Signal's jail.
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
  imports = [
    ./linux-laptop/bluetooth-devices.nix
  ];

  networking.hostName = "linux-laptop";

  # Do not advertise this machine or open multicast discovery ports.
  services.avahi.enable = lib.mkForce false;
  services.avahi.openFirewall = false;

  # Boot
  boot.loader.systemd-boot.enable = lib.mkForce false;
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

  # Initrd
  boot.initrd.systemd.enable = true;
  # LUKS device is declared by disko; do NOT redeclare it here.
  # Early KMS (amdgpu in initrd) is handled by nixos-hardware's
  # framework-16-7040-amd profile via hardware.amdgpu.initrd.enable.

  # Hibernate
  boot.resumeDevice = "/dev/vg-linux-laptop/lv-swap";

  # Use the latest kernel version.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Keyboard layout (EVERYWHERE)
  # 1. XKB layout (used by GNOME/Wayland and as source for console)
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # 2. Virtual console (TTY): derive from xkb so they always match
  console.useXkbConfig = true;
  # Push the keymap into initrd so LUKS passphrase prompt uses it too
  console.earlySetup = true;

  # GNOME + Wayland
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Wayland: GNOME 50 (NixOS 26.05) is Wayland-only; the former
  # services.displayManager.gdm.wayland toggle was removed.

  services.gnome.gnome-keyring.enable = true;
  security.pam.services.gdm-password.enableGnomeKeyring = true;

  programs.codexDesktopLinux.enable = true;

  # Sound
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Automatic timezone (automatic-timezoned via geoclue)
  #
  # Override the fleet-wide UTC fallback (flake.nix) so the
  # timezone can be set dynamically via geolocation.
  #
  # automatic-timezoned queries geoclue for the current location,
  # resolves it to a timezone using an offline tzf-rs database (no
  # external API call), and calls org.freedesktop.timedate1.SetTimezone
  # via systemd-timedated.  It re-runs on every LocationUpdated signal
  # from geoclue, which fires each time the network changes.
  #
  # The GNOME desktop module sets enableDemoAgent = false and removes
  # "geoclue-demo-agent" from the geoclue agent whitelist, because
  # GNOME Shell acts as the session agent.  automatic-timezoned runs
  # its own copy of the demo agent as a system service; we must add it
  # back to the whitelist explicitly, otherwise geoclue rejects the
  # agent and stops emitting LocationUpdated after the first boot query.
  #
  # WiFi is left enabled (BeaconDB) so the source is properly
  # initialised with a valid URL.  geoclue also runs a GeoIP source in
  # parallel; when no WiFi networks are visible (e.g. USB/phone
  # tethering) the GeoIP result is used instead.  Disabling WiFi via
  # the NixOS option omits the url= key from the config file, which
  # causes geoclue to log "Could not parse locate URL ''" and fail.
  #
  # gsd-datetime (enabled by automatic-timezone = true in dconf) was
  # tried first but it depends on a Nominatim API response that does not
  # always include a timezone field, causing a null-pointer assertion.
  time.timeZone = lib.mkForce null;
  services.automatic-timezoned.enable = true;
  services.geoclue2.whitelistedAgents = ["gnome-shell" "geoclue-demo-agent"];

  security.polkit.extraConfig = builtins.readFile ../config/polkit/set-timezone.rules;

  # Time synchronisation
  # NTP via systemd-timesyncd: keeps the hardware clock accurate.
  # mkDefault so the qemu-vm module can disable it inside the VM.
  services.timesyncd.enable = lib.mkDefault true;

  # Date/time locale
  # Custom locales for dates (day-month-year), measurements, and paper sizes.
  # The fleet-wide defaultLocale stays en_US.UTF-8 (set in flake.nix).
  i18n.extraLocaleSettings = {
    LC_TIME = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
  };

  # Btrfs tools
  environment.systemPackages = [
    pkgs.compsize
    sandboxedAppIcons
    pkgs.virt-manager
    pkgs.qemu_kvm
    unstable.torsocks
  ];

  # QEMU/KVM virtualisation (OSX-KVM and general VM use)
  #
  # libvirtd provides a management daemon for QEMU/KVM VMs.
  # virt-manager offers a GUI for creating and managing VMs.
  # The KVM modprobe options are required for macOS guest support on
  # AMD: ignore_msrs prevents crashes on unhandled MSR accesses, and
  # nested=1 enables nested virtualisation.
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

  # Btrfs maintenance
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = ["/"];
  };

  # Btrfs block-level deduplication (bees)
  #
  # Bees scans the filesystem for duplicate extents and deduplicates
  # them in the background using FIDEDUPERANGE.  This is transparent
  # to user programmes and users: files keep their original paths,
  # permissions, and contents.  Bees is compression-aware and works
  # well with the zstd compression already enabled on all subvolumes.
  #
  # All subvolumes (@root, @example, @example-cache, @.snapshots) live
  # on the same btrfs filesystem (lv-btrfs), so one bees instance
  # covers everything.
  services.beesd.filesystems.root = {
    spec = "/";
    hashTableSizeMB = 128;
    verbosity = "warning";
    extraOptions = ["--loadavg-target" "4.0"];
  };

  # Automated btrfs snapshots (home directory)
  # Hourly local snapshots of /home/example into /.snapshots/.
  # Persistent=true on the timer guarantees a snapshot on every boot
  # (catches up missed runs while the machine was off).
  services.btrbk.instances.home = {
    onCalendar = "hourly";
    settings = {
      snapshot_create = "always"; # no remote target, so force local snapshots
      snapshot_preserve_min = "2h";
      snapshot_preserve = "24h 5d 3w"; # 24 hourly, 5 daily, 3 weekly

      volume."/" = {
        snapshot_dir = ".snapshots";
        subvolume."home/example" = {};
      };
    };
  };

  systemd.timers."btrbk-home".timerConfig.Persistent = true;

  # The btrbk service uses sudo to run btrfs commands as root.
  # security.sudo.execWheelOnly restricts the sudo binary to wheel
  # members, so the btrbk system user needs to be in that group.
  # Its actual privileges are still limited by sudoers rules (only
  # btrfs, mkdir, readlink with NOPASSWD).
  users.users.btrbk.extraGroups = ["wheel"];

  # Snapshot failure alert
  # PTY broadcast + critical desktop notification when btrbk fails.
  systemd.services."btrbk-home".unitConfig.OnFailure = ["btrbk-home-failure-alert.service"];
  systemd.services."btrbk-home-failure-alert" = {
    description = "Alert on btrbk snapshot failure";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "btrbk-failure-alert" ''
        stat_cmd=${pkgs.coreutils}/bin/stat
        id_cmd=${pkgs.coreutils}/bin/id
        notify_send=${pkgs.libnotify}/bin/notify-send
        emacsclient=${unstable.emacs-pgtk}/bin/emacsclient
        ${builtins.readFile ../scripts/btrbk-failure-alert.sh}
      '';
    };
  };

  # Power management
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandlePowerKey = "hibernate";
  };

  # 26.05: systemd.sleep.extraConfig was replaced by settings.Sleep.
  systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";

  # Touchpad watchdog
  #
  # The PixArt PIXA3854 I2C HID touchpad sometimes enters a stuck
  # state where the firmware sends only MSC_TIMESTAMP heartbeat
  # events with no position data.  This happens both after
  # suspend/resume and spontaneously during normal use.  The
  # watchdog samples raw evdev events and reloads i2c_hid_acpi when
  # it detects the stuck signature, recovering the touchpad within
  # seconds without user intervention.
  systemd.services."touchpad-watchdog" = {
    description = "PixArt touchpad stuck-state watchdog";
    wantedBy = ["multi-user.target"];
    after = ["systemd-modules-load.service"];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;
      ExecStart = pkgs.writeScript "touchpad-watchdog" ''
        #!${pkgs.zsh}/bin/zsh
        python_cmd=${pkgs.python3}/bin/python3
        watchdog_py=${../scripts/touchpad_watchdog.py}
        modprobe_cmd=${pkgs.kmod}/bin/modprobe
        sleep_cmd=${pkgs.coreutils}/bin/sleep
        ${builtins.readFile ../scripts/touchpad-watchdog.zsh}
      '';
    };
  };

  boot.kernel.sysctl = {
    # Kernel hardening security.protectKernelImage adds
    # kexec_load_disabled (good) but also injects "nohibernate" into
    # boot.kernelParams, which conflicts with suspend-then-hibernate
    # and the explicit resume device. Since this laptop uses
    # LUKS-encrypted swap and Secure Boot, the hibernate image is
    # encrypted at rest and the boot chain validated, so hibernation
    # is not an attack vector. Apply the kexec lockdown manually
    # instead.
    "kernel.kexec_load_disabled" = true;
    # Restrict ptrace to direct parent only (blocks debugger-based escalation)
    "kernel.yama.ptrace_scope" = 2;
    # Hide kernel pointers from unprivileged users
    "kernel.kptr_restrict" = 2;
    # Disable Magic SysRq (not needed on a personal laptop)
    "kernel.sysrq" = 0;
    # Prevent unprivileged BPF (large kernel attack surface)
    "kernel.unprivileged_bpf_disabled" = 1;
    # Harden BPF JIT compiler
    "net.core.bpf_jit_harden" = 2;
    # Restrict dmesg to processes with CAP_SYSLOG (root / journalctl)
    "kernel.dmesg_restrict" = 1;

    # Network stack hardening
    # Strict reverse path filtering: drop packets whose source address
    # would not be routed back through the same interface.
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    # Reject ICMP redirects (not a router, never needs them)
    "net.ipv4.conf.all.accept_redirects" = false;
    "net.ipv4.conf.default.accept_redirects" = false;
    "net.ipv6.conf.all.accept_redirects" = false;
    "net.ipv6.conf.default.accept_redirects" = false;
    "net.ipv4.conf.all.send_redirects" = false;
    "net.ipv4.conf.default.send_redirects" = false;
    "net.ipv4.conf.all.secure_redirects" = false;
    "net.ipv4.conf.default.secure_redirects" = false;
    # Log martian (impossible source) packets for detection
    "net.ipv4.conf.all.log_martians" = true;
    "net.ipv4.conf.default.log_martians" = true;
  };

  # Thunderbolt / USB4 authorisation
  # Framework 16 AMD 7040 has USB4 (Thunderbolt 4). Bolt lets GNOME
  # prompt the user before authorising new Thunderbolt/USB4 devices,
  # preventing rogue DMA attacks from plugged-in peripherals.
  services.hardware.bolt.enable = true;

  # USB-C monitor (Iiyama PL3494WQ) hotplug stabilisation
  #
  # The Infineon CYPD82xx PD controller firmware on Framework AMD
  # laptops has a race during USB-C DP Alt Mode negotiation that
  # tears down the USB4 tunnel, disconnecting the monitor's Realtek
  # hub (0bda:5420) and restarting the handshake.  This is a known,
  # unfixed issue across all Framework AMD models (7040, AI 300,
  # AI 370), tracked since June 2024.  No kernel parameter,
  # firmware update, or upstream patch resolves it.
  #
  # References:
  #   https://community.frame.work/t/tracking-usb-c-error-on-boot/52012
  #   https://community.frame.work/t/display-connecting-infinitely-via-usb-c/68717
  #   https://community.frame.work/t/solved-issues-connecting-to-usb-c-monitor-amd-ryzen-ai-350/68468
  #
  # Two layers cooperate to mitigate this:
  #
  # 1. udev (99-iiyama-usb-hub.rules): disable runtime PM on the
  #    Realtek hub, pin the xHCI controller (0000:c3:00.3) to D0,
  #    and forbid D3cold.  This narrows the race window.
  #
  # 2. Watchdog (usbc-monitor-stabilize): polls journalctl for rapid
  #    disconnect events on bus 5-1.  When cycling is detected it
  #    reloads ucsi_acpi and rebinds the xHCI controller, forcing a
  #    clean Alt Mode renegotiation.  This breaks the loop that
  #    otherwise takes minutes to self-resolve.
  services.udev.extraRules =
    builtins.readFile ../config/udev/99-iiyama-usb-hub.rules;

  systemd.services."usbc-monitor-stabilize" = {
    description = "Watchdog for USB-C monitor hub cycling";
    wantedBy = ["multi-user.target"];
    after = ["systemd-journald.service"];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;
      ExecStart = pkgs.writeShellScript "usbc-monitor-stabilize" ''
        journalctl_cmd=${pkgs.systemd}/bin/journalctl
        grep_cmd=${pkgs.gnugrep}/bin/grep
        modprobe_cmd=${pkgs.kmod}/bin/modprobe
        sleep_cmd=${pkgs.coreutils}/bin/sleep
        ${builtins.readFile ../scripts/usbc-monitor-stabilize.sh}
      '';
    };
  };

  # Crash logging (pstore)
  # On kernel panic, the firmware writes the last dmesg to UEFI NVRAM
  # ("pstore").  systemd-pstore (already enabled by NixOS) archives it
  # to /var/lib/systemd/pstore/ on the next boot.  The kernel param
  # below ensures the full ring buffer is flushed to pstore on panic.
  boot.kernelParams = [
    "printk.always_kmsg_dump=1"
    "quiet"
    "splash"
  ];

  # Plymouth (graphical boot splash)
  boot.plymouth.enable = true;

  # GPU acceleration (AMD Radeon 780M / Phoenix iGPU)
  # nixos-hardware already enables:
  #   • hardware.graphics.enable       (Mesa: OpenGL + Vulkan/RADV)
  #   • hardware.graphics.enable32Bit  (32-bit Mesa for Wine/Steam)
  #   • hardware.amdgpu.initrd.enable  (early KMS in initrd)
  # VA-API: hardware video decode/encode that saves battery on laptop.
  hardware.graphics.extraPackages = with pkgs; [
    # AMD VA-API driver (H.264, HEVC, VP9, AV1 decode on the iGPU)
    libvdpau-va-gl # VDPAU-over-VA-API shim for apps that use VDPAU
  ];

  # Tell VA-API to use the radeonsi driver (Mesa's built-in)
  environment.variables.LIBVA_DRIVER_NAME = "radeonsi";

  # Audit subsystem (intrusion detection)
  security.audit.enable = true;
  security.auditd.enable = true;
  security.audit.rules = [
    # Log all execve calls (catches reverse shells, unexpected binaries)
    "-a always,exit -F arch=b64 -S execve -k exec"
    # Monitor changes to authentication databases
    "-w /etc/shadow -p wa -k shadow"
    "-w /etc/passwd -p wa -k passwd"
    "-w /etc/group -p wa -k group"
    # Monitor Secure Boot key material
    "-w /etc/secureboot -p wa -k secureboot"
    # Monitor sudo configuration
    "-w /etc/sudoers -p wa -k sudoers"
    "-w /etc/sudoers.d -p wa -k sudoers"
  ];

  # Polkit: create missing FHS rules directories so polkitd does not
  # log harmless "Error opening directory" warnings at startup.
  systemd.tmpfiles.rules = [
    "d /run/polkit-1/rules.d 0755 polkitd root -"
    "d /usr/local/share/polkit-1/rules.d 0755 polkitd root -"
  ];

  # Coredump capture for userspace crashes
  # systemd-coredump stores dumps in /var/lib/systemd/coredump/ so you
  # can inspect them after reboot with `coredumpctl list` / `coredumpctl info`.
  systemd.coredump = {
    enable = true;
    # 26.05: extraConfig was replaced by settings.Coredump.
    settings.Coredump = {
      Storage = "external";
      Compress = "yes";
      MaxUse = "2G";
    };
  };

  # /tmp as tmpfs (RAM backed, cleared on reboot)
  # Prevents sensitive temporary files from persisting on disk.
  # Defaults to 50 % of RAM; large builds should use ~/tmp instead.
  boot.tmp.useTmpfs = true;

  # Automatic security updates
  # Persistent=true ensures missed triggers (laptop off or hibernated)
  # are caught up on the next boot.
  system.autoUpgrade = {
    enable = true;
    flake = toString self;
    dates = "04:00";
    randomizedDelaySec = "30min";
    persistent = true;
  };

  # Firejail: filesystem sandboxing for GUI applications
  #
  # Each profile is wrapped with builtins.path so Nix copies it into
  # its own store entry that the derivation references.  Without this,
  # the profile resolves to the flake-source store path, which is NOT
  # registered as a build input and gets garbage-collected.
  programs.firejail = {
    enable = true;
    wrappedBinaries = {
      firefox-devedition = {
        executable = "${unstable.firefox-devedition}/bin/firefox-devedition";
        profile = builtins.path {
          path = ../config/firejail/firefox.profile;
          name = "firejail-firefox-profile";
        };
        desktop = "${unstable.firefox-devedition}/share/applications/firefox-devedition.desktop";
      };
      code = {
        executable = "${unstable.vscode}/bin/code";
        profile = builtins.path {
          path = ../config/firejail/vscode.profile;
          name = "firejail-vscode-profile";
        };
        desktop = "${unstable.vscode}/share/applications/code.desktop";
      };
      signal-desktop = {
        executable = "${signalDesktopWithPortal}/bin/signal-desktop-with-portal";
        profile = builtins.path {
          path = ../config/firejail/signal.profile;
          name = "firejail-signal-profile";
        };
        desktop = "${unstable.signal-desktop}/share/applications/signal.desktop";
      };
      vlc = {
        # Hardware decoding is disabled for this hardware workaround.
        executable = pkgs.writeShellScript "vlc-no-hw-decode" ''
          exec ${unstable.vlc}/bin/vlc --avcodec-hw=none "$@"
        '';
        profile = builtins.path {
          path = ../config/firejail/vlc.profile;
          name = "firejail-vlc-profile";
        };
        desktop = "${unstable.vlc}/share/applications/vlc.desktop";
      };
      Discord = {
        executable = "${unstable.discord}/bin/discord";
        profile = builtins.path {
          path = ../config/firejail/discord.profile;
          name = "firejail-discord-profile";
        };
        desktop = "${unstable.discord}/share/applications/discord.desktop";
      };
      transmission-gtk = {
        executable = "${unstable.transmission_4-gtk}/bin/transmission-gtk";
        profile = builtins.path {
          path = ../config/firejail/transmission-gtk.profile;
          name = "firejail-transmission-gtk-profile";
        };
        desktop = "${unstable.transmission_4-gtk}/share/applications/transmission-gtk.desktop";
      };
    };
  };

  # Example avatar for GDM and GNOME (replace with your own image)
  #
  # AccountsService reads /var/lib/AccountsService/icons/<user> to
  # display the profile picture on the lock screen and in Settings.
  system.activationScripts.accountsservice-avatar = lib.stringAfter ["users"] ''
    avatar_src=${../img/wallpaper.jpg}
    ${builtins.readFile ../scripts/accountsservice-avatar.sh}
  '';

  # LocalSend: cross-platform file sharing (AirDrop alternative)
  # Receiving requires explicitly opening a port on a trusted interface.
  programs.localsend = {
    enable = true;
    package = unstable.localsend;
    openFirewall = false;
  };

  # nh: Nix CLI helper providing human-friendly rebuild, diff, and GC.
  # The module sets NH_OS_FLAKE (which takes precedence over NH_FLAKE for
  # `nh os` commands) and installs a weekly `nh clean` systemd service.
  programs.nh = {
    enable = true;
    package = unstable.nh;
    flake = toString self;
    clean = {
      enable = true;
      # Keep the last 5 generations and anything touched in the last 7 days.
      extraArgs = "--keep 5 --keep-since 7d";
    };
  };

  # Disable the fleet-wide nix.gc.automatic (set in flake.nix sharedModule)
  # because nh clean (above) provides a more capable replacement: it prunes
  # gcroots in addition to old generations and respects --keep-since.
  nix.gc.automatic = lib.mkForce false;

  # Tor: anonymous communication network
  #
  # The daemon runs at all times (lightweight, only listens on
  # localhost) so the circuit is already established when the
  # transparent proxy is toggled on.  TransPort and DNSPort handle
  # redirected traffic; the default SOCKSPort (9050) remains available
  # for apps that can use SOCKS directly (e.g. torsocks).
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

  # Tor transparent proxy (toggleable)
  #
  # A oneshot service that installs nftables redirect rules on start
  # and removes them on stop.  Not started at boot; the user must
  # explicitly run: sudo systemctl start tor-transparent-proxy
  #
  # The nftables rules live in a dedicated table
  # (tor-transparent-proxy) that is independent of the NixOS firewall
  # table.  Deleting it on stop cannot corrupt the system firewall.
  systemd.services."tor-transparent-proxy" = {
    description = "Tor transparent proxy (nftables redirect)";
    requires = ["tor.service"];
    after = ["tor.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "tor-transparent-proxy-on" ''
        nft_cmd=${pkgs.nftables}/bin/nft
        id_cmd=${pkgs.coreutils}/bin/id
        ${builtins.readFile ../scripts/tor-transparent-proxy-on.sh}
      '';
      ExecStop = pkgs.writeShellScript "tor-transparent-proxy-off" ''
        nft_cmd=${pkgs.nftables}/bin/nft
        ${builtins.readFile ../scripts/tor-transparent-proxy-off.sh}
      '';
    };
  };

  system.stateVersion = "25.11";

  # Maestral systemd user services are defined in home/linux-laptop.nix
  # (Home Manager) so they only start for user example, not for the
  # GDM greeter. Placing them here in systemd.user.services would
  # install global unit files under /etc/systemd/user/ visible to
  # every user session, causing repeated crashes and coredumps in
  # the greeter that block the login screen.

  # VM variant: `nixos-rebuild build-vm --flake .#linux-laptop`
  # Builds a QEMU VM that shares the full host configuration.
  # Log in as example / test.
  virtualisation.vmVariant = {
    virtualisation = {
      memorySize = 4096;
      cores = 4;
      graphics = true;
    };

    # Test credentials (real config uses hashedPasswordFile)
    users.users.example = {
      password = lib.mkForce "test";
      hashedPasswordFile = lib.mkForce null;
    };

    # The LVM swap volume does not exist inside the VM.
    boot.resumeDevice = lib.mkForce "";
    swapDevices = lib.mkForce [];

    # Lanzaboote (Secure Boot) is not available in the VM.
    # Re-enable systemd-boot so the VM can boot normally.
    # mkOverride 10 wins over the host's mkForce (priority 50).
    boot.lanzaboote.enable = lib.mkOverride 10 false;
    boot.loader.systemd-boot.enable = lib.mkOverride 10 true;

    # Disko disk layout targets bare-metal NVMe/LUKS/LVM.
    # The qemu-vm module provides its own virtual disk and
    # filesystem mounts, so disable all disko devices.
    disko.devices = lib.mkForce {};

    # The host initrd loads dm-snapshot for LVM and amdgpu for early KMS.
    # Neither exists in the VM; strip them so the systemd-based initrd
    # does not stall waiting for nonexistent devices.
    boot.initrd.kernelModules = lib.mkForce [];
    hardware.amdgpu.initrd.enable = lib.mkForce false;
  };
}

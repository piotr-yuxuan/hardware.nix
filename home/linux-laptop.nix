# Home Manager linux-laptop-specific overrides (NixOS, Framework 16 AMD).
#
# Imported alongside home/base.nix for the example user on linux-laptop.
# `unstable` is available via extraSpecialArgs.
{
  pkgs,
  lib,
  config,
  unstable,
  ...
}: let
  monoFont = "IosevkaTerm Nerd Font Mono";
  monoFontSize = 11;

  # GWeather location helper (GNOME world clocks)
  inherit (lib.hm.gvariant) mkVariant mkTuple mkUint32;

  mkLoc = {
    name,
    metar,
    cityLat,
    cityLon,
    stationLat,
    stationLon,
  }:
    mkTuple [
      (mkUint32 2)
      (mkVariant (mkTuple [
        name
        metar
        true
        [(mkTuple [cityLat cityLon])]
        [(mkTuple [stationLat stationLon])]
      ]))
    ];

  worldClocks = map mkLoc (import ./linux-laptop/world-clocks.nix);

  # Build a MIME-type -> desktop-file mapping from a flat list of MIME types,
  # all handled by the same application.  Merge several calls with // to
  # assemble the full defaultApplications attrset.
  mimeGroup = desktop: types: lib.genAttrs types (_: [desktop]);
in {
  # linux-laptop-only packages
  home.packages =
    [
      # GUI apps
      unstable.emacs-pgtk
      unstable.libreoffice
      unstable.jetbrains.pycharm # macOS uses the native Homebrew cask
      # Firefox, VSCode, Signal, VLC, and Transmission are
      # sandboxed via Firejail at the system level (hosts/linux-laptop.nix).
      # Do not install them here or the unwrapped binaries would shadow
      # the sandboxed wrappers.
      unstable.maestral
      unstable.maestral-gui
      unstable.google-chrome
      unstable.ungoogled-chromium
      unstable.tuba

      # Two-factor authentication
      unstable.authenticator # GNOME Authenticator (TOTP/HOTP)

      # Android
      unstable.android-tools # adb, fastboot, mkbootimg
      unstable.scrcpy # display and control Android devices over USB or TCP/IP

      # Music
      unstable.picard # MusicBrainz tagger

      # Shell & terminal
      # ncurses provides `tic` for terminfo compilation. lowPrio lets
      # ghostty's bundled terminfo/g/ghostty entry win the buildEnv conflict.
      (lib.lowPrio unstable.ncurses)
      unstable.xterm # xterm-color terminfo entry

      # Build toolchain (native Emacs modules: jinx, gterm)
      unstable.gnumake
      unstable.libtool

      # Languages (personal)
      #unstable.jdk17

      # Profiling (JVM)
      # visualvm lives here rather than home/base.nix because on macOS it
      # is installed via the Homebrew cask (config/Brewfile); base.nix is
      # shared, so keeping it here avoids a duplicate Nix copy on macOS.
      # async-profiler and flamegraph stay cross-platform in base.nix.
      unstable.visualvm # JVM monitoring & profiling GUI

      # Misc
      unstable.bubblewrap # bwrap, unprivileged sandboxing for applications
      unstable.sqlite
      unstable.wl-clipboard # wl-copy / wl-paste for Wayland terminal Emacs
      unstable.difftastic # structural diffs (difftastic.el)
      unstable.editorconfig-core-c # .editorconfig support
      unstable.dust
      unstable.duf
      unstable.wget

      # OSX-KVM (macOS virtualisation via QEMU/KVM)
      unstable.dmg2img # convert BaseSystem.dmg to raw image
      unstable.p7zip # 7z extraction used by OSX-KVM tooling
      unstable.cdrtools # mkisofs/genisoimage for ISO creation
      unstable.tesseract # OCR engine for automated install helpers

      # Audio editing
      unstable.audacity # audio editor

      # LaTeX
      unstable.texliveFull # full TeX Live (XeLaTeX, LuaLaTeX, latexmk, …)

      # Music notation
      unstable.lilypond # music engraving
      unstable.frescobaldi # LilyPond GUI editor (score preview, Qt6)
      unstable.timidity # MIDI playback (LilyPond preview audio)
      # Python (Emacs tooling)
      unstable.python3Packages.pip
      unstable.python3Packages.jedi
      unstable.python3Packages.rope

      # GNOME Shell extensions
      unstable.gnomeExtensions.date-menu-formatter # custom panel clock format
      unstable.gnomeExtensions.emoji-copy # searchable emoji picker (Super+.)
      unstable.gnomeExtensions.grand-theft-focus # suppress "… is ready" and focus the window
      unstable.gnomeExtensions.appindicator # system tray for legacy status icons
      unstable.gnomeExtensions.night-theme-switcher # auto dark/light theme by schedule or sun
      unstable.gnomeExtensions.clipboard-history # persistent clipboard ring with search
      unstable.gnomeExtensions.auto-power-profile # auto power profile based on AC/battery
    ]
    ++ (import ../fonts.nix {inherit unstable;});

  fonts.fontconfig.enable = true;

  programs.git.settings = {
    user = {
      name = lib.mkForce "Example User";
      email = lib.mkForce "example@example.invalid";
      # signingKey = "<your-gpg-key-id>";
    };
    commit.gpgSign = true;
    tag.gpgSign = true;
  };

  # 26.05: programs.ssh.settings replaces matchBlocks (upstream directive names).
  programs.ssh.settings."github.com" = {
    HostName = "github.com";
    IdentityFile = "~/.ssh/id_ed25519";
  };

  # Fontconfig: map "monospace" to our Nerd Font for starship glyphs
  xdg.configFile."fontconfig/fonts.conf".source = ../config/fontconfig/fonts.conf;

  # `settings` is intentionally unset so the module does not generate
  # a config file; the shared config is written below via
  # xdg.configFile.
  programs.ghostty = {
    enable = true;
    package = unstable.ghostty;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  xdg.configFile."ghostty/config".text =
    (lib.fileContents ../config/ghostty/config)
    + "\nfont-size = ${toString monoFontSize}\n";

  # Macchina for welcome message
  xdg.configFile."macchina/macchina.toml".source = ../config/macchina/macchina.toml;
  xdg.configFile."macchina/themes/NixOS.toml".source = ../config/macchina/themes/NixOS.toml;
  xdg.configFile."macchina/nixos-ascii.txt".source = ../config/macchina/nixos-ascii.txt;

  # Gnome Console (and any GTK app querying "monospace") reads this
  # GSettings key, NOT fontconfig. Without it GNOME falls back to
  # Adwaita Mono which has no Nerd Font symbols.
  dconf.settings."org/gnome/desktop/interface".monospace-font-name = "${monoFont} ${toString monoFontSize}";

  dconf.settings."org/gnome/desktop/background" = {
    picture-uri = "file://${../img/wallpaper.jpg}";
    picture-uri-dark = "file://${../img/wallpaper.jpg}";
    picture-options = "zoom";
  };

  # The stock GNOME clock hardcodes abbreviated weekdays. Date Menu
  # Formatter overrides it with a Luxon format string.
  # Ordinal suffixes ("19th") are not available in Luxon.
  # Result: "Thursday, 19 March  15:53".
  dconf.settings."org/gnome/shell" = {
    enabled-extensions = [
      "date-menu-formatter@marcinjakubowski.github.com"
      "emoji-copy@felipeftn"
      "grand-theft-focus@zalckos.github.com"
      "appindicatorsupport@rgcjonas.gmail.com"
      "nightthemeswitcher@romainvigier.fr"
      "clipboard-history@alexsaveau.dev"
      "auto-power-profile@dmy3k.github.io"
    ];
    favorite-apps = ["emacsclient.desktop"];
    always-show-log-out = true;
  };

  dconf.settings."org/gnome/shell/extensions/date-menu-formatter" = {
    pattern = "EEEE, d MMMM  HH:mm:ss";
    update-level = "3";
  };

  dconf.settings."org/gnome/desktop/interface" = {
    clock-show-weekday = true;
    clock-show-date = true;
    clock-format = "24h";
  };

  # Show ISO week numbers in the dropdown calendar.
  dconf.settings."org/gnome/desktop/calendar".show-weekdate = true;

  # GNOME: world clocks (panel clock dropdown)
  dconf.settings."org/gnome/shell/world-clocks".locations =
    map mkVariant worldClocks;

  # GNOME: automatic timezone based on geolocation
  dconf.settings."org/gnome/desktop/datetime".automatic-timezone = true;

  # Master switch for GNOME location services (Privacy > Location).
  # Without this geoclue refuses all requests from UID 1000 regardless
  # of the per-app configuration.
  dconf.settings."org/gnome/system/location".enabled = true;

  # GNOME Shell geoclue agent provides location data for the datetime
  # plugin above and for the weather panel.  The polkit rule in
  # hosts/linux-laptop.nix allows the active session to call SetTimezone
  # without a password prompt.
  dconf.settings."org/gnome/shell/weather".automatic-location = true;

  # GNOME: keyboard preferences
  dconf.settings."org/gnome/desktop/peripherals/keyboard".numlock-state = true;
  dconf.settings."org/gnome/desktop/input-sources" = {
    sources = [(lib.hm.gvariant.mkTuple ["xkb" "us"])];
    xkb-options = ["terminate:ctrl_alt_bksp"];
  };

  # GNOME: touchpad preferences
  dconf.settings."org/gnome/desktop/peripherals/touchpad" = {
    speed = 1.0;
    two-finger-scrolling-enabled = true;
  };

  # GNOME: System Monitor preferences
  dconf.settings."org/gnome/gnome-system-monitor" = {
    cpu-stacked-area-chart = true;
    graph-data-points = 600;
    graph-update-interval = 499;
    logarithmic-scale = true;
    network-in-bits = false;
    resources-memory-in-iec = true;
    show-dependencies = false;
    show-whose-processes = "user";
  };

  # GNOME: screenshots

  # Direct the legacy gnome-screenshot tool to the canonical directory.
  # GNOME Shell 42+ saves instead to ~/Pictures/Screenshots (capital S);
  # a symlink from that path to the lowercase directory is created by
  # scripts/home-layout-linux-laptop.sh so both land in the same place.
  dconf.settings."org/gnome/gnome-screenshot" = {
    auto-save-directory = "file://${config.home.homeDirectory}/Pictures/screenshots";
  };

  # Silence all desktop event sounds. Corresponds to GNOME Settings >
  # Sound > "Alert and event sounds".
  dconf.settings."org/gnome/desktop/sound" = {
    "event-sounds" = false;
  };

  # Maestral Dropbox daemon (background sync)
  systemd.user.services.maestral = {
    Unit.Description = "Maestral Dropbox daemon";
    Service = {
      ExecStart = "${unstable.maestral}/bin/maestral start --foreground";
      ExecStop = "${unstable.maestral}/bin/maestral stop";
      Restart = "on-failure";
      Nice = "10";
      # Sandboxing
      # "full" (not "strict") so /home stays writable for Dropbox sync.
      ProtectSystem = "full";
      PrivateTmp = true;
      NoNewPrivileges = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      SystemCallArchitectures = "native";
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  # Maestral Qt tray icon
  systemd.user.services.maestral-gui = {
    Unit = {
      Description = "Maestral Qt tray icon";
      After = ["maestral.service" "graphical-session.target"];
    };
    Service = {
      ExecStart = "${unstable.maestral-gui}/bin/maestral_qt";
      Restart = "on-failure";
      # Provide the GTK3 GSettings schemas that maestral_qt requires
      Environment = [
        "XDG_DATA_DIRS=${lib.concatStringsSep ":" [
          "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
          "/run/current-system/sw/share"
          "%h/.local/share"
        ]}"
      ];
      # Sandboxing (lighter than the daemon: needs DBus + display)
      NoNewPrivileges = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      SystemCallArchitectures = "native";
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  # Suppress the XDG autostart entry that maestral creates on its own;
  # the systemd services above handle startup instead.
  xdg.configFile."autostart/maestral-maestral.desktop".text = ''
    [Desktop Entry]
    Hidden=true
    Type=Application
    Name=Maestral
  '';

  # LanguageTool HTTP server (grammar checker for LibreOffice)
  systemd.user.services.languagetool = {
    Unit.Description = "LanguageTool grammar checker (HTTP API)";
    Service = {
      ExecStart = "${unstable.languagetool}/bin/languagetool-http-server --port 47193";
      Restart = "on-failure";
      NoNewPrivileges = true;
      ProtectSystem = "full";
      PrivateTmp = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      SystemCallArchitectures = "native";
    };
    Install.WantedBy = ["default.target"];
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications =
      # Audio -> VLC (sandboxed via firejail; desktop file stays vlc.desktop)
      mimeGroup "vlc.desktop" [
        "audio/mpeg"
        "audio/x-wav"
        "audio/flac"
        "audio/x-flac"
        "audio/ogg"
        "audio/vorbis"
        "audio/x-vorbis+ogg"
        "audio/mp4"
        "audio/x-m4a"
        "audio/aac"
        "audio/x-aac"
        "audio/opus"
        "audio/x-opus+ogg"
        "audio/mp2"
        "audio/musepack"
        "audio/x-musepack"
        "audio/wavpack"
        "audio/x-wavpack"
        "application/ogg"
      ]
      # Programming and prose -> Emacs
      // mimeGroup "emacsclient.desktop" [
        "text/plain"
        "text/x-csrc"
        "text/x-c++src"
        "text/x-chdr"
        "text/x-c++hdr"
        "text/x-python"
        "text/x-java"
        "text/x-scala"
        "text/x-rust"
        "text/x-go"
        "text/x-sh"
        "text/x-shellscript"
        "application/x-shellscript"
        "text/x-nix"
        "text/javascript"
        "application/javascript"
        "text/css"
        "application/json"
        "text/xml"
        "application/xml"
        "text/x-yaml"
        "application/x-yaml"
        "text/x-toml"
        "text/markdown"
        "text/x-markdown"
        "text/x-org"
        "text/x-tex"
        "application/x-tex"
        "text/x-lisp"
        "text/x-common-lisp"
        "text/x-clojure"
        "text/x-haskell"
        "text/x-lua"
        "text/x-ruby"
        "text/x-perl"
        "text/x-php"
        "text/x-sql"
        "text/x-diff"
        "text/x-patch"
        "text/x-makefile"
      ]
      # Browser -> Firefox Developer Edition
      // mimeGroup "firefox-devedition.desktop" [
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "x-scheme-handler/ftp"
        "text/html"
        "application/xhtml+xml"
      ]
      # Office -> LibreOffice (Writer)
      // mimeGroup "libreoffice-writer.desktop" [
        "application/msword"
        "application/vnd.ms-word"
        "application/vnd.ms-word.document.macroEnabled.12"
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        "application/vnd.openxmlformats-officedocument.wordprocessingml.template"
        "application/vnd.oasis.opendocument.text"
        "application/vnd.oasis.opendocument.text-template"
        "application/vnd.oasis.opendocument.text-master"
        "application/rtf"
        "text/rtf"
      ]
      # Office -> LibreOffice (Calc)
      // mimeGroup "libreoffice-calc.desktop" [
        "application/vnd.ms-excel"
        "application/vnd.ms-excel.sheet.macroEnabled.12"
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        "application/vnd.openxmlformats-officedocument.spreadsheetml.template"
        "application/vnd.oasis.opendocument.spreadsheet"
        "application/vnd.oasis.opendocument.spreadsheet-template"
        "text/csv"
      ]
      # Office -> LibreOffice (Impress)
      // mimeGroup "libreoffice-impress.desktop" [
        "application/vnd.ms-powerpoint"
        "application/vnd.ms-powerpoint.presentation.macroEnabled.12"
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        "application/vnd.openxmlformats-officedocument.presentationml.template"
        "application/vnd.openxmlformats-officedocument.presentationml.slideshow"
        "application/vnd.oasis.opendocument.presentation"
        "application/vnd.oasis.opendocument.presentation-template"
      ]
      # Office -> LibreOffice (Draw)
      // mimeGroup "libreoffice-draw.desktop" [
        "application/vnd.oasis.opendocument.graphics"
        "application/vnd.oasis.opendocument.graphics-template"
      ]
      # Office -> LibreOffice (Math)
      // mimeGroup "libreoffice-math.desktop" [
        "application/vnd.oasis.opendocument.formula"
      ];
  };

  # Clear .hushlogin at login so the shell greeting runs once per sessionvariables
  systemd.user.services.clear-hushlogin = {
    Unit.Description = "Remove .hushlogin so the next interactive shell shows the greeting";
    Service = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/rm -f %h/.hushlogin";
    };
    Install.WantedBy = ["default.target"];
  };

  #  XDG user directories

  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    # Pin the stateVersion-gated default (flips true->false at 26.05) so the
    # XDG_*_DIR session variables keep being exported regardless of
    # stateVersion; silences the 26.05 deprecation trace.
    setSessionVariables = true;
  };

  #  GNOME: Nautilus sidebar bookmarks

  xdg.configFile."gtk-3.0/bookmarks".text = let
    h = config.home.homeDirectory;
  in ''
    file://${h} Home
    file://${h}/src/github.com/example example
    file://${h}/img img
    file://${h}/mov mov
    file://${h}/net net
    file://${h}/pvt pvt
    file://${h}/snd snd
    file://${h}/src src
  '';

  #  Hide default XDG folders from Nautilus
  #
  # GLib-based file managers (Nautilus, Thunar) read ~/.hidden and omit
  # every listed name from the directory view.  The real folders still
  # exist and any application can use them; they simply don't appear
  # when browsing $HOME.

  home.file.".hidden".text = lib.fileContents ../config/hidden;

  #  Linux-specific HOME layout additions (mov -> Videos, Dropbox redirects)

  home.activation.homeLayoutlinux-laptop = lib.hm.dag.entryAfter ["homeLayout"] ''
    ${lib.fileContents ../scripts/home-layout-linux-laptop.sh}
  '';

  #  Email: personal account (mbsync + mu)

  accounts.email = {
    maildirBasePath = "${config.home.homeDirectory}/Mail";
    accounts.personal = {
      address = "example@example.invalid";
      realName = "Example User";
      userName = "example@example.invalid";
      passwordCommand = "gpg -q --for-your-eyes-only --no-tty -d ~/.authinfo.gpg | awk '/machine imap.example.invalid.*port 993/{print $NF}'";
      primary = true;
      imap = {
        host = "imap.example.invalid";
        port = 993;
        tls.enable = true;
        tls.certificatesFile = "/etc/ssl/certs/ca-certificates.crt";
      };
      maildir.path = "personal";
      mbsync = {
        enable = true;
        subFolders = "Verbatim";
        create = "maildir";
        expunge = "maildir";
        patterns = ["*"];
      };
      mu.enable = true;
    };
  };

  programs.mbsync.enable = true;

  programs.thunderbird = {
    enable = true;
    profiles."default" = {
      isDefault = true;
      # The attribute key is used as the profile directory name, so this
      # maps to the existing ~/.thunderbird/default directory.
      settings = {};
    };
  };
}

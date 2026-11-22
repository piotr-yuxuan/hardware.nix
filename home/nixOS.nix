# Home Manager settings of nixOS only; home/base.nix holds the shared ones.
{
  pkgs,
  lib,
  config,
  unstable,
  inputs,
  ...
}: let
  monoFontSize = 11;

  # Maps each MIME type of a list to one desktop file.
  mimeGroup = desktop: types: lib.genAttrs types (_: [desktop]);
in {
  # Identities, mail, bookmarks, keyboard layout and world clocks.
  imports = lib.optional (builtins.pathExists ./nixOS/personal.nix) ./nixOS/personal.nix;

  home.packages =
    [
      # GUI apps
      unstable.papirus-icon-theme
      unstable.emacs-pgtk
      unstable.libreoffice
      inputs.claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop
      # The desktop keeps its own CLI off PATH; the Mac takes the cask.
      unstable.claude-code
      #inputs.hylki.packages.${pkgs.stdenv.hostPlatform.system}.default # Fails to link against sqlite3 at 1.47.1.
      #inputs.penguin-mail.packages.${pkgs.stdenv.hostPlatform.system}.default # Doesn't compile right now, might enable it again on a tag.
      #inputs.inlark.packages.${pkgs.stdenv.hostPlatform.system}.default
      # Firefox, VS Code, Signal, VLC and Transmission come sandboxed from
      # hosts/nixOS.nix: a copy here would shadow the wrappers.
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

      # Profiling (JVM); the Mac takes VisualVM's Homebrew cask.
      unstable.visualvm # JVM monitoring & profiling GUI

      # Here while recode fails on aarch64-darwin (nixpkgs#568679) and the
      # Mac takes Homebrew's; back to home/base.nix once Hydra builds it.
      unstable.fortune
      unstable.enca

      # Graphics; Linux only in nixpkgs, so the Mac takes the Homebrew cask.
      unstable.gimp

      # IDE; the Mac takes the cask, so that no Nix .app needs App
      # Management permission at each switch.
      unstable.jetbrains.pycharm

      # Misc
      unstable.bubblewrap # bwrap, unprivileged sandboxing for applications
      unstable.sqlite
      unstable.wl-clipboard # wl-copy / wl-paste for Wayland terminal Emacs
      unstable.editorconfig-core-c # .editorconfig support
      unstable.dust
      unstable.duf
      unstable.wget
      unstable.openssl

      # OSX-KVM (macOS virtualisation via QEMU/KVM)
      unstable.dmg2img # convert BaseSystem.dmg to raw image
      unstable.p7zip # 7z extraction used by OSX-KVM tooling
      unstable.cdrtools # mkisofs/genisoimage for ISO creation
      unstable.tesseract # OCR engine for automated install helpers

      pkgs.audacity # stable on purpose: AGENTS.md, "Package channels"

      # Stores the mail password in the login keyring
      unstable.libsecret # secret-tool

      # LaTeX
      unstable.texliveFull # full TeX Live (XeLaTeX, LuaLaTeX, latexmk, …)

      # Music notation
      unstable.lilypond # music engraving
      unstable.frescobaldi # LilyPond GUI editor (score preview, Qt6)
      unstable.timidity # MIDI playback (LilyPond preview audio)

      # Python (Emacs tooling)
      unstable.python3Packages.pip

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

  # "monospace" maps to the Nerd Font, for the prompt's glyphs.
  xdg.configFile."fontconfig/fonts.conf".source = ../config/fontconfig/fonts.conf;

  xdg.configFile."ghostty/config".text =
    (lib.fileContents ../config/ghostty/config)
    + "\nfont-size = ${toString monoFontSize}\n";

  # Macchina for welcome message, one link per file of config/macchina
  xdg.configFile.macchina = {
    source = ../config/macchina;
    recursive = true;
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      # The GTK theme an earlier service used to set.
      gtk-theme = "Adwaita";
      icon-theme = "Papirus";
      # GNOME's "monospace" comes from here, not from fontconfig.
      monospace-font-name = "IosevkaTerm Nerd Font Mono ${toString monoFontSize}";
      clock-show-weekday = true;
      clock-show-date = true;
      clock-format = "24h";
    };

    "org/gnome/desktop/background" = {
      picture-uri = "file://${../img/wallpaper.jpg}";
      picture-uri-dark = "file://${../img/wallpaper.jpg}";
      picture-options = "zoom";
    };

    # Date Menu Formatter gives the clock full weekdays, with a Luxon
    # pattern: "Thursday, 19 March  15:53".
    "org/gnome/shell" = {
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

    "org/gnome/shell/extensions/date-menu-formatter" = {
      pattern = "EEEE, d MMMM  HH:mm:ss";
      update-level = "3";
    };

    # Show ISO week numbers in the dropdown calendar.
    "org/gnome/desktop/calendar".show-weekdate = true;

    "org/gnome/desktop/datetime".automatic-timezone = true;

    # Location services on, without which geoclue refuses every request.
    "org/gnome/system/location".enabled = true;

    "org/gnome/shell/weather".automatic-location = true;

    "org/gnome/desktop/peripherals/keyboard".numlock-state = true;

    "org/gnome/desktop/peripherals/touchpad" = {
      speed = 1.0;
      two-finger-scrolling-enabled = true;
    };

    "org/gnome/gnome-system-monitor" = {
      cpu-stacked-area-chart = true;
      graph-data-points = 600;
      graph-update-interval = 499;
      logarithmic-scale = true;
      network-in-bits = false;
      resources-memory-in-iec = true;
      show-dependencies = false;
      show-whose-processes = "user";
    };

    # GNOME Shell saves to ~/Pictures/Screenshots, which
    # scripts/home-layout-nixOS.sh links to this directory.
    "org/gnome/gnome-screenshot".auto-save-directory = "file://${config.home.homeDirectory}/Pictures/screenshots";

    # No alert or event sounds.
    "org/gnome/desktop/sound".event-sounds = false;
  };

  # Maestral's ignore list. Maestral reads it only when sync starts, so
  # a switch that changes it restarts the daemon below.
  home.file."Dropbox (Maestral)/.mignore".source = ../config/maestral/mignore;

  # Maestral Dropbox daemon (background sync). Home Manager, not NixOS
  # systemd.user.services: system-wide user units also start in the GDM
  # greeter, and crash there.
  systemd.user.services.maestral = {
    Unit = {
      Description = "Maestral Dropbox daemon";
      X-Restart-Triggers = ["${config.home.file."Dropbox (Maestral)/.mignore".source}"];
    };
    Service = {
      ExecStart = "${unstable.maestral}/bin/maestral start --foreground";
      ExecStop = "${unstable.maestral}/bin/maestral stop";
      Restart = "on-failure";
      Nice = "10";
      # Sandboxing; "full", not "strict", so that /home stays writable.
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
      # The icon does not follow the daemon through a restart: it quits,
      # or stays with a dead connection. Restart it with the daemon, as a
      # switch that changes .mignore does.
      PartOf = ["maestral.service"];
    };
    Service = {
      ExecStart = "${unstable.maestral-gui}/bin/maestral_qt";
      Restart = "on-failure";
      # Provide the GTK3 GSettings schemas that maestral_qt requires
      Environment = [
        "XDG_DATA_DIRS=${lib.concatStringsSep ":" [
          "${unstable.gtk3}/share/gsettings-schemas/${unstable.gtk3.name}"
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

  # Clear .hushlogin at login so the shell greeting runs once per session
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
    package = unstable.xdg-user-dirs;
    createDirectories = true;
    # Keep exporting XDG_*_DIR, whatever stateVersion says.
    setSessionVariables = true;
  };

  # On by Home Manager's default on Linux; named here for its packages.
  xdg.mime = {
    sharedMimeInfoPackage = unstable.shared-mime-info;
    desktopFileUtilsPackage = unstable.desktop-file-utils;
  };

  # File managers hide the default folders that ~/.hidden lists.

  home.file.".hidden".text = lib.fileContents ../config/hidden;

  #  Linux-specific HOME layout additions (mov -> Videos, Dropbox redirects)

  home.activation.homeLayoutnixOS =
    lib.hm.dag.entryAfter ["homeLayout"]
    (lib.fileContents ../scripts/home-layout-nixOS.sh);
}

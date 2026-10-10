# nix-darwin system configuration for macOS hosts.
#
# Manages Nix, shells, security hardening, and macOS default preferences.
#
# Apply: sudo darwin-rebuild switch --flake .#macOS
{
  config,
  lib,
  unstable,
  ...
}: {
  # Nix daemon
  nix.optimise.automatic = true;
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      # auto-optimise-store removed: known to corrupt the store.
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
      # Scoped to the machine owner so future accounts cannot push
      # arbitrary store paths bypassing signature verification.
      trusted-users = ["root" config.system.primaryUser];
    };
    gc = {
      automatic = false; # replaced by the nh-clean launchd agent below
    };
  };

  # Linux builder
  # A lightweight NixOS VM (aarch64-linux) that lets this Apple Silicon Mac
  # build and run Linux derivations, including disposable NixOS test VMs.
  # nix-darwin registers it automatically as an aarch64-linux build machine;
  # it is only consulted when a Linux build is requested, so it stays inert
  # for normal darwin work. The VM image is fetched prebuilt from
  # cache.nixos.org, so no local Linux build is needed to bootstrap it.
  # memorySize/cores are runtime QEMU flags and do NOT change the cached
  # image's store path (diskSize would, so it is left at the default).
  # Revert by deleting this block and running `sudo darwin-rebuild switch`.
  nix.linux-builder = {
    enable = true;
    maxJobs = 4;
    config = {
      virtualisation = {
        cores = 6;
        darwin-builder.memorySize = 8192; # MB; headroom for nested test VMs
      };
    };
  };

  # nh: weekly garbage collection via a launchd user agent.
  # nix-darwin has no programs.nh module, so the periodic job is wired
  # manually.  Runs every Sunday at 03:00, keeping the last 5 generations
  # and anything newer than 7 days (mirrors the nixOS policy exactly).
  # nh clean also removes gcroots, unlike plain nix-collect-garbage.
  launchd.user.agents.nh-clean = {
    serviceConfig = {
      Label = "org.nixos.nh-clean";
      ProgramArguments = [
        "${unstable.nh}/bin/nh"
        "clean"
        "all"
        "--keep"
        "5"
        "--keep-since"
        "7d"
      ];
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 3;
          Minute = 0;
        }
      ];
      RunAtLoad = false;
      StandardOutPath = "/tmp/nh-clean.log";
      StandardErrorPath = "/tmp/nh-clean.log";
    };
  };

  # Shell
  # Register Nix-managed zsh in /etc/shells so it can be used as a
  # login shell.  You may need to run
  # `chsh -s /run/current-system/sw/bin/zsh` once manually.
  programs.zsh.enable = true;

  # Keyboard & input
  system.defaults.NSGlobalDomain = {
    # Key repeat: fast repeat, short delay before repeat starts.
    KeyRepeat = 2;
    InitialKeyRepeat = 15;

    # Always show scroll bars.
    AppleShowScrollBars = "Always";

    # Use F1–F12 as standard function keys (media via fn+F*).
    "com.apple.keyboard.fnState" = true;

    # Prefer key repeat over press-and-hold character picker.
    ApplePressAndHoldEnabled = false;

    # Disable all automatic text substitution.
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticDashSubstitutionEnabled = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
    NSAutomaticQuoteSubstitutionEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;

    # Expand save and print dialogs by default.
    NSNavPanelExpandedStateForSaveMode = true;
    NSNavPanelExpandedStateForSaveMode2 = true;
    PMPrintingExpandedStateForPrint = true;
    PMPrintingExpandedStateForPrint2 = true;

    # Save to disk, not iCloud, by default.
    NSDocumentSaveNewDocumentsToCloud = false;

    # Metric units.
    AppleMeasurementUnits = "Centimeters";
    AppleMetricUnits = 1;
    AppleTemperatureUnit = "Celsius";

    # Medium sidebar icon size (1=small, 2=medium, 3=large).
    NSTableViewDefaultSizeMode = 2;

    # Enable subpixel font rendering on non-Apple displays.
    AppleFontSmoothing = 2;

    # Automatically switch between Light and Dark appearance at
    # sunrise/sunset. Requires Location Services enabled in System
    # Settings > Privacy & Security > Location Services.
    AppleInterfaceStyleSwitchesAutomatically = true;
  };

  # Trackpad
  system.defaults.trackpad = {
    # Tap to click.
    Clicking = true;

    # Three-finger drag to select text or move windows by swiping
    # with three fingers (System Settings → Accessibility → Pointer
    # Control → Trackpad Options → Dragging style).
    TrackpadThreeFingerDrag = true;
  };

  # Dock
  system.defaults.dock = {
    autohide = true;
    mru-spaces = false; # don't rearrange Spaces by recent use
    show-recents = false;

    # Magnification on hover.
    magnification = true;
    largesize = 128;
    tilesize = 48; # base icon size

    # Minimise into the app icon, not a separate tile.
    minimize-to-application = true;
    mineffect = "scale"; # faster than "genie"

    # Group windows by app in Mission Control (Exposé).
    expose-group-apps = true;

    # Pin only Emacs; remove every other persistent app.
    persistent-apps = ["/Applications/Emacs.app"];

    # Disable all hot corners.
    wvous-tl-corner = 1;
    wvous-tr-corner = 1;
    wvous-bl-corner = 1;
    wvous-br-corner = 1;
  };

  # Automatic timezone
  # Let macOS determine the timezone from the current network location.
  # Requires Location Services in System Settings → Privacy & Security.
  # time.timeZone is left unset (null) so macOS manages it dynamically.

  # Menu bar clock
  system.defaults.menuExtraClock.IsAnalog = true;

  # Battery
  system.defaults.controlcenter.BatteryShowPercentage = true;

  # Screenshots
  system.defaults.screencapture = {
    location = "~/img/screenshots";
    type = "png";
    disable-shadow = true; # cleaner window captures
  };

  # Disable "Are you sure you want to open this application?" quarantine dialog.
  system.defaults.LaunchServices.LSQuarantine = false;

  # Reduce entrypoints for Spaces.
  system.defaults.spaces.spans-displays = false;

  # Login window
  system.defaults.loginwindow = {
    GuestEnabled = false;
    DisableConsoleAccess = true;
    # Show login/password fields (not user avatars).
    SHOWFULLNAME = true;
  };

  # Finder
  system.defaults.finder = {
    AppleShowAllExtensions = true;
    AppleShowAllFiles = false; # Hide hidden files
    FXEnableExtensionChangeWarning = false;
    FXDefaultSearchScope = "SCcf"; # search current folder by default
    FXPreferredViewStyle = "Nlsv"; # default to list view
    ShowPathbar = true;
    ShowStatusBar = true;
    _FXSortFoldersFirst = true; # folders on top in all views
  };

  # Custom preferences (no first-class nix-darwin option)
  system.defaults.CustomUserPreferences = {
    # Siri / AI
    "com.apple.Siri" = {
      StatusMenuVisible = false;
      UserHasDeclinedEnable = true;
    };
    "com.apple.assistant.support" = {
      "Assistant Enabled" = false;
    };

    # Mission Control / gestures
    "com.apple.dock" = {
      # Swipe down with four fingers to show only the current app's windows.
      showAppExposeGestureEnabled = true;
    };

    # Finder sidebar
    "com.apple.finder" = {
      ShowRecentTags = false;
      SidebarShowingSignedIntoiCloud = false;
      SidebarShowingiCloudDesktop = false;
      FXArrangeGroupViewBy = "Name";
    };

    # Hide Bonjour computers in Finder sidebar
    "com.apple.NetworkBrowser" = {
      BrowseAllInterfaces = false;
    };

    # Prevent .DS_Store on network and USB volumes
    "com.apple.desktopservices" = {
      DSDontWriteNetworkStores = true;
      DSDontWriteUSBStores = true;
    };

    # Show desktop widgets (but not in Stage Manager). Disable Sequoia
    # window tiling/snapping (conflicts with Rectangle).
    "com.apple.WindowManager" = {
      EnableStandardClickToShowDesktop = false;
      StandardHideWidgets = false;
      StageManagerHideWidgets = true;
      EnableWindowSnapping = false;
      EnableTiledWindowMargins = false;
    };

    # Rectangle: hide menu bar icon (icon is unnecessary; use keyboard shortcuts).
    "com.knollsoft.Rectangle" = {
      hideStatusItem = true;
    };

    # MiddleClick: synthesise a middle-click from a four-finger trackpad
    # tap, so e.g. Firefox closes a tab when tapped. Four fingers, not
    # three, because three-finger drag is enabled above
    # (system.defaults.trackpad.TrackpadThreeFingerDrag) and would
    # otherwise conflict.
    "art.ginzburg.MiddleClick" = {
      fingers = 4;
    };

    # Disable Tip notifications.
    "com.apple.tipsd" = {
      allowTips = false;
    };

    # Suppress Spaces / Mission Control keyboard & trackpad triggers.
    "com.apple.symbolichotkeys" = {
      # 32/34 = Mission Control (Ctrl-Up / Ctrl-Down)
      # 60/61 = Input sources (Ctrl-Space and Ctrl-Opt-Space by default)
      # 75/76 = Move left/right a Space (Ctrl-Left / Ctrl-Right)
      # 79/80 = Switch to Desktop 1 / 2
      AppleSymbolicHotKeys = {
        "32" = {enabled = false;};
        "34" = {enabled = false;};
        "60" = {enabled = false;};
        "61" = {enabled = false;};
        "75" = {enabled = false;};
        "76" = {enabled = false;};
        "79" = {enabled = false;};
        "80" = {enabled = false;};
        "81" = {enabled = false;};
        "82" = {enabled = false;};
      };
    };

    # AirDrop: contacts only.
    # Options: 0 = Off, 1 = Contacts Only, 2 = Everyone.
    "com.apple.sharingd" = {
      DiscoverableMode = "Contacts Only";
    };

    # Disable Bluetooth sharing.
    "com.apple.Bluetooth" = {
      PrefKeyServicesEnabled = false;
    };

    # Disable remote Apple events.
    "com.apple.AEServer" = {
      AppleEventEnabled = false;
    };

    # Require password immediately after screensaver / sleep.
    # Auto-lock screensaver after 15 minutes of idle.
    "com.apple.screensaver" = {
      askForPassword = 1;
      askForPasswordDelay = 0;
      idleTime = 900;
    };

    # Disable UI sound effects. Corresponds to System Settings > Sound
    # > "Play sound effects for user interface actions".
    "com.apple.systemsound" = {
      "com.apple.sound.uiaudio.enabled" = 0;
    };

    # Apple Terminal visual style (subset that can be expressed as plain plist values;
    # font and colour settings require NSArchived NSFont/NSColor objects and must be
    # configured interactively inside Terminal.app preferences).
    "com.apple.Terminal" = {
      # Use "Basic" as the startup and default profile so these settings apply.
      "Default Window Settings" = "Basic";
      "Startup Window Settings" = "Basic";
      "Window Settings" = {
        Basic = {
          # Initial window geometry.
          columnCount = 80;
          rowCount = 25;
          # No blinking cursor.
          CursorType = 0;
          BlinkCursor = false;
          # Enable font anti-aliasing.
          FontAntialias = true;
        };
      };
    };
  };

  # Automatic timezone (system-level preference)
  # The toggle lives in /Library/Preferences (needs root). The
  # activation script runs as root during darwin-rebuild switch.
  system.activationScripts.postActivation.text =
    lib.fileContents ../scripts/darwin-post-activation.sh;

  # Security
  security.pam.services.sudo_local.touchIdAuth = true;

  # Application Layer Firewall (ALF)
  networking.applicationFirewall = {
    enable = true;
    enableStealthMode = true; # drop unsolicited ICMP
    allowSignedApp = false;
    # Block all inbound to non-essential apps. Strongest ALF posture, chosen
    # because prod data dumps live on this machine; also shields LAN-exposed
    # app listeners. Set false if it blocks a legitimate inbound service.
    blockAllIncoming = true;
  };

  # Hostname
  # Do NOT set networking.hostName or networking.computerName.

  # Users
  # The primary user is the `user` argument of lib.mkDarwinHost
  # (flake.nix), given by the Mac's own flake.

  # Fonts
  # nix-darwin copies these into /Library/Fonts/Nix Fonts/ so that
  # macOS Core Text (and every native app) can discover them.
  fonts.packages = import ../fonts.nix {inherit unstable;};

  # Used by nix-darwin as a safety check. DO NOT change.
  system.stateVersion = 6; # !!! Have you read the comment above?
}

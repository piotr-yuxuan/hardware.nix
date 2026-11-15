# nix-darwin settings of the Mac: Nix, security and macOS preferences.
# Applied from the Mac's own flake: sudo darwin-rebuild switch --flake .#macOS
{unstable, ...}: {
  # Nix daemon
  nix.optimise.automatic = true;
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      # auto-optimise-store removed: known to corrupt the store.
      # trusted-users keeps nix-darwin's ["root"]: a trusted user is as
      # good as root, and the daily account has no sudo on purpose.
    };
  };

  # A small aarch64-linux NixOS VM, fetched prebuilt, that builds Linux
  # derivations, NixOS tests included, only when one is asked for. Cores
  # and memory leave the cached image as it is; a disk size would not.
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

  # Weekly garbage collection with nixOS's retention, as root: the old
  # system generations are root's, and the daily account has no sudo.
  # nix-darwin has no programs.nh module.
  launchd.daemons.nh-clean = {
    # nh calls nix-store from PATH. Strings rather than config.nix.package,
    # which IT-managed Nix (nix.enable = false) cannot evaluate.
    path = [
      "/run/current-system/sw/bin"
      "/nix/var/nix/profiles/default/bin"
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
    ];
    serviceConfig = {
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
      # Root writes the log, so not under the world-writable /tmp.
      StandardOutPath = "/var/log/nh-clean.log";
      StandardErrorPath = "/var/log/nh-clean.log";
    };
  };

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

    # Light or dark appearance by sunrise and sunset (Location Services).
    AppleInterfaceStyleSwitchesAutomatically = true;
  };

  # Trackpad
  system.defaults.trackpad = {
    # Tap to click.
    Clicking = true;

    # Drag with three fingers (Accessibility, Pointer Control).
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

  # time.timeZone stays unset: macOS follows the location.

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

    # MiddleClick: a four-finger tap is a middle click; three fingers drag.
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

    # No sound effects for interface actions.
    "com.apple.systemsound" = {
      "com.apple.sound.uiaudio.enabled" = 0;
    };

    # Terminal.app's Basic profile; fonts and colours are archived objects,
    # set in Terminal's own preferences.
    "com.apple.Terminal" = {
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

  # The login window shows the input menu, so the layout follows the last
  # user. Where an MDM profile sets it, override it with lib.mkForce null.
  system.defaults.CustomSystemPreferences."/Library/Preferences/com.apple.loginwindow".ShowInputMenu = true;

  # Security
  security.pam.services.sudo_local.touchIdAuth = true;

  # Application Layer Firewall (ALF)
  networking.applicationFirewall = {
    enable = true;
    enableStealthMode = true; # drop unsolicited ICMP
    allowSignedApp = false;
    # Strictest setting, because production data dumps live on this Mac.
    blockAllIncoming = true;
  };

  # Do NOT set networking.hostName or networking.computerName. The
  # primary user comes from lib.mkDarwinHost's `user`, in flake.nix.

  # Copied to /Library/Fonts/Nix Fonts, where every macOS app finds them.
  fonts.packages = import ../fonts.nix {inherit unstable;};

  # Used by nix-darwin as a safety check. DO NOT change.
  system.stateVersion = 6; # !!! Have you read the comment above?
}

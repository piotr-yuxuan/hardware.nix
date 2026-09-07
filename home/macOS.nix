# Home Manager macOS overrides (nix-darwin).
#
# Imported alongside home/base.nix for the macOS user.
# `unstable` is available via extraSpecialArgs.
{
  lib,
  unstable,
  ...
}: let
  # Substitute at evaluation time so Linux CI can evaluate the Darwin output
  # without first building a Darwin derivation just to read its script.
  brewBundleActivation = builtins.replaceStrings
    ["@BREWFILE@" "@BREW_BUNDLE_SCRIPT@"]
    [(toString ../config/Brewfile) (toString ../scripts/brew-bundle-activation.sh)]
    (builtins.readFile ../scripts/hm-activation/brew-bundle.sh);

  defaultAppsActivation = builtins.replaceStrings
    ["@DUTI_BIN@" "@DEFAULT_APPS_SCRIPT@"]
    ["${unstable.duti}/bin/duti" (toString ../scripts/set-macos-defaults.sh)]
    (builtins.readFile ../scripts/hm-activation/default-apps.sh);
in {
  #  macOS only packages

  home.packages = [
    # Languages & runtimes (macOS specific)
    unstable.luarocks
    unstable.pipenv
    unstable.poetry

    # Language servers (macOS specific)
    # texlab moved to home/base.nix (cross-platform)

    # VCS / GitOps
    unstable.glab
    unstable.gitlab-runner

    # Text / docs
    unstable.gnugrep
    unstable.gnused

    # Default-app management (sets UTI/MIME handlers via LaunchServices)
    unstable.duti
  ];

  #  Git identity (fill in before first use)

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
    AddKeysToAgent = "yes";
    UseKeychain = "yes";
  };

  #  macOS environment

  home.sessionVariables = {
    # Homebrew security hardening.
    HOMEBREW_CASK_OPTS = "--require-sha";
    HOMEBREW_FORCE_BREWED_CURL = "1";
    HOMEBREW_NO_ANALYTICS = "1";
    HOMEBREW_NO_GITHUB_API = "1";
    HOMEBREW_NO_INSECURE_REDIRECT = "1";
    HOMEBREW_NO_ENV_HINTS = "1";

    ARCHFLAGS = "-arch arm64";

    # Puppeteer / mermaid-cli (mmdc) on darwin.
    #
    # mermaid-cli is bundled with a puppeteer-core that pins an exact
    # Chromium revision (e.g. 131.0.6778.85).  On every nixpkgs bump the
    # pinned revision drifts, the user has to re-run
    # `npx puppeteer browsers install` and the binary that lands in
    # ~/.cache/puppeteer never matches what THIS mermaid-cli wants.
    #
    # Solution: tell puppeteer-core to use the system Chrome (managed
    # via Brewfile cask "google-chrome") and skip its own download
    # entirely.  Picked up by Emacs GUI via exec-path-from-shell, which
    # sources the shell init files where home.sessionVariables lands.
    #
    # Source of the convention: https://pptr.dev/api/puppeteer.configuration
    PUPPETEER_EXECUTABLE_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
    PUPPETEER_SKIP_DOWNLOAD = "true";
  };

  # Bootstrap Homebrew into the shell environment.
  programs.zsh.profileExtra = lib.fileContents ../config/brew-shellenv.zsh;

  # Restore macOS-specific interactive shell features (COMBINING_CHARS,
  # disable log builtin, Terminal.app hooks) that nix-darwin's generated
  # /etc/zshrc omits.
  programs.zsh.initContent = lib.fileContents ../config/macos-zshrc.zsh;

  # Brewfile integration (imperative bridging for macOS GUI apps)

  home.activation.brewBundle =
    lib.hm.dag.entryAfter ["writeBoundary"]
    brewBundleActivation;

  # Default applications (UTI and URL-scheme handlers via duti)

  home.activation.defaultApps =
    lib.hm.dag.entryAfter ["brewBundle"]
    defaultAppsActivation;

  # macOS desktop wallpaper is intentionally NOT managed here. macOS persists
  # it per-user, and the wallpaper store format (com.apple.wallpaper) is an
  # undocumented binary plist that changed shape across releases (Type
  # "linked" -> "individual"), so scripted edits set the wrong wallpaper. Set
  # it once via System Settings.

  # Clear .hushlogin at login so the shell greeting runs once per session

  launchd.agents.clear-hushlogin = {
    enable = true;
    config = {
      Label = "com.user.clear-hushlogin";
      ProgramArguments = ["/bin/sh" "-c" "/bin/rm -f \"$HOME/.hushlogin\""];
      RunAtLoad = true;
      StandardErrorPath = "/dev/null";
      StandardOutPath = "/dev/null";
    };
  };

  # Nix flake staleness check (weekly)
  #
  # Warns via terminal notification if any flake input is older than
  # 14 days.  Runs weekly on Monday at 09:00; launchd catches up after
  # sleep or shutdown automatically.

  launchd.agents.nix-staleness-check = {
    enable = true;
    config = {
      Label = "com.user.nix-staleness-check";
      ProgramArguments = [
        "/bin/sh"
        "-c"
        (lib.fileContents ../scripts/nix-staleness-check.sh)
      ];
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 9;
          Minute = 0;
        }
      ];
      StandardErrorPath = "/dev/null";
      StandardOutPath = "/dev/null";
    };
  };

  # Docker: bind published ports to localhost by default
  #
  # Docker publishes `-p` ports to 0.0.0.0 (all interfaces) by default, which
  # would expose container services to the local network.
  # Setting "ip" makes `docker run -p PORT:PORT` (and compose without an
  # explicit host IP) default to 127.0.0.1. Managed here, not via Docker
  # Desktop's UI, so it is reproducible and cannot silently drift; edit engine
  # config in this attrset rather than the Docker Desktop "Docker Engine" pane.
  home.file.".docker/daemon.json".text = builtins.toJSON {
    ip = "127.0.0.1";
    experimental = false;
    builder.gc = {
      enabled = true;
      defaultKeepStorage = "20GB";
    };
  };

  # Start apps at login

  launchd.agents.notunes = {
    enable = true;
    config = {
      Label = "com.user.notunes";
      ProgramArguments = ["/usr/bin/open" "-a" "NoTunes"];
      RunAtLoad = true;
      StandardErrorPath = "/dev/null";
      StandardOutPath = "/dev/null";
    };
  };

  launchd.agents.rectangle = {
    enable = true;
    config = {
      Label = "com.user.rectangle";
      ProgramArguments = ["/usr/bin/open" "-a" "Rectangle"];
      RunAtLoad = true;
      StandardErrorPath = "/dev/null";
      StandardOutPath = "/dev/null";
    };
  };

  # macOS overrides for Ghostty terminal emulator
  #
  # ghostty is installed via the Homebrew cask (config/Brewfile), not
  # via Nix: pkgs.ghostty is marked broken on Darwin.  Setting
  # package = null prevents the Home Manager module from adding the
  # broken derivation to home.packages while still wiring up shell
  # integration and XDG config-file management.
  # base.nix enables programs.ghostty and deploys the shared config;
  # we only override what differs on macOS.

  programs.ghostty.package = null; # installed via Homebrew cask

  xdg.configFile."ghostty/config".text = lib.mkForce (
    (lib.fileContents ../config/ghostty/config)
    + "\n# Platform\nfont-size = 22\nshell-integration = detect\n"
  );

  # macOS-specific HOME layout (mov -> Movies, hide default folders)
  #
  # Creates the mov alias pointing at ~/Movies and applies the
  # UF_HIDDEN flag (chflags hidden) to the default macOS folders so
  # that Finder omits them when browsing $HOME.  The folders remain
  # fully functional for all applications.

  home.activation.homeLayoutMacOS =
    lib.hm.dag.entryAfter ["brewBundle" "writeBoundary"]
    (lib.fileContents ../scripts/home-layout-macOS.sh);
}

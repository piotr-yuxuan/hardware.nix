# Home Manager settings of the Mac only; home/base.nix holds the shared ones.
{
  lib,
  unstable,
  ...
}: let
  # A launchd agent that runs `open` with these arguments once per login.
  openAtLogin = name: arguments: {
    enable = true;
    config = {
      Label = "com.user.${name}";
      ProgramArguments = ["/usr/bin/open"] ++ arguments;
      RunAtLoad = true;
      StandardErrorPath = "/dev/null";
      StandardOutPath = "/dev/null";
    };
  };
in {
  home.packages = [
    # Languages & runtimes (macOS specific)
    unstable.luarocks
    unstable.pipenv

    # VCS / GitOps
    unstable.glab
    # At 19.5.2 its kubernetes tests do not compile on Darwin, so no
    # cache serves it and the build fails.
    (unstable.gitlab-runner.overrideAttrs {doCheck = false;})

    # Linux gets the wrapped Podman package from its NixOS module.
    unstable.podman

    # Terraform, for the HashiCorp extension of VS Code. nixOS stays
    # with OpenTofu (home/base.nix).
    unstable.terraform # unfree (BSL), so built from source; the extension formats and validates with it
    unstable.terraform-ls # nothing calls this copy by default: the extension bundles its own

    # Text / docs
    unstable.gnugrep
    unstable.gnused

    # Nix CLI helper; nixOS has it from programs.nh at system level.
    unstable.nh

    # Default-app management (sets UTI/MIME handlers via LaunchServices)
    unstable.duti
    unstable.kubelogin # Azure kubelogin: signs kubectl in to AKS clusters
    #unstable.azure-cli # az
  ];

  # The Git identities live in the Mac's own flake (templates/macOS); until
  # they are filled in, a commit fails rather than guess a name.
  programs.git.settings.user.useConfigOnly = true;

  # Keep SSH key passphrases in the login Keychain (Apple's ssh only).
  programs.ssh.settings."*".UseKeychain = "yes";

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

    # mermaid-cli's Puppeteer uses the cask's Chrome rather than download
    # its own pinned Chromium, which drifts at each nixpkgs update. Emacs.app
    # does not see these: docs/how-to/macOS-troubleshoot-emacs.org.
    PUPPETEER_EXECUTABLE_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
    PUPPETEER_SKIP_DOWNLOAD = "true";
  };

  # Bootstrap Homebrew into the shell environment.
  programs.zsh.profileExtra = lib.fileContents ../config/brew-shellenv.zsh;

  # The parts of Apple's /etc/zshrc that nix-darwin's leaves out.
  programs.zsh.initContent = lib.fileContents ../config/macos-zshrc.zsh;

  # Brewfile integration (imperative bridging for macOS GUI apps). A
  # failure only warns: activation must not abort the whole switch.
  home.activation.brewBundle =
    lib.hm.dag.entryAfter ["writeBoundary"]
    "BREWFILE=${../config/Brewfile} bash ${../scripts/brew-bundle-activation.sh} || echo 'brewBundle: warning: Brewfile activation failed; continuing.' >&2";

  # Default applications (UTI and URL-scheme handlers via duti); the
  # script skips a handler whose application is missing.
  home.activation.defaultApps =
    lib.hm.dag.entryAfter ["brewBundle"]
    "DUTI_BIN=${unstable.duti}/bin/duti bash ${../scripts/set-macos-defaults.sh}";

  # The wallpaper is set by hand: its undocumented store changes shape
  # between macOS releases, so scripted edits set the wrong one.

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

  # On Mondays, a notification when a flake input is over 14 days old.

  launchd.agents.nix-staleness-check = {
    enable = true;
    config = {
      Label = "com.user.nix-staleness-check";
      ProgramArguments = ["/bin/sh" "${../scripts/nix-staleness-check.sh}"];
      # launchd agents do not inherit shell variables. PATH gives the
      # script nix and Apple's jq and osascript. Without NH_FLAKE the
      # script finds no flake and exits silently: the Mac's own flake
      # sets it to its own directory (templates/macOS/identity.nix).
      EnvironmentVariables.PATH = "/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
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

  # Published ports bind to 127.0.0.1, not to every interface, as containers
  # may hold production data. Edit the engine here, not in Docker Desktop.
  home.file.".docker/daemon.json".text = builtins.toJSON {
    ip = "127.0.0.1";
    experimental = false;
    builder.gc = {
      enabled = true;
      defaultKeepStorage = "20GB";
    };
  };

  # Start apps at login
  launchd.agents.docker-desktop = openAtLogin "docker-desktop" ["-g" "-j" "-a" "Docker"];
  launchd.agents.notunes = openAtLogin "notunes" ["-a" "NoTunes"];
  launchd.agents.rectangle = openAtLogin "rectangle" ["-a" "Rectangle"];

  # Ghostty comes from the Homebrew cask (home/base.nix sets no package).
  xdg.configFile."ghostty/config".text =
    (lib.fileContents ../config/ghostty/config)
    + "\n# Platform\nfont-size = 22\nshell-integration = detect\n";

  # ~/mov links to ~/Movies, and Finder hides the default folders.

  home.activation.homeLayoutMacOS =
    lib.hm.dag.entryAfter ["brewBundle" "writeBoundary"]
    (lib.fileContents ../scripts/home-layout-macOS.sh);
}

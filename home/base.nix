# Home Manager base module (cross-platform).
#
# Imported by both nixOS (NixOS) and macOS (standalone macOS).
# Per-host overrides live in home/nixOS.nix and home/macOS.nix.
#
# RULE: Only settings that are picked up and applied on *both*
#       NixOS and macOS belong here.  Platform-specific config
#       goes in the corresponding host file.
#
# `unstable` is passed via extraSpecialArgs from the flake.
{
  lib,
  config,
  unstable,
  starship-gruvbox-rainbow,
  practicalli-clojure-deps-edn,
  ...
}: let
  engraveFaces = unstable.emacsPackages.engrave-faces;
  piMcpAdapter = unstable.callPackage ../packages/pi-mcp-adapter.nix {};
in {
  # Let Home Manager manage itself.
  programs.home-manager.enable = true;

  #  Packages: cross-platform CLI tools (both hosts)
  home.packages = [
    # Build toolchain
    unstable.cmake
    unstable.pkg-config
    unstable.enchant # libenchant for jinx / spell compile-time dep
    unstable.maven
    unstable.esbuild # fallback only; projects invoke their locked esbuild

    # Languages & runtimes
    unstable.python3
    unstable.nodejs
    unstable.bun # JavaScript runtime, package manager, and bundler
    unstable.go

    # Rust toolchain
    unstable.cargo
    unstable.rustc
    unstable.rustfmt
    unstable.rust-analyzer

    # Java runtime (required by Clojure CLI / deps.edn).
    # temurin-bin-27 is non-LTS (supported until JDK 28, ~Mar 2027); bump then.
    unstable.temurin-bin-27
    unstable.zig # used by emacs-libgterm (gterm) to compile its dynamic module

    # Clojure ecosystem
    unstable.babashka # fast Clojure scripting (no JVM startup)
    unstable.clj-kondo # Clojure linter / static analysis
    unstable.clojure # Clojure CLI tools (clj / clojure)
    unstable.leiningen # Clojure project automation & build tool
    unstable.neil # manage deps.edn aliases & deps
    unstable.rlwrap # optional: readline history for `clj`

    # Language servers (lsp-mode)
    unstable.clojure-lsp
    unstable.texlab # LaTeX language server
    unstable.basedpyright
    unstable.typescript-language-server
    unstable.typescript
    unstable.ltex-ls-plus
    unstable.jdt-language-server
    unstable.bash-language-server
    unstable.dockerfile-language-server
    unstable.yaml-language-server
    unstable.tofu-ls # OpenTofu language server
    unstable.nixd
    unstable.gopls
    unstable.lua-language-server
    unstable.tailwindcss-language-server # Tailwind CSS in HTML / JSX / TSX
    unstable.htmx-lsp # htmx attribute completion in HTML
    unstable.docker-compose-language-service # binary: docker-compose-langserver, for compose.yaml
    unstable.marksman # Markdown structural LSP (headings, links, refs)
    # Bundle of HTML, CSS, JSON, ESLint and Markdown servers extracted
    # from VS Code.  One Nix package, five binaries:
    # vscode-{html,css,json,eslint,markdown}-language-server.
    unstable.vscode-langservers-extracted

    # Formatters
    unstable.alejandra # Nix formatter
    unstable.black
    unstable.cljfmt
    unstable.isort
    unstable.yamlfmt
    unstable.shfmt
    unstable.prettier

    # Linters
    unstable.statix # Nix anti-pattern linter
    unstable.deadnix # unused Nix code detector
    unstable.shellcheck
    unstable.yamllint
    unstable.python3Packages.cfn-lint # CloudFormation template linter

    # Testing
    unstable.bats # shell test framework (tests/ directory)

    # CLI utilities
    # fortune and enca are not listed here: both need recode, which
    # fails to build on aarch64-darwin (nixpkgs#568679). nixOS gets them
    # from Nix (home/nixOS.nix) and macOS from Homebrew (config/Brewfile).
    unstable.macchina
    unstable.yq-go
    unstable.curl
    unstable.socat # stdio bridge for the Emacs MCP Unix socket
    unstable.tokei
    unstable.onefetch
    unstable.scc
    unstable.gource # animated 3D visualisation of repository history
    unstable.bmon
    unstable.coreutils
    unstable.duckdb
    unstable.postgresql
    unstable.fx
    unstable.qrencode
    unstable.silver-searcher-ng # maintained Silver Searcher fork; provides ag alongside rg
    unstable.tree
    unstable.poppler-utils # pdftotext, pdfinfo, etc. (xpdf is CVE-marked)
    unstable.ffmpeg # media processing (also used by yt-dlp)
    unstable.ispell
    unstable.age # modern file encryption
    unstable.graphviz
    unstable.mermaid-cli # mmdc for ob-mermaid (Org Babel mermaid blocks)
    engraveFaces # fast font-lock highlighting for Org LaTeX exports
    unstable.inxi
    unstable.lsof
    unstable.difftastic
    unstable.zola # static site generator (Rust); moved here from Homebrew

    # IaC / Cloud
    unstable.aws-vault # secure AWS credential management
    unstable.ssm-session-manager-plugin
    unstable.git-sizer # repository size metrics and health check
    unstable.podman-compose
    unstable.sops
    unstable.opentofu
    unstable.terraform-mcp-server
    unstable.infracost
    unstable.tflint
    unstable.terraform-docs
    unstable.terraform-landscape
    # Programs that VS Code extensions call, and pre-commit, which team
    # repositories run. Only free packages that the binary cache serves
    # are shared with nixOS. Not listed here:
    # - terraform and terraform-ls, for macOS only (home/macOS.nix):
    #   terraform is unfree, so it is built from source, and nixOS
    #   stays with OpenTofu;
    # - dbt, whose extension installs the dbt v2 binary itself, as
    #   ~/.local/bin/dbt;
    # - snowflake-cli (snow), whose build fails on both hosts at the
    #   locked nixpkgs (snowflake-connector-python under Python 3.14):
    #   macOS takes it from Homebrew (config/Brewfile).
    unstable.kubectl
    unstable.kubernetes-helm # helm
    unstable.kubelogin # Azure kubelogin: signs kubectl in to AKS clusters
    unstable.azure-cli # az
    unstable.sqlfluff # SQL linter and formatter
    unstable.pre-commit # runs the hooks of a repository's .pre-commit-config.yaml

    # PyCharm is per host: on macOS it would be the only Nix .app, and
    # Home Manager's app copy then needs App Management permission at
    # every switch. macOS uses the Homebrew cask (config/Brewfile) and
    # nixOS uses Nix (home/nixOS.nix).

    # CloudFormation
    unstable.rain # CloudFormation deploy / diff CLI

    # Load testing / monitoring
    unstable.k6 # modern load testing (scripted in JS)
    unstable.vegeta # HTTP load testing CLI
    unstable.hey # simple HTTP load generator

    # Profiling / flamegraphs
    # visualvm is intentionally not in this shared list: on macOS it is
    # installed via the Homebrew cask (config/Brewfile) for the native
    # .app, and on nixOS via Nix (home/nixOS.nix). Listing it here
    # would also put a (redundant) Nix copy on macOS.
    unstable.async-profiler # low-overhead JVM sampling profiler
    unstable.flamegraph # Brendan Gregg's FlameGraph scripts

    # System management
    unstable.nh # Nix CLI helper: human-friendly rebuild, diff, GC, and search

    # AI coding agent
    unstable.pi-coding-agent
    piMcpAdapter

    # Build tools
    unstable.meson
    unstable.ninja

    # Email (mu, mu4e, and isync/mbsync managed via programs.mu and
    # programs.mbsync; email account config lives in home/nixOS.nix)

    # Spell & grammar
    unstable.languagetool # grammar checker (EN, FR, PL, …)
    unstable.python3Packages.grammalecte # French grammar checker
    unstable.hunspell
    unstable.hunspellDicts.en_GB-ise
    unstable.hunspellDicts.en_US
    unstable.hunspellDicts.fr-classique
    unstable.hunspellDicts.pl_PL
    unstable.hunspellDicts.es_ES
    unstable.hunspellDicts.de_DE
    (unstable
      .callPackage ../packages/hunspell-dict-la.nix {})
    unstable.aspell
    unstable.aspellDicts.en
    unstable.aspellDicts.fr
    unstable.aspellDicts.pl
    unstable.aspellDicts.la
    unstable.aspellDicts.es
    unstable.aspellDicts.de
  ];

  xdg.enable = true;

  programs.zsh = {
    enable = true;
    # Opt into the upcoming Home Manager default: keep zsh dotfiles under
    # XDG (~/.config/zsh) instead of $HOME. HM writes a bootstrap
    # ~/.zshenv that sets ZDOTDIR. Silences the 26.05 dotDir warning.
    dotDir = "${config.xdg.configHome}/zsh";
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    completionInit = "autoload -Uz compinit && compinit";
    plugins = [
      {
        name = "zsh-completions";
        src = unstable.zsh-completions;
      }
      {
        name = "nix-zsh-completions";
        src = unstable.nix-zsh-completions;
      }
    ];

    # History (keep everything, delete nothing)
    history = {
      # Pin HISTFILE explicitly (its default follows dotDir). History is
      # mutable state, so it lives under XDG_STATE_HOME, not the config
      # dir. The old ~/.zsh_history was merged + deduplicated into here.
      path = "${config.xdg.stateHome}/zsh/history";
      size = 10000000;
      save = 10000000;
      extended = true; # :start:elapsed;command format
      share = true; # share across sessions (implies INC_APPEND)
      ignoreDups = true; # skip consecutive duplicates
      ignoreSpace = true; # prefix with space to omit from history
      expireDuplicatesFirst = true; # safety net if size limit is ever hit
    };

    shellAliases = {
      cat = "bat --paging never";
    };

    # ~/.zshenv is sourced for every zsh invocation
    envExtra = lib.fileContents ../config/before.zshenv;

    # initContent replaces the older initExtra/initExtraFirst (HM ≥ 25.11).
    # All interactive-shell init goes here.
    initContent = lib.fileContents ../config/after.zshrc;
  };

  # Starship prompt (gruvbox-rainbow preset, declarative)
  # The preset TOML is fetched from upstream via the
  # starship-gruvbox-rainbow flake input; `nix flake update`
  # pulls the latest version automatically.
  programs.starship = {
    enable = true;
    package = unstable.starship;
    enableZshIntegration = true;
    settings = lib.recursiveUpdate (builtins.fromTOML (builtins.readFile starship-gruvbox-rainbow)) {
      os.symbols.NixOS = ""; # nf-linux-nixos

      # Replace the gruvbox-rainbow preset's Nerd Font arrow prompt
      # with a POSIX `$` for regular users and `#` for root.  The
      # built-in `character` module has no root detection, so disable
      # it and use two `custom` modules gated on $USER.  The format
      # string lives in config/starship-format.txt: same content as
      # the upstream preset, but ends with $custom instead of
      # $character.
      format = lib.mkForce (lib.fileContents ../config/starship-format.txt);

      character.disabled = true;

      custom.user_char = {
        when = "test \"$USER\" != \"root\"";
        format = "[\\$](bold fg:color_green) ";
      };

      custom.root_char = {
        when = "test \"$USER\" = \"root\"";
        format = "[#](bold fg:color_red) ";
      };
    };
  };

  programs.git = {
    enable = true;
    lfs.enable = true;

    settings = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      rebase.autoStash = true;
      fetch.prune = true;
      rerere.enabled = true;
      merge.conflictstyle = "zdiff3";
      diff.algorithm = "histogram";

      core = {
        autocrlf = "input";
        whitespace = "trailing-space,space-before-tab";
      };

      # Supply-chain hardening to verify integrity of all received objects.
      transfer.fsckObjects = true;
      fetch.fsckObjects = true;
      receive.fsckObjects = true;

      # Block cleartext git:// protocol; allow only https and ssh.
      protocol.allow = "never";
      "protocol.https".allow = "always";
      "protocol.ssh".allow = "always";
      "protocol.file".allow = "user";

      # core.pager and interactive.diffFilter are set automatically
      # by programs.delta, so no need to declare them here.
    };

    ignores = lib.splitString "\n" (lib.fileContents ../config/gitignore);
  };

  # GitHub CLI.  The Home Manager module is preferred over a plain
  # `unstable.gh` in `home.packages`: it manages
  # `~/.config/gh/config.yml` declaratively, wires `gh auth
  # git-credential` into `programs.git` for HTTPS remotes, and runs
  # the `migrateGhAccounts` activation required since gh 2.40.0.
  #
  # `package` is pinned to `unstable.gh` because `useGlobalPkgs =
  # true` would otherwise bind it to the stable channel. The same
  # selective override is used for other fast-moving user programs,
  # while mature and foundational program defaults remain stable.
  #
  # `git_protocol = "ssh"` matches the per-host SSH setup: the
  # personal module of nixOS pins an `IdentityFile` for `github.com`,
  # and the Mac's own flake selects the personal key by directory through
  # `core.sshCommand`.  `gh repo clone` and `gh pr checkout` therefore
  # use SSH (on macOS, run them below ~/src/github.com/piotr-yuxuan/ for
  # personal repositories).
  programs.gh = {
    enable = true;
    package = unstable.gh;
    settings.git_protocol = "ssh";
  };

  programs.delta = {
    enable = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = false; # That breaks magit: either override it in magit, or disable it here.
      syntax-theme = "ansi";
    };
  };

  programs.bat = {
    enable = true;
    config = {
      theme = "ansi";
      style = "numbers,changes,header";
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    # fd respects .gitignore, follows symlinks, and shows hidden files.
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    fileWidgetCommand = "fd --type f --hidden --follow --exclude .git";
    changeDirWidgetCommand = "fd --type d --hidden --follow --exclude .git";
    defaultOptions = [
      "--multi"
      "--height=50%"
      "--layout=reverse"
      "--border=rounded"
      "--info=inline"
      "--bind=ctrl-a:toggle-all"
      "--bind=ctrl-/:toggle-preview"
      "--bind=ctrl-u:preview-half-page-up"
      "--bind=ctrl-d:preview-half-page-down"
      "--bind=alt-up:preview-top"
      "--bind=alt-down:preview-bottom"
    ];
    fileWidgetOptions = [
      "--preview='bat --color=always --style=numbers,changes --line-range=:300 {}'"
      "--preview-window=right:55%:wrap:hidden"
    ];
    changeDirWidgetOptions = [
      "--preview='eza --tree --color=always --icons=auto --level=3 {}'"
      "--preview-window=right:45%:hidden"
    ];
    historyWidgetOptions = [
      "--sort"
      "--exact"
      "--preview='echo {}'"
      "--preview-window=down:3:wrap:hidden"
    ];
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    icons = "auto";
    git = true;
    extraOptions = ["--group-directories-first"];
  };
  programs.tmux = {
    enable = true;
    keyMode = "vi";
    mouse = true;
    terminal = "tmux-256color";
    historyLimit = 50000;
    escapeTime = 10; # ms; keep low so Emacs M-... sequences are fast
    baseIndex = 1;
    extraConfig = lib.fileContents ../config/tmux.conf;
  };

  #  Ghostty terminal emulator
  #
  # Shared config deployed on both NixOS and macOS.  Platform overrides
  # (package source, font-size) live in home/macOS.nix and the NixOS
  # host file respectively.
  programs.ghostty = {
    enable = true;
    # On Darwin pkgs.ghostty is broken; macOS.nix overrides package = null.
    # On NixOS the default (pkgs.ghostty) works.
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
  programs.btop.enable = true;
  programs.htop = {
    enable = true;
    settings = {
      show_program_path = false;
      tree_view = true;
      sort_key = 46; # PERCENT_CPU
      highlight_base_name = true;
    };
  };
  programs.gpg = {
    enable = true;
    settings = {
      personal-cipher-preferences = "AES256 AES192 AES";
      personal-digest-preferences = "SHA512 SHA384 SHA256";
      cert-digest-algo = "SHA512";
      default-preference-list = "SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed";
      s2k-digest-algo = "SHA512";
      s2k-cipher-algo = "AES256";
      keyid-format = "0xlong";
      with-fingerprint = true;
      use-agent = true;
    };
  };
  services.gpg-agent = {
    enable = true;
    enableZshIntegration = true;
    extraConfig = lib.fileContents ../config/gpg-agent.conf;
    pinentry.package =
      if unstable.stdenv.hostPlatform.isDarwin
      then unstable.pinentry_mac
      else if unstable.stdenv.hostPlatform.isLinux
      then unstable.pinentry-gnome3
      else throw "pinentry: unsupported platform";
    defaultCacheTtl = 3600;
    maxCacheTtl = 7200;
  };

  # nh: NH_OS_FLAKE (set by programs.nh.flake on NixOS) takes precedence
  # over NH_FLAKE for `nh os` commands.  NH_FLAKE is intentionally unset
  # here: the flake path is user-specific and must be supplied at the call
  # site (e.g. `nh home switch /path/to/repo`) or via a shell alias.

  # Prebuilt Elisp on Emacs load-path
  # Append (not override): the trailing ":" tells Emacs to keep defaults.
  home.sessionVariables.EMACSLOADPATH = "${engraveFaces}/share/emacs/site-lisp/elpa/engrave-faces-${engraveFaces.version}:${config.programs.mu.package.mu4e}/share/emacs/site-lisp/mu4e:";

  # Native-module compilation (jinx, vterm, …)
  # NixOS has no /usr/include, so expose enchant (+ other lib) headers
  # and pkg-config metadata so `gcc` invoked from inside Emacs can
  # find them.
  #
  # NOTE (macOS): Emacs.app (jimeh/emacs-builds) hard-overrides
  # LIBRARY_PATH at startup with its own GCC framework + Xcode SDK
  # paths (for libgccjit native compilation).  This means the enchant
  # LIBRARY_PATH set here is silently lost inside Emacs on macOS.
  # pkg-config (PKG_CONFIG_PATH) already provides the -L flag to the
  # compiler, so jinx still compiles.  However the Xcode SDK paths
  # that Emacs injects into LIBRARY_PATH conflict with Nix GCC's
  # --sysroot, causing link failures for tree-sitter grammar
  # compilation.  The Emacs config works around this with :around
  # advice on `treesit-install-language-grammar' that strips
  # LIBRARY_PATH for the subprocess.
  home.sessionVariables.PKG_CONFIG_PATH = "${unstable.enchant.dev}/lib/pkgconfig";
  home.sessionVariables.C_INCLUDE_PATH = "${unstable.enchant.dev}/include";
  home.sessionVariables.LIBRARY_PATH = "${lib.getLib unstable.enchant}/lib";

  home.sessionVariables.DICPATH = lib.concatStringsSep ":" [
    "${unstable.hunspellDicts.en_GB-ise}/share/hunspell"
    "${unstable.hunspellDicts.en_US}/share/hunspell"
    "${unstable.hunspellDicts.fr-classique}/share/hunspell"
    "${unstable.hunspellDicts.pl_PL}/share/hunspell"
    "${unstable.hunspellDicts.es_ES}/share/hunspell"
    "${unstable.hunspellDicts.de_DE}/share/hunspell"
    "${unstable.callPackage ../packages/hunspell-dict-la.nix {}}/share/hunspell"
  ];

  xdg.configFile."enchant/enchant.ordering".text = lib.fileContents ../config/enchant.ordering;
  home.file.".aspell.conf".text = lib.fileContents ../config/aspell.conf;

  home.activation.homeLayout =
    lib.hm.dag.entryAfter ["writeBoundary"]
    (lib.fileContents ../scripts/home-layout.sh);

  # bhauman/clojure-mcp: installed via Clojure tools so it is
  # available as `clojure -Tmcp start` from any directory.  The
  # install command is idempotent (overwrites on re-run).
  home.activation.clojureMcpInstall =
    lib.hm.dag.entryAfter ["writeBoundary"]
    (builtins.replaceStrings
      ["@CLOJURE_BIN@" "@GIT_DIR@"]
      ["${unstable.clojure}/bin/clojure" "${unstable.git}/bin"]
      (builtins.readFile ../scripts/clojure-mcp-install.sh));

  # Pi deliberately has no built-in MCP client.  Deploy the pinned
  # adapter as a global extension and keep its server declarations in
  # the tool-agnostic MCP configuration path.  Pi's mutable
  # ~/.pi/agent/settings.json remains unmanaged.
  home.file.".pi/agent/extensions/pi-mcp-adapter".source = "${piMcpAdapter}/lib/node_modules/pi-mcp-adapter";
  xdg.configFile."mcp/mcp.json".source = ../config/mcp.json;
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    # 26.05: matchBlocks + extraOptions are deprecated in favour of
    # settings, a freeform attrset keyed by host that uses upstream
    # OpenSSH directive names. The "*" default block is emitted last.
    settings."*" = {
      AddKeysToAgent = "yes";
      ForwardAgent = false;
      ControlMaster = "auto";
      ControlPath = "~/.ssh/control-%C";
      ControlPersist = "10m";
      ServerAliveInterval = 60;
      ServerAliveCountMax = 3;
      HashKnownHosts = true;
      IdentitiesOnly = "yes";
      PasswordAuthentication = "no";
      StrictHostKeyChecking = "accept-new";
    };
  };

  programs.asciinema.enable = true;
  programs.awscli = {
    enable = true;
    package = unstable.awscli2;
  };
  programs.fd = {
    enable = true;
    hidden = true;
  };
  programs.gcc.enable = true;
  programs.granted = {
    enable = true;
    package = unstable.granted;
    enableZshIntegration = true;
  };
  programs.jq.enable = true;
  programs.mu.enable = true;
  programs.pandoc.enable = true;
  programs.ripgrep = {
    enable = true;
    arguments = [
      "--smart-case"
      "--hidden"
      "--glob=!.git/"
      "--glob=!node_modules/"
      "--glob=!.direnv/"
      "--glob=!straight/repos/"
      "--glob=!eln-cache/"
    ];
  };
  programs.ruff = {
    enable = true;
    package = unstable.ruff;
    # User fallback only: a project's Ruff configuration takes
    # precedence.
    settings = {
      lint.select = ["ALL"];
      lint.ignore = [
        "D203" # Prefer no blank line before a class docstring (D211).
        "D213" # Prefer a summary on the first docstring line (D212).
        # Leave indentation, quoting, and trailing commas to the
        # formatter.
        "W191"
        "E111"
        "E114"
        "E117"
        "D206"
        "D300"
        "Q000"
        "Q001"
        "Q002"
        "Q003"
        "Q004"
        "COM812"
        "COM819"
      ];
    };
  };
  programs.uv = {
    enable = true;
    package = unstable.uv;
    settings = {};
  };
  programs.poetry = {
    enable = true;
    package = unstable.poetry;
    settings = {};
  };
  programs.sqls.enable = true;
  programs.tealdeer.enable = true;
  programs.yt-dlp = {
    enable = true;
    package = unstable.yt-dlp;
  };

  #  XDG base directories
  # Practicalli Clojure deps.edn
  # Community aliases for tools.deps.  Tracked as a flake input so
  # `nix flake update` always pulls the latest main commit.
  xdg.configFile."clojure/deps.edn".source = "${practicalli-clojure-deps-edn}/deps.edn";
  xdg.configFile."clojure-lsp/config.edn".source = ../config/clojure-lsp/config.edn;

  # Maven local user settings: download *-sources.jar for every
  # dependency so clojure-lsp can navigate Java symbols to .java
  # sources rather than CFR decompiled output.  Maven reads
  # ~/.m2/settings.xml on every supported platform (NixOS, macOS).
  home.file.".m2/settings.xml".source = ../config/maven/settings.xml;
}

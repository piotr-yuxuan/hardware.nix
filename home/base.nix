# Home Manager settings of both hosts, nixOS (NixOS) and the Mac
# (nix-darwin); each host adds its own in home/<host>.nix. A value that
# differs by platform takes an explicit conditional, as pinentry does.
# Packages come from `unstable`: see AGENTS.md, "Package channels".
{
  lib,
  config,
  pkgs,
  unstable,
  starship-gruvbox-rainbow,
  practicalli-clojure-deps-edn,
  ...
}: let
  engraveFaces = unstable.emacsPackages.engrave-faces;
  hunspellDicts = [
    unstable.hunspellDicts.en_GB-ise
    unstable.hunspellDicts.en_US
    unstable.hunspellDicts.fr-classique
    unstable.hunspellDicts.pl_PL
    unstable.hunspellDicts.es_ES
    unstable.hunspellDicts.de_DE
    (unstable.callPackage ../packages/hunspell-dict-la.nix {})
  ];
in {
  programs.home-manager.enable = true;

  home.packages =
    [
      # Build toolchain
      unstable.cmake
      unstable.pkg-config
      unstable.enchant # libenchant for jinx / spell compile-time dep
      unstable.maven
      unstable.esbuild # fallback only; projects invoke their locked esbuild
      unstable.gcc

      # Languages & runtimes
      unstable.python3
      unstable.nodejs
      unstable.bun # JavaScript runtime, package manager, and bundler
      unstable.go
      unstable.uv # Python projects and tools
      unstable.poetry

      # Rust toolchain
      unstable.cargo
      unstable.clippy # rust-analyzer's check command, here and in Emacs
      unstable.rustc
      unstable.rustfmt
      unstable.rust-analyzer
      unstable.sccache # compilation cache
      unstable.rust-code-analysis # rust-code-analysis-cli: source code metrics

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
      unstable.sqls # SQL language server
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
      unstable.docker-language-server # Docker's, for Compose files
      unstable.tombi # TOML
      unstable.marksman # Markdown structural LSP (headings, links, refs)
      unstable.vscode-langservers-extracted # HTML, CSS, JSON, ESLint, Markdown

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
      unstable.asciinema # terminal session recorder
      unstable.btop
      unstable.jq
      unstable.yt-dlp
      unstable.zsh-completions # reaches fpath through the profile's share/zsh
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
      unstable.awscli2
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
      # repositories run. Shared only when the binary cache serves them,
      # or, for the two dbt binaries, a download from dbt Labs.
      # docs/reference/package-guide.org says why terraform and
      # snowflake-cli are left out, and which dbt runs.
      unstable.kubectl
      unstable.kubernetes-helm # helm
      pkgs.sqlfluff # stable on purpose: AGENTS.md, "Package channels"
      (unstable.callPackage ../packages/dbt.nix {})
      (unstable.callPackage ../packages/dbt-proprietary.nix {}) # dbt-2.0.9, unfree
      # No binary cache serves it: a small Rust build, accepted on both hosts.
      (unstable.callPackage ../packages/dbt-lsp-plus.nix {})
      unstable.pre-commit # runs the hooks of a repository's .pre-commit-config.yaml

      # CloudFormation
      unstable.rain # CloudFormation deploy / diff CLI

      # Load testing / monitoring
      unstable.k6 # modern load testing (scripted in JS)
      unstable.vegeta # HTTP load testing CLI
      unstable.hey # simple HTTP load generator

      # Profiling / flamegraphs
      unstable.async-profiler # low-overhead JVM sampling profiler
      unstable.flamegraph # Brendan Gregg's FlameGraph scripts

      # AI and LLM
      unstable.llama-cpp
      unstable.rtk # shortens command output for coding agents
      (unstable.callPackage ../packages/rust-analyzer-mcp.nix {}) # registered per project
      (unstable.callPackage ../packages/allium.nix {}) # allium and allium-lsp, for Allium's agent plugin
      # Telemetry and the update check off wherever it starts, MCP clients
      # included: docs/reference/package-guide.org, "codegraph".
      (unstable.symlinkJoin {
        inherit (unstable.codegraph) pname version meta;
        paths = [unstable.codegraph];
        nativeBuildInputs = [unstable.makeWrapper];
        postBuild = "wrapProgram $out/bin/codegraph --set CODEGRAPH_TELEMETRY 0 --set CODEGRAPH_NO_UPDATE_CHECK 1";
      })

      # Build tools
      unstable.meson
      unstable.ninja

      # Spell & grammar
      unstable.languagetool # grammar checker (EN, FR, PL, …)
      unstable.python3Packages.grammalecte # French grammar checker
      unstable.hunspell
      unstable.aspell
      unstable.aspellDicts.en
      unstable.aspellDicts.fr
      unstable.aspellDicts.pl
      unstable.aspellDicts.la
      unstable.aspellDicts.es
      unstable.aspellDicts.de
    ]
    ++ hunspellDicts;

  xdg.enable = true;

  programs.zsh = {
    enable = true;
    # Stable, unlike the rest: on nixOS the login shell is NixOS's stable
    # zsh, and on the Mac nix-darwin puts the stable zsh on PATH with its
    # /etc/zshrc.
    package = pkgs.zsh;
    dotDir = "${config.xdg.configHome}/zsh";
    autosuggestion.enable = true;
    syntaxHighlighting = {
      enable = true;
      package = unstable.zsh-syntax-highlighting;
    };
    completionInit = "autoload -Uz compinit && compinit";

    # Keep everything. History is state, so it lives under XDG_STATE_HOME.
    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      size = 10000000;
      extended = true; # :start:elapsed;command format
      expireDuplicatesFirst = true; # safety net if size limit is ever hit
    };

    shellAliases = {
      cat = "bat --paging never";
    };

    envExtra = lib.fileContents ../config/before.zshenv;
    initContent = lib.fileContents ../config/after.zshrc;
  };

  # The gruvbox-rainbow preset, a flake input, with `$` or `#` as prompt.
  programs.starship = {
    enable = true;
    package = unstable.starship;
    settings = lib.recursiveUpdate (builtins.fromTOML (builtins.readFile starship-gruvbox-rainbow)) {
      os.symbols.NixOS = ""; # nf-linux-nixos

      # The `character` module cannot tell root, so two custom modules
      # replace it; config/starship-format.txt is the preset's format
      # ending with $custom.
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
    package = unstable.git;
    lfs = {
      enable = true;
      package = unstable.git-lfs;
    };

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

      # Check every object received.
      transfer.fsckObjects = true;
      fetch.fsckObjects = true;
      receive.fsckObjects = true;

      # Block cleartext git:// protocol; allow only https and ssh.
      protocol.allow = "never";
      "protocol.https".allow = "always";
      "protocol.ssh".allow = "always";
      "protocol.file".allow = "user";

      # The diff, log, show and blame pagers and interactive.diffFilter
      # come from programs.delta below.
    };

    ignores = lib.splitString "\n" (lib.fileContents ../config/gitignore);
  };

  # The module writes gh's configuration and makes gh git's credential
  # helper for HTTPS. SSH matches each host's key setup; on the Mac, run
  # gh below ~/src/github.com/piotr-yuxuan/ for personal repositories.
  programs.gh = {
    enable = true;
    package = unstable.gh;
    settings.git_protocol = "ssh";
  };

  # Git pages through delta and filters `git add -p` with it. magit is
  # not affected: it runs git with --no-pager and stages with git apply.
  programs.delta = {
    enable = true;
    package = unstable.delta;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = false; # magit-delta reads this section: line numbers break magit.
      syntax-theme = "ansi";
    };
  };

  programs.bat = {
    enable = true;
    package = unstable.bat;
    config = {
      theme = "ansi";
      style = "numbers,changes,header";
    };
  };

  programs.fzf = {
    enable = true;
    package = unstable.fzf;
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
    package = unstable.zoxide;
  };
  programs.eza = {
    enable = true;
    package = unstable.eza;
    icons = "auto";
    git = true;
    extraOptions = ["--group-directories-first"];
  };
  programs.tmux = {
    enable = true;
    package = unstable.tmux;
    keyMode = "vi";
    mouse = true;
    terminal = "tmux-256color";
    historyLimit = 50000;
    escapeTime = 10; # ms; keep low so Emacs M-... sequences are fast
    baseIndex = 1;
    extraConfig = lib.fileContents ../config/tmux.conf;
  };

  # Each host writes ghostty/config with its own font size. On the Mac
  # the Homebrew cask installs Ghostty, which nixpkgs builds for Linux only.
  programs.ghostty = {
    enable = true;
    package =
      if unstable.stdenv.hostPlatform.isDarwin
      then null
      else if unstable.stdenv.hostPlatform.isLinux
      then unstable.ghostty
      else throw "ghostty: unsupported platform";
  };

  programs.direnv = {
    enable = true;
    package = unstable.direnv;
    nix-direnv = {
      enable = true;
      package = unstable.nix-direnv;
    };
  };
  programs.htop = {
    enable = true;
    package = unstable.htop;
    settings = {
      show_program_path = false;
      tree_view = true;
      sort_key = 46; # PERCENT_CPU
      highlight_base_name = true;
    };
  };
  programs.gpg = {
    enable = true;
    package = unstable.gnupg;
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

  # Elisp from Nix on Emacs's load path; the final ":" keeps the defaults.
  home.sessionVariables.EMACSLOADPATH = "${engraveFaces}/share/emacs/site-lisp/elpa/engrave-faces-${engraveFaces.version}:${config.programs.mu.package.mu4e}/share/emacs/site-lisp/mu4e:";

  # enchant's headers and libraries for the modules Emacs compiles, such
  # as jinx. Emacs.app replaces LIBRARY_PATH on the Mac:
  # docs/how-to/macOS-troubleshoot-emacs.org.
  home.sessionVariables.PKG_CONFIG_PATH = "${unstable.enchant.dev}/lib/pkgconfig";
  home.sessionVariables.C_INCLUDE_PATH = "${unstable.enchant.dev}/include";
  home.sessionVariables.LIBRARY_PATH = "${lib.getLib unstable.enchant}/lib";

  home.sessionVariables.DICPATH = lib.makeSearchPath "share/hunspell" hunspellDicts;

  home.sessionVariables.RUSTC_WRAPPER = lib.getExe unstable.sccache;

  # For programs installed by hand, such as `cargo install --root
  # ~/.local`. A login shell must see it: Emacs reads PATH from one.
  home.sessionPath = [ "$HOME/.local/bin" ];

  xdg.configFile."enchant/enchant.ordering".text = lib.fileContents ../config/enchant.ordering;
  home.file.".aspell.conf".text = lib.fileContents ../config/aspell.conf;

  home.activation.homeLayout =
    lib.hm.dag.entryAfter ["writeBoundary"]
    (lib.fileContents ../scripts/home-layout.sh);

  # `clojure -Tmcp start` from any directory; git is on the command's PATH
  # because the activation PATH has none.
  home.activation.clojureMcpInstall =
    lib.hm.dag.entryAfter ["writeBoundary"]
    "PATH=${unstable.git}/bin:$PATH run ${unstable.clojure}/bin/clojure -Ttools install-latest :lib io.github.bhauman/clojure-mcp :as mcp || echo 'clojure-mcp-install: install failed (network?), skipping' >&2";

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
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

  programs.fd = {
    enable = true;
    package = unstable.fd;
    hidden = true;
  };
  programs.granted = {
    enable = true;
    package = unstable.granted;
  };
  # On by Home Manager's default; named here for its package.
  programs.man.package = unstable.man;
  programs.mu = {
    enable = true;
    package = unstable.mu;
  };
  # The module wraps pandoc with its data directory, even when empty.
  programs.pandoc = {
    enable = true;
    package = unstable.pandoc;
  };
  programs.ripgrep = {
    enable = true;
    package = unstable.ripgrep;
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
    # Used only where a project has no Ruff configuration.
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
  programs.tealdeer = {
    enable = true;
    package = unstable.tealdeer;
  };

  # Practicalli's aliases for the Clojure CLI, a flake input.
  xdg.configFile."clojure/deps.edn".source = "${practicalli-clojure-deps-edn}/deps.edn";
  xdg.configFile."clojure-lsp/config.edn".source = ../config/clojure-lsp/config.edn;

  # Maven fetches the sources of every dependency, so that clojure-lsp
  # opens Java sources rather than decompiled classes.
  home.file.".m2/settings.xml".source = ../config/maven/settings.xml;

  # rtk reads the platform's configuration directory, which on the Mac
  # is not XDG's. Linked file by file, so the directory stays writable.
  home.file."rtk" = {
    target =
      if unstable.stdenv.hostPlatform.isDarwin
      then "Library/Application Support/rtk"
      else if unstable.stdenv.hostPlatform.isLinux
      then "${config.xdg.configHome}/rtk"
      else throw "rtk: unsupported platform";
    source = ../config/rtk;
    recursive = true;
  };

  # Claude Code's servers, at one path on both hosts for `claude plugin
  # marketplace add`; docs/reference/package-guide.org registers it.
  home.file.".local/share/claude-code/hardware.nix".source =
    ../config/claude-code-marketplace;
}

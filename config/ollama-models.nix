# Ollama models to pre-pull on all machines.
#
# This list is the single source of truth consumed by:
#   - services.ollama.loadModels   (NixOS, hosts/nixOS.nix)
#   - programs.opencode            (cross-platform, home/base.nix)
#   - ollama-pull-models.sh        (macOS, docs/macos-nix-darwin.org)
#
# The script reads this file at runtime with `nix eval -f`.
[
  {
    model = "gemma4:26b";
    name = "Gemma 4 26B";
  }
  {
    model = "qwen3.5:35b";
    name = "Qwen 3.5 35B";
  }
  {
    model = "qwen3.5:0.8b";
    name = "Qwen 3.5 0.8B";
  }
]

# Shared font packages, referenced by both:
#   • home/base.nix  (home.packages, fontconfig on Linux + macOS)
#   • hosts/macOS.nix (fonts.packages, macOS Core Text via /Library/Fonts)
#
# Usage:  import ../fonts.nix { inherit unstable; }
{unstable}:
[
  # Nerd Fonts (terminal / code)
  unstable.nerd-fonts.iosevka
  unstable.nerd-fonts.iosevka-term
  unstable.nerd-fonts.fira-code
  unstable.nerd-fonts.inconsolata
  unstable.font-awesome_7
  unstable.libertine

  # Serif / historical / ligature-rich
  unstable.junicode # medieval/historical, rich OpenType features
  unstable.libertinus # fork of Linux Libertine, extensive ligatures
  unstable.eb-garamond # Garamond revival, old-style ligatures & alternates
  unstable.cardo # scholarly serif, historic glyphs & diacritics
  unstable.sorts-mill-goudy # Goudy Old Style revival, f-ligatures
  unstable.crimson-pro # elegant body serif, OpenType features. Also contains Alegreya-Black.
  unstable.gentium # SIL, covers Latin/Cyrillic/Greek with diacritics

  # Code fonts with ligatures
  unstable.victor-mono # cursive italics, code ligatures
  unstable.cascadia-code # Microsoft, code ligatures & cursive
  unstable.jetbrains-mono # JetBrains, code ligatures
  unstable.recursive # variable font, sans ↔ mono with ligatures

  # Calligraphic / script
  unstable.tex-gyre.chorus # free Zapf Chancery (same design lineage as Zapfino)
  unstable.dancing-script # lively informal calligraphic script
  unstable.lxgw-wenkai # CJK calligraphic Kai based on Klee One
]
# macOS ships its own Zapfino.
++ unstable.lib.optionals unstable.stdenv.hostPlatform.isLinux [
  (unstable.callPackage ./packages/zapfino.nix {})
]
++ [
  (unstable.callPackage ./packages/tw-moe-fonts.nix {})

  # CJK fallback
  unstable.noto-fonts-cjk-sans # CJK sans-serif fallback
  unstable.noto-fonts-cjk-serif # CJK serif fallback
]

# Git identities and local paths of this Mac.
#
# This file belongs to the Mac's own flake and is never published. Fill
# every FIXME here; nothing about this Mac or its employer goes into the
# shared configuration.
{config, ...}: {
  #  Git identity
  #
  # Work is the default identity on this Mac. The personal identity
  # applies below ~/src/github.com/piotr-yuxuan/. The shared
  # configuration sets user.useConfigOnly: until the work identity is
  # filled in, commits outside the personal directory fail instead of
  # using a wrong identity.
  #
  # FIXME: uncomment and fill the work identity. If signed commits are
  # required, also add signingKey to it, and commit.gpgSign, tag.gpgSign
  # and gpg.format beside it.
  # programs.git.settings.user = {
  #   name = "<the name the employer expects>";
  #   email = "<work email>";
  # };

  # FIXME: select the work SSH key. Work forge on github.com: set
  # programs.git.settings.core.sshCommand like the personal include
  # below. Another forge host: add a programs.ssh.settings block for it.

  programs.git.includes = [
    {
      # ~/src is a plain directory on macOS, so this logical path is also
      # the physical path Git matches.
      condition = "gitdir:~/src/github.com/piotr-yuxuan/";
      contents = {
        user = {
          name = "piotr-yuxuan";
          email = "piotr-yuxuan@users.noreply.github.com";
          # FIXME: long ID of this Mac's own personal OpenPGP key (one
          # key per machine).
          signingKey = "FIXME-personal-openpgp-key-id";
        };
        commit.gpgSign = true;
        tag.gpgSign = true;
        # Personal commits stay OpenPGP-signed whatever format work uses.
        gpg.format = "openpgp";
        # Select the personal key, and do not reuse a connection
        # authenticated with the work key.
        core.sshCommand = "ssh -i ~/.ssh/piotr-yuxuan@users.noreply.github.com_ed25519 -o IdentitiesOnly=yes -o ControlPath=none";
      };
    }
  ];

  # The weekly staleness check reads the lock file of this flake. Adapt
  # the path if this directory lives elsewhere.
  launchd.agents.nix-staleness-check.config.EnvironmentVariables.NH_FLAKE = "${config.home.homeDirectory}/src/local/macOS";
}

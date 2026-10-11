# Security policy

## Supported versions

Only the latest release is supported. A fix is published as a new release, and
earlier releases are not changed.

## Report a vulnerability

Report it in private, with the form that GitHub provides:
<https://github.com/piotr-yuxuan/hardware.nix/security/advisories/new>. Do not
open a public issue for it.

Say which file or setting is concerned, what an attacker could do, and how to
reproduce it. This is a personal repository, maintained in spare time: no delay
is promised for an answer.

## What is in scope

This repository configures personal machines, and it is exported from a private
one. In scope:

- a default that weakens a machine which uses this configuration;
- a secret or personal data that the export should not have published;
- a flaw in the release pipeline or in the publication gate,
  `scripts/publish.py`.

A flaw in a package that this configuration installs belongs to that package,
or to nixpkgs.

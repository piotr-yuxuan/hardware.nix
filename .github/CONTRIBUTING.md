# Contributing

This repository is an export. The configuration is written in a private
repository, and one tool, `scripts/publish.py`, publishes each change here as a
commit that the owner signs.
[Publish to the public repository](../docs/how-to/publish-to-public.org)
describes it.

## What this means for a change

- An issue is welcome: a bug, a page that is wrong or unclear, a question.
- A pull request is read. A change that is taken is applied at the source and
  arrives here with the next export. It cannot be merged here: the gate that
  checks every push refuses a commit that the owner did not make, and the next
  export would undo the merge.
- Never put a secret, a personal value or the value of an employer in an issue
  or in a pull request.

## Check a change

[AGENTS.md](../AGENTS.md) lists the checks and the rules of style.
[Test a change](../docs/how-to/test-a-change.org) shows how to build a change
without activating it. The pipeline runs the same checks on every pull request.

## Releases

Every push to `master` that passes its checks is released with a version, a
tag and notes. [Release pipeline](../docs/reference/release-pipeline.org)
describes the pipeline and the references that a flake can follow.

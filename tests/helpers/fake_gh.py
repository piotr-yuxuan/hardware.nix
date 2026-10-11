#!/usr/bin/env python3
"""Stand in for ``gh api`` in the tests of scripts/release.py.

Every request is appended to ``calls.jsonl`` in the directory that ``FAKE_GH_HOME``
names, as ``[method, path, body]``. The reply is the entry of ``replies.json``
for ``"METHOD path"``, an empty object when it has none. A request listed
under ``"failing"`` in that file prints nothing and exits with status 1.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

home = Path(os.environ["FAKE_GH_HOME"])
command, flag, method, path, *rest = sys.argv[1:]
if (command, flag) != ("api", "--method") or rest not in ([], ["--input", "-"]):
    sys.exit(f"fake gh: unexpected arguments {sys.argv[1:]!r}")
body = json.load(sys.stdin) if rest else None
with (home / "calls.jsonl").open("a", encoding="utf-8") as calls:
    calls.write(json.dumps([method, path, body]) + "\n")
script = json.loads((home / "replies.json").read_text(encoding="utf-8"))
request = f"{method} {path}"
if request in script["failing"]:
    sys.exit(f"fake gh: {request} refused")
json.dump(script["replies"].get(request, {}), sys.stdout)

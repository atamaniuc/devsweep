#!/bin/bash
# Regenerates the "What it cleans" table in README.md from the app's own
# catalog, so the docs can never list something the app does not support.
# Usage: ./build.sh && ./scripts/update-readme-tools.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/DevSweep.app/Contents/MacOS/DevSweep"
if [[ ! -x "$APP" ]]; then
  echo "error: $APP not found; run ./build.sh first" >&2
  exit 1
fi

python3 - "$APP" <<'PY'
import pathlib
import subprocess
import sys

binary = sys.argv[1]
table = subprocess.run([binary, "--tools-md"], check=True, capture_output=True, text=True).stdout.strip()
if not table:
    sys.exit("error: --tools-md produced no output")

readme = pathlib.Path("README.md")
text = readme.read_text(encoding="utf-8")
start, end = "<!-- tools:begin -->", "<!-- tools:end -->"
try:
    begin = text.index(start) + len(start)
    finish = text.index(end)
except ValueError:
    sys.exit(f"error: README.md is missing the {start} / {end} markers")

readme.write_text(text[:begin] + "\n\n" + table + "\n\n" + text[finish:], encoding="utf-8")
print(f"README tool table updated: {table.count(chr(10)) + 1} lines")
PY

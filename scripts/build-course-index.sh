#!/usr/bin/env bash
# build-course-index.sh — Generate a lightweight module index artifact
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/artifacts"
OUT_FILE="$OUT_DIR/course-index.md"

mkdir -p "$OUT_DIR"

{
  echo "# Generated Course Index"
  echo ""
  echo "Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo ""
  echo "| Module | README | Markdown Files |"
  echo "|---|---|---|"
} > "$OUT_FILE"

for module in "$ROOT_DIR"/[0-9][0-9]-*; do
  [[ -d "$module" ]] || continue
  name="$(basename "$module")"
  readme="$name/README.md"
  artifact_link="../$readme"
  count="$(find "$module" -type f -name "*.md" | wc -l | tr -d ' ')"
  if [[ -f "$module/README.md" ]]; then
    echo "| $name | [$readme]($artifact_link) | $count |" >> "$OUT_FILE"
  else
    echo "| $name | missing | $count |" >> "$OUT_FILE"
  fi
done

echo ""
echo "Wrote $OUT_FILE"

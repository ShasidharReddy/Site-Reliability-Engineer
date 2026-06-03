#!/usr/bin/env bash
# validate-repo.sh — Validate structure, local links, and script syntax
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; }

ERRORS=0

required_paths=(
  "README.md"
  "Makefile"
  "scripts/bootstrap-lab.sh"
  "scripts/deploy-monitoring-stack.sh"
  "scripts/cleanup-lab.sh"
  "scripts/validate-repo.sh"
  "09-production-readiness/README.md"
)

for path in "${required_paths[@]}"; do
  if [[ -e "$path" ]]; then
    ok "exists: $path"
  else
    fail "missing: $path"
    (( ERRORS++ )) || true
  fi
done

echo ""
echo "Checking module READMEs..."
while IFS= read -r module; do
  if [[ -f "$module/README.md" ]]; then
    ok "$module/README.md"
  else
    fail "$module/README.md missing"
    (( ERRORS++ )) || true
  fi
done < <(find . -maxdepth 1 -type d -name "[0-9][0-9]-*" | sort)

echo ""
echo "Checking shell scripts syntax..."
while IFS= read -r script; do
  if bash -n "$script"; then
    ok "$script"
  else
    fail "syntax error: $script"
    (( ERRORS++ )) || true
  fi
done < <(find . -type f -name "*.sh" | sort)

echo ""
echo "Checking markdown links to local files..."
while IFS= read -r md; do
  md_dir="$(dirname "$md")"
  while IFS= read -r link; do
    target="${link%%#*}"
    [[ -z "$target" ]] && continue
    [[ "$target" =~ ^https?:// ]] && continue
    [[ "$target" =~ ^mailto: ]] && continue
    [[ "$target" =~ ^# ]] && continue

    if [[ "$target" = /* ]]; then
      resolved=".$target"
    else
      resolved="$md_dir/$target"
    fi

    if [[ ! -e "$resolved" ]]; then
      fail "$md -> missing link target: $target"
      (( ERRORS++ )) || true
    fi
  done < <(grep -oE '\[[^]]+\]\(([^)]+)\)' "$md" | sed -E 's/.*\(([^)]+)\)/\1/')
done < <(find . -type f -name "*.md" | sort)

echo ""
if (( ERRORS > 0 )); then
  fail "validation failed with $ERRORS issue(s)"
  exit 1
fi

ok "repository validation passed"


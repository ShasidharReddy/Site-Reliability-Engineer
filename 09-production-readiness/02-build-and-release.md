# 02 — Build and Release

This repository is a docs-and-operations platform. "Build" means generating validated artifacts and enforcing quality gates.

## Build Pipeline

```bash
make build
```

Build output:
- `artifacts/course-index.md` — generated index of module coverage.

## Quality Gates

```bash
make validate
```

Validation checks:
- required files and module entrypoints
- shell script syntax (`bash -n`)
- local markdown link integrity

## CI Release Gate

GitHub Actions workflow (`.github/workflows/ci.yml`) runs:

```bash
make ci
```

`make ci` runs both build and validation. Any failure blocks merge.

## Suggested Release Process

1. Open PR with module/script changes.
2. Ensure CI passes.
3. Tag stable milestone:

```bash
git tag -a v1.x.y -m "SRE course release v1.x.y"
git push origin v1.x.y
```

4. Add release notes with changed labs, scripts, and operational impacts.


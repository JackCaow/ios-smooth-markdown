#!/usr/bin/env bash
# Vendors a smooth-rust-core snapshot into rust-core/, or verifies the current one.
#   tools/sync-rust-core.sh <tag-or-commit>   replace rust-core/ with that upstream ref
#   tools/sync-rust-core.sh --verify          check rust-core/ matches rust-core/UPSTREAM
set -euo pipefail
repository="https://github.com/JackCaow/smooth-rust-core.git"
root="$(cd "$(dirname "$0")/.." && pwd)"
target="$root/rust-core"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [[ "${1:-}" == "--verify" ]]; then
  commit="$(awk '$1 == "commit" { print $2 }' "$target/UPSTREAM")"
  git clone -q "$repository" "$tmp/core"
  git -C "$tmp/core" checkout -q "$commit"
  diff -r -q -x .git -x .github -x tools -x target -x UPSTREAM -x .DS_Store "$tmp/core" "$target"
  (cd "$target" && shasum -a 256 --check --quiet SOURCE.sha256)
  echo "rust-core matches smooth-rust-core $commit"
  exit 0
fi

ref="${1:?usage: tools/sync-rust-core.sh <tag-or-commit> | --verify}"
git clone -q "$repository" "$tmp/core"
git -C "$tmp/core" checkout -q "$ref"
commit="$(git -C "$tmp/core" rev-parse HEAD)"
(cd "$tmp/core" && shasum -a 256 --check --quiet SOURCE.sha256)
rsync -a --delete --exclude .git --exclude .github --exclude tools --exclude target --exclude .DS_Store "$tmp/core/" "$target/"
printf 'repository %s\nref %s\ncommit %s\n' "$repository" "$ref" "$commit" > "$target/UPSTREAM"
echo "rust-core synced to smooth-rust-core $ref ($commit)"

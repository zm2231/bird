#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(node -p "require('./package.json').version")"
SHA="$(git rev-parse --short=8 HEAD)"
IDENTITY="${BIRD_CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Developer ID Application:/ {print $2; exit}')}"
NOTARY_PROFILE="${BIRD_NOTARY_PROFILE:?BIRD_NOTARY_PROFILE must name a notarytool keychain profile}"
OUT="$ROOT/release"
STAGE="$OUT/stage"

[ -n "$IDENTITY" ] || { echo "error: no Developer ID Application identity found" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "error: worktree is dirty" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$STAGE"

for target in arm64 x64; do
	BIRD_VERSION="$VERSION" BIRD_GIT_SHA="$SHA" bun build --compile --minify --env='BIRD_*' \
		--target="bun-darwin-$target" src/cli.ts --outfile "$OUT/bird-$target"
done
lipo -create "$OUT/bird-arm64" "$OUT/bird-x64" -output "$STAGE/bird"
rm "$OUT/bird-arm64" "$OUT/bird-x64"

codesign --force --timestamp --options runtime \
	--entitlements "$ROOT/packaging/entitlements.plist" \
	--sign "$IDENTITY" "$STAGE/bird"
codesign --verify --strict --verbose=2 "$STAGE/bird"

ditto -c -k "$STAGE/bird" "$OUT/notary.zip"
xcrun notarytool submit "$OUT/notary.zip" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 20m
rm "$OUT/notary.zip"

ARCHIVE="$OUT/bird-macos-universal-v$VERSION.tar.gz"
tar -C "$STAGE" -czf "$ARCHIVE" bird
shasum -a 256 "$ARCHIVE" | tee "$ARCHIVE.sha256"

#!/usr/bin/env bash
# Writes dist/eave.rb for a released dmg, with the checksum taken from the file
# itself. The result is what goes into abcdlsj/homebrew-tap's Casks/.
#
#   scripts/write-cask.sh 0.1.0 dist/eave_0.1.0_darwin_universal.dmg
set -euo pipefail

VERSION="${1:-}"
DMG="${2:-}"
if [[ -z "$VERSION" || -z "$DMG" ]]; then
    echo "usage: scripts/write-cask.sh <version> <dmg>" >&2
    exit 1
fi
VERSION="${VERSION#v}"
[[ -f "$DMG" ]] || { echo "missing ${DMG}" >&2; exit 1; }

OUT="${EAVE_CASK_OUT:-dist/eave.rb}"
if command -v shasum >/dev/null; then
    SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
else
    SHA="$(sha256sum "$DMG" | cut -d' ' -f1)"
fi

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<EOF
# typed: strict
# frozen_string_literal: true

cask "eave" do
  version "${VERSION}"

  sha256 "${SHA}"

  url "https://github.com/abcdlsj/eave/releases/download/v#{version}/eave_#{version}_darwin_universal.dmg"
  name "Eave"
  desc "Native macOS menu bar manager with Notch integration"
  homepage "https://github.com/abcdlsj/eave"

  depends_on macos: :sequoia

  app "Eave.app"

  caveats <<~EOS
    Eave manages other apps' menu bar items, so it needs Accessibility access:
    System Settings → Privacy & Security → Accessibility → enable Eave.
  EOS

  zap trash: [
    "~/Library/Preferences/com.abcdlsj.eave.plist",
    "~/Library/Caches/com.abcdlsj.eave",
    "~/Library/HTTPStorages/com.abcdlsj.eave",
    "~/Library/Saved Application State/com.abcdlsj.eave.savedState",
  ]
end
EOF

cat "$OUT"
command -v ruby >/dev/null && ruby -c "$OUT"

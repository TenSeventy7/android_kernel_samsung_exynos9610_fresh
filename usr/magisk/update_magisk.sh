#!/usr/bin/env bash

set -eu

# [
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

MAGISK_CURRENT_VERSION="$(cat "$DIR/magisk_version" 2>/dev/null || echo -n 'none')"
MAGISK_BRANCH="$1"
# ]

if [[ $MAGISK_BRANCH == local ]]; then
	MAGISK_VERSION="local"
	MAGISK_LINK="https://gitlab.com/TenSeventy7/magisk-files/raw/main/app-debug.apk"
else
	MAGISK_VERSION="$(curl -s "https://raw.githubusercontent.com/topjohnwu/magisk-files/master/$MAGISK_BRANCH.json" | jq '.magisk.version' | cut -d '"' -f 2)"
	MAGISK_LINK="$(curl -s "https://raw.githubusercontent.com/topjohnwu/magisk-files/master/$MAGISK_BRANCH.json" | jq '.magisk.link' | cut -d '"' -f 2)"
fi

if [[ $MAGISK_CURRENT_VERSION != "$MAGISK_VERSION" ]] || [[ $MAGISK_BRANCH == local || $MAGISK_BRANCH == canary ]]; then
	echo "Updating Magisk from $MAGISK_CURRENT_VERSION to $MAGISK_VERSION"
	curl -s --output "$DIR/magisk.zip" -L "$MAGISK_LINK"

	grep -q 'Not Found' "$DIR/magisk.zip" \
		&& curl -s --output "$DIR/magisk.zip" -L "${MAGISK_LINK%.apk}.zip"

	7z e -so "$DIR/magisk.zip" lib/arm64-v8a/libmagiskinit.so > "$DIR/magiskinit"
	7z e -so "$DIR/magisk.zip" lib/arm64-v8a/libmagisk.so     > "$DIR/magisk"
	7z e -so "$DIR/magisk.zip" lib/arm64-v8a/libinit-ld.so    > "$DIR/init-ld"
	7z e -so "$DIR/magisk.zip" assets/stub.apk                > "$DIR/stub"
	xz --force --check=crc32 "$DIR/magisk" "$DIR/init-ld" "$DIR/stub"

	echo -n "$MAGISK_VERSION" > "$DIR/magisk_version"
	rm "$DIR/magisk.zip"
else
	echo "Nothing to be done: Magisk version $MAGISK_VERSION"
fi

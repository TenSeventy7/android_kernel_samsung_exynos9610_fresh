#!/usr/bin/env bash

set -eu

# [
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

MAGISK_CURRENT_VERSION="$(cat "$DIR/magisk_version" 2>/dev/null || echo -n 'none')"
MAGISK_BRANCH="$1"
# ]

case "$MAGISK_BRANCH" in
alpha|kitsune|local) REPOSITORY="https://raw.githubusercontent.com/FreshROMs/android_kernel_samsung_exynos9610_mint/magisk-files" ;;
stable|canary) REPOSITORY="https://raw.githubusercontent.com/topjohnwu/magisk-files/master" ;;
esac

MAGISK_VERSION="$(curl -s "$REPOSITORY/$MAGISK_BRANCH.json" | jq '.magisk.version' | cut -d '"' -f 2)"
MAGISK_LINK="$(curl -s "$REPOSITORY/$MAGISK_BRANCH.json" | jq '.magisk.link' | cut -d '"' -f 2)"

if [[ $MAGISK_CURRENT_VERSION != "$MAGISK_VERSION" ]] || [[ $MAGISK_BRANCH == canary ]]; then
	echo "Updating Magisk from $MAGISK_CURRENT_VERSION to $MAGISK_VERSION"
	curl -s --output "$DIR/magisk.zip" -L "$MAGISK_LINK"
	grep -q 'Not Found' "$DIR/magisk.zip" \
		&& curl -s --output "$DIR/magisk.zip" -L "${MAGISK_LINK%.apk}.zip"

	if unzip -l "$DIR/magisk.zip" | grep -q 'libmagisk64.so'; then
		7z e -so "$DIR/magisk.zip" lib/armeabi-v7a/libmagisk32.so > "$DIR/magisk32"
		7z e -so "$DIR/magisk.zip" lib/arm64-v8a/libmagisk64.so > "$DIR/magisk64"
		xz --force --check=crc32 "$DIR/magisk32" "$DIR/magisk64"

		cp "$DIR/initramfs_list.base" "$DIR/initramfs_list"
		sed -i '/magisk.xz/d' "$DIR/initramfs_list"
		sed -i '/init-ld/d' "$DIR/initramfs_list"
	else
		7z e -so "$DIR/magisk.zip" lib/arm64-v8a/libmagisk.so > "$DIR/magisk"
		7z e -so "$DIR/magisk.zip" lib/arm64-v8a/libinit-ld.so > "$DIR/init-ld"
		xz --force --check=crc32 "$DIR/magisk" "$DIR/init-ld"

		cp "$DIR/initramfs_list.base" "$DIR/initramfs_list"
		sed -i '/magisk32.xz/d' "$DIR/initramfs_list"
		sed -i '/magisk64.xz/d' "$DIR/initramfs_list"
	fi
	7z e -so "$DIR/magisk.zip" lib/arm64-v8a/libmagiskinit.so > "$DIR/magiskinit"
	7z e -so "$DIR/magisk.zip" assets/stub.apk > "$DIR/stub"
	xz --force --check=crc32 "$DIR/stub"

	echo -n "$MAGISK_VERSION" > "$DIR/magisk_version"
	rm "$DIR/magisk.zip"
else
	echo "Nothing to be done: Magisk version $MAGISK_VERSION"
fi

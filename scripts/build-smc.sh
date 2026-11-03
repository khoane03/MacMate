#!/bin/bash
set -euo pipefail

SOURCE_DIR="$SRCROOT/ThirdParty/MacMonitor-SMC"
RESOURCE_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
OUTPUT="$RESOURCE_DIR/smc"
BUILT_HELPER="$DERIVED_FILE_DIR/smc-universal"

mkdir -p "$RESOURCE_DIR/ThirdParty"
xcrun --sdk macosx clang \
    -Wall \
    -Wextra \
    -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
    -arch arm64 \
    -arch x86_64 \
    -I "$SOURCE_DIR" \
    "$SOURCE_DIR/SMC.c" \
    "$SOURCE_DIR/smc_cli.c" \
    -framework IOKit \
    -o "$BUILT_HELPER"
install -m 755 "$BUILT_HELPER" "$OUTPUT"
cp "$SOURCE_DIR/LICENSE" "$RESOURCE_DIR/ThirdParty/MacMonitor-SMC-LICENSE.txt"

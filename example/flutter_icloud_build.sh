#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# flutter_icloud_build.sh — Build & run Flutter iOS from iCloud Drive
#
# iCloud Drive adds extended attributes (com.apple.FinderInfo, etc.) to all
# files which makes codesign fail with "resource fork, Finder information,
# or similar detritus not allowed". These attributes CANNOT be removed on
# iCloud Drive because fileproviderd immediately re-applies them.
#
# This script works around the issue by:
#   1. rsync-ing the project to a local (non-iCloud) temp directory
#   2. Running 'flutter run' (or any flutter command) from there
#
# Usage:
#   ./flutter_icloud_build.sh                    # default: flutter run
#   ./flutter_icloud_build.sh run -d iPhone       # flutter run -d iPhone
#   ./flutter_icloud_build.sh build ios            # flutter build ios
#   ./flutter_icloud_build.sh run --release        # flutter run --release
#
# The script auto-detects the project root and syncs back pub artifacts.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

# Detect if this is a sub-project (example/) with a path dependency on parent
PARENT_PUBSPEC="$PROJECT_DIR/../pubspec.yaml"
if [ -f "$PARENT_PUBSPEC" ]; then
  # Sync the parent package too (for path: ../ dependencies)
  PARENT_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
  PARENT_NAME="$(basename "$PARENT_DIR")"
  BUILD_ROOT="/tmp/flutter_icloud_build_${PARENT_NAME}"
  BUILD_DIR="$BUILD_ROOT/$PROJECT_NAME"
else
  BUILD_ROOT="/tmp/flutter_icloud_build_${PROJECT_NAME}"
  BUILD_DIR="$BUILD_ROOT"
  PARENT_DIR=""
fi

# ── Colors ────────────────────────────────────────────────────────────────────
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Flutter iCloud Build Wrapper${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"

# ── Step 1: Sync project to /tmp ──────────────────────────────────────────────
echo -e "${YELLOW}▸ Syncing project to ${BUILD_DIR}${NC}"

# If there is a parent package (path dependency), sync it first
if [ -n "${PARENT_DIR:-}" ]; then
  echo -e "${YELLOW}  (including parent package: ${PARENT_NAME})${NC}"
  mkdir -p "$BUILD_ROOT"
  rsync -a --delete \
    --exclude 'build/' \
    --exclude 'example/build/' \
    --exclude '.dart_tool/' \
    --exclude 'example/.dart_tool/' \
    --exclude '.flutter-plugins-dependencies' \
    --exclude '*.nosync' \
    --exclude '*.nosync/' \
    --exclude '.DS_Store' \
    --exclude 'docs_html/' \
    --exclude 'doc/' \
    --exclude 'docs/' \
    "$PARENT_DIR/" "$BUILD_ROOT/"
else
  mkdir -p "$BUILD_DIR"
  rsync -a --delete \
    --exclude 'build/' \
    --exclude '.dart_tool/' \
    --exclude '.flutter-plugins-dependencies' \
    --exclude '*.nosync' \
    --exclude '.DS_Store' \
    "$PROJECT_DIR/" "$BUILD_DIR/"
fi

echo -e "${GREEN}  ✓ Project synced${NC}"

# ── Step 2: Run flutter command ───────────────────────────────────────────────
FLUTTER_CMD="${1:-run}"
shift || true
FLUTTER_ARGS=("$@")

echo -e "${YELLOW}▸ Running: flutter $FLUTTER_CMD ${FLUTTER_ARGS[*]}${NC}"
echo -e "${YELLOW}  in: ${BUILD_DIR}${NC}"
echo ""

cd "$BUILD_DIR"

# Ensure deps are up to date in the temp copy
flutter pub get --no-example 2>/dev/null || true

# Run the actual flutter command
flutter "$FLUTTER_CMD" "${FLUTTER_ARGS[@]}"

# ── Step 3: Sync back any generated files ─────────────────────────────────────
echo ""
echo -e "${YELLOW}▸ Syncing generated files back to iCloud project${NC}"

# Sync back pubspec.lock, generated files, etc (but NOT build artifacts)
rsync -a \
  --include 'pubspec.lock' \
  --include '.dart_tool/***' \
  --include 'ios/Podfile.lock' \
  --include 'ios/Pods/***' \
  --include 'ios/Flutter/Generated.xcconfig' \
  --include 'ios/Flutter/flutter_export_environment.sh' \
  --include 'macos/Flutter/GeneratedPluginRegistrant.swift' \
  --include '.flutter-plugins' \
  --include '.flutter-plugins-dependencies' \
  --exclude '*' \
  "$BUILD_DIR/" "$PROJECT_DIR/" 2>/dev/null || true

echo -e "${GREEN}  ✓ Done${NC}"

#!/bin/bash

# Build script
# 1. Syncs/Checks version numbers against Git tags
# 2. Generates a production-ready ZIP in dist/archives
#
# Usage:
#   bash build.sh              # Checks version, builds zip
#   bash build.sh --fix        # Updates file versions to match Git tag, then builds
#   bash build.sh --dev        # Skips version check (for development), builds zip

set -e

# Configuration (supplied via environment)
PLUGIN_SLUG="${PLUGIN_SLUG:?PLUGIN_SLUG must be set}"
MAIN_FILE="${MAIN_FILE:?MAIN_FILE must be set}"
README_FILE="readme.txt"
DIST_DIR="dist/archives"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Starting Build Process for ${PLUGIN_SLUG}...${NC}"

# ==============================================================================
# Version Synchronization
# ==============================================================================

if [ -n "$GIT_TAG" ]; then
	LATEST_TAG="$GIT_TAG"
	echo -e "${BLUE}ℹ️  Using provided GIT_TAG: ${LATEST_TAG}${NC}"
else
	LATEST_TAG=$(git tag --list --sort=-version:refname 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' | head -n 1)
fi

if [ -z "$LATEST_TAG" ]; then
	echo -e "${YELLOW}⚠️  No Git tags found. Skipping version sync.${NC}"
	VERSION=$(grep -E -o "Version: *[0-9A-Za-z.-]+" "$MAIN_FILE" | head -n1 | sed -E "s/Version: *//")
else
	CLEAN_VERSION="${LATEST_TAG#v}"
	VERSION="$CLEAN_VERSION"

	CURRENT_PLUGIN_VERSION=$(grep -E -o "Version: *[0-9A-Za-z.-]+" "$MAIN_FILE" | head -n1 | sed -E "s/Version: *//")
	
	HAS_README=0
	if [ -f "$README_FILE" ]; then
		HAS_README=1
		CURRENT_README_VERSION=$(grep -E -o "Stable tag: *[0-9A-Za-z.-]+" "$README_FILE" | head -n1 | sed -E "s/Stable tag: *//")
	fi

	TAG_BASE_VERSION=$(echo "$CLEAN_VERSION" | sed -E 's/(-|\.pre|\.beta|\.rc).*//')

	if [ "$1" == "--dev" ]; then
		echo -e "${YELLOW}🔧 Development mode: Skipping version check.${NC}"
		VERSION="$CURRENT_PLUGIN_VERSION"
	elif [ "$1" == "--fix" ]; then
		NEEDS_UPDATE=0
		if [ "$CURRENT_PLUGIN_VERSION" != "$CLEAN_VERSION" ]; then
			NEEDS_UPDATE=1
		fi
		if [ "$HAS_README" = "1" ] && [ "$CURRENT_README_VERSION" != "$CLEAN_VERSION" ]; then
			NEEDS_UPDATE=1
		fi
		if [ "$HAS_README" = "1" ] && grep -q "^= Unreleased =$" "$README_FILE"; then
			NEEDS_UPDATE=1
		fi

		if [ "$NEEDS_UPDATE" = "1" ]; then
			echo -e "${BLUE}📦 Updating file versions to match tag: ${CLEAN_VERSION}...${NC}"
			sed -i.bak -E "s/(Version: *)[0-9A-Za-z.-]+/\1$CLEAN_VERSION/" "$MAIN_FILE"
			
			if [ "$HAS_README" = "1" ]; then
				sed -i.bak -E "s/(Stable tag: *)[0-9A-Za-z.-]+/\1$CLEAN_VERSION/" "$README_FILE"
				sed -i.bak -E "s/^= Unreleased =$/= $CLEAN_VERSION =/" "$README_FILE"
				rm -f "$README_FILE.bak"
			fi
			rm -f "$MAIN_FILE.bak"
			echo -e "${GREEN}✅ Files updated.${NC}"
		else
			echo -e "${GREEN}✅ Versions already match (${CLEAN_VERSION}).${NC}"
		fi
	else
		MISMATCH=0
		if [ "$CURRENT_PLUGIN_VERSION" != "$CLEAN_VERSION" ] && [ "$CURRENT_PLUGIN_VERSION" != "$TAG_BASE_VERSION" ]; then
			MISMATCH=1
		fi
		if [ "$HAS_README" = "1" ] && [ "$CURRENT_README_VERSION" != "$CLEAN_VERSION" ] && [ "$CURRENT_README_VERSION" != "$TAG_BASE_VERSION" ]; then
			MISMATCH=1
		fi

		if [ "$MISMATCH" = "1" ]; then
			echo -e "${RED}❌ Version Mismatch!${NC}"
			echo "   Git Tag: $LATEST_TAG"
			echo "   $MAIN_FILE:        $CURRENT_PLUGIN_VERSION"
			if [ "$HAS_README" = "1" ]; then
				echo "   $README_FILE:      $CURRENT_README_VERSION"
			fi
			echo "   Run 'bash build.sh --fix' to sync them."
			exit 1
		fi

		if [ "$LATEST_TAG" != "$TAG_BASE_VERSION" ]; then
			echo -e "${GREEN}✅ Prerelease tag detected ($LATEST_TAG) - using file version ($CURRENT_PLUGIN_VERSION) for build.${NC}"
			VERSION="$CURRENT_PLUGIN_VERSION"
		else
			echo -e "${GREEN}✅ Versions match ($LATEST_TAG).${NC}"
		fi
	fi
fi

echo -e "📦 Build Version: ${YELLOW}${VERSION}${NC}"

if [ -f "composer.json" ]; then
	echo -e "${BLUE}📦 Installing production dependencies...${NC}"
	composer install --no-dev --prefer-dist --optimize-autoloader --quiet
fi

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/${PLUGIN_SLUG}"*.zip 2>/dev/null || true

if ! command -v wp &>/dev/null; then
	echo -e "${RED}❌ WP-CLI not found. Install it: https://wp-cli.org/#installing${NC}"
	exit 1
fi
if ! wp help dist-archive &>/dev/null; then
	echo -e "${RED}❌ The dist-archive command is missing. Install the version CI uses:${NC}"
	echo "   wp package install wp-cli/dist-archive-command:v3.1.0"
	exit 1
fi

# dist-archive reads the plugin header and .distignore from this directory, so no WordPress install is needed.
echo -e "${BLUE}🚀 Running dist-archive...${NC}"
wp dist-archive . "$DIST_DIR" --plugin-dirname="${PLUGIN_SLUG}" --create-target-dir --format=zip --allow-root

if ls "$DIST_DIR/${PLUGIN_SLUG}"*.zip 1>/dev/null 2>&1; then
	echo -e "${GREEN}✅ Build Complete!${NC}"
	echo -e "📁 Archives located in: ${YELLOW}${DIST_DIR}/${NC}"
	ls -lh "$DIST_DIR"
else
	echo -e "${RED}❌ Build Failed: No zip file created.${NC}"
	exit 1
fi

EXTRACTED_DIR="dist/extracted"
echo -e "${BLUE}📂 Extracting distribution to ${EXTRACTED_DIR}...${NC}"

find "$EXTRACTED_DIR" -mindepth 1 -delete 2>/dev/null || true
mkdir -p "$EXTRACTED_DIR"
cd "$EXTRACTED_DIR"
unzip -q "../archives/${PLUGIN_SLUG}.${VERSION}.zip" -d temp 2>/dev/null || unzip -q "../archives/"*.zip -d temp 2>/dev/null
mv temp/*/* . 2>/dev/null || mv temp/* . 2>/dev/null || true
rm -rf temp
cd ../..

echo -e "${GREEN}✅ Distribution extracted.${NC}"

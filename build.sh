#!/bin/bash

set -e

PROJECT="Calendar.xcodeproj"
SCHEME="Calendar"
DESTINATION="platform=macOS"
BUILD_DIR="build"

# Check if Xcode.app exists
if [[ ! -d "/Applications/Xcode.app" ]]; then
  echo "❌ Error: Xcode.app not found in /Applications/"
  echo "   Please install Xcode from the Mac App Store first."
  exit 1
fi

# Check xcode-select path
SELECTED=$(xcode-select -p 2>/dev/null || true)
if [[ "$SELECTED" != "/Applications/Xcode.app/Contents/Developer" ]]; then
  echo "⚙️  Setting xcode-select to Xcode.app..."
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
fi

# Accept license if needed
if ! xcodebuild -license check 2>/dev/null; then
  echo "📝 Accepting Xcode license..."
  sudo xcodebuild -license accept
fi

# Verify project and scheme
if [[ ! -f "$PROJECT" ]]; then
  echo "❌ Error: Project file '$PROJECT' not found."
  exit 1
fi

echo "🔍 Checking available schemes..."
if ! xcodebuild -project "$PROJECT" -list | grep -q "Schemes:"; then
  echo "❌ Error: Could not list schemes — check project integrity."
  exit 1
fi

# Build
echo "🚀 Building '$SCHEME' for $DESTINATION..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -derivedDataPath "$BUILD_DIR" build

# Success
echo "✅ Build succeeded! Artifacts are in: $BUILD_DIR/Build/Products/"

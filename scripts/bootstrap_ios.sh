#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is not installed. Install it with: brew install xcodegen"
  exit 1
fi

xcodegen generate

# XcodeGen 2.45 generates objectVersion 77 by default, which Xcode 15.4 cannot open.
# Normalize the generated project format so local development can stay on Xcode 15.4.
perl -0pi -e 's/objectVersion = 77;/objectVersion = 60;/g; s/preferredProjectObjectVersion = 77;/preferredProjectObjectVersion = 60;/g' Snapuary.xcodeproj/project.pbxproj

echo "Generated Snapuary.xcodeproj"

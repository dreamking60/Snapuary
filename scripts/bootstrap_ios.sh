#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is not installed. Install it with: brew install xcodegen"
  exit 1
fi

xcodegen generate

echo "Generated Snapuary.xcodeproj"

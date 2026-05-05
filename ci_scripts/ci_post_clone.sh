#!/bin/sh

set -eu

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"

cd "$REPO_ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing XcodeGen with Homebrew..."
  brew install xcodegen
fi

echo "Generating Snapuary.xcodeproj from project.yml..."
xcodegen generate

if [ ! -d "Snapuary.xcodeproj" ]; then
  echo "error: Snapuary.xcodeproj was not generated"
  exit 1
fi

echo "Generated Snapuary.xcodeproj"

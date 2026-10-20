#!/bin/sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export JAVA_HOME="$PROJECT_DIR/.tools/jdk-17.0.20.1+1/Contents/Home"
export ANDROID_HOME="$PROJECT_DIR/.tools/android-sdk"
cd "$PROJECT_DIR"
exec "$PROJECT_DIR/.tools/flutter/bin/flutter" "$@"

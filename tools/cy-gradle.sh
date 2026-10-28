#!/usr/bin/env bash
# Runs Gradle in the CleanYourTV fork with the toolchain that brew + sdkmanager installed.
set -euo pipefail
# macOS + Homebrew defaults; set JAVA_HOME (JDK 17) and ANDROID_HOME yourself elsewhere.
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}
export ANDROID_HOME=${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}
export ANDROID_SDK_ROOT=${ANDROID_HOME}
cd "$(dirname "$0")/../vendor/cleanyourtv/launcher"
exec ./gradlew --no-daemon "$@"

#!/bin/bash
# MobSF / Release APK build
flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/debug-info

---
name: build-unsigned-ipa
description: Build an unsigned IPA from the Bittern Xcode project. Use this skill whenever the user asks to build, compile, export, or package an IPA, make an unsigned app, install on device without signing, or mentions exporting the app. Always trigger on keywords like "编译", "打包", "IPA", "导出", "build", "export", "package", "unsigned".
---

# Build Unsigned IPA

Build an unsigned `.ipa` file from the Bittern Xcode project for sideloading or testing.

## Prerequisites

- iOS device support must be installed for the deployment target version (check with `xcodebuild -showBuildSettings` or install via Xcode → Settings → Components)
- The project file is at `Bittern.xcodeproj`, scheme is `Bittern`

## Build Steps

Run each step in order. The project root is the current working directory.

### 1. Archive with code signing disabled

```bash
rm -rf build/Bittern.xcarchive

xcodebuild archive \
  -project Bittern.xcodeproj \
  -scheme Bittern \
  -destination 'generic/platform=iOS' \
  -archivePath build/Bittern.xcarchive \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

If the archive step fails with a destination error (e.g. "iOS X.Y is not installed"), tell the user to install the matching iOS platform support in Xcode → Settings → Components.

### 2. Package into IPA

Once the archive succeeds, package the `.app` into an unsigned IPA:

```bash
cd build
rm -rf Payload
mkdir -p Payload
cp -R Bittern.xcarchive/Products/Applications/Bittern.app Payload/
zip -r -q Bittern.ipa Payload
rm -rf Payload
```

The output is `build/Bittern.ipa`, an unsigned IPA ready for sideloading.

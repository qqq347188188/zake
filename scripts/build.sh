#!/bin/bash
# 本地构建（macOS，需要 Xcode + xcodegen）
set -e
cd "$(dirname "$0")/.."

rm -rf build Payload
mkdir -p build

echo "==> 编译 dumpdecrypted.dylib"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun clang -target arm64-apple-ios16.0 -isysroot "$SDK" \
  -dynamiclib -fPIC -o build/dumpdecrypted.dylib \
  src/dumpdecrypted/dumpdecrypted.c
codesign -s - --entitlements src/dumpdecrypted/dylib_entitlements.plist \
  build/dumpdecrypted.dylib

echo "==> 生成 Xcode 工程"
xcodegen generate --spec project.yml --project Decryptor.xcodeproj

echo "==> 构建 App"
xcodebuild -project Decryptor.xcodeproj -scheme Decryptor \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" ARCHS=arm64 \
  build CONFIGURATION_BUILD_DIR=$PWD/build/app

echo "==> 嵌入 dylib 并签名"
cp build/dumpdecrypted.dylib build/app/Decryptor.app/dumpdecrypted.dylib
codesign -s - --entitlements src/host/entitlements.plist --deep build/app/Decryptor.app

echo "==> 打包 IPA"
mkdir -p Payload
cp -r build/app/Decryptor.app Payload/
zip -r Decryptor.ipa Payload
rm -rf Payload

echo "完成：Decryptor.ipa"

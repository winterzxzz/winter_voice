#!/bin/sh
set -eu

expected_identifier=com.winterzxzz.WinterVoice
source_plist=WinterVoice/Resources/Info.plist

source_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_plist")
if [ "$source_identifier" != '$(PRODUCT_BUNDLE_IDENTIFIER)' ]; then
    echo "Expected source CFBundleIdentifier to inherit PRODUCT_BUNDLE_IDENTIFIER; found: $source_identifier" >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    exit 0
fi

app_bundle=$1
built_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_bundle/Contents/Info.plist")
if [ "$built_identifier" != "$expected_identifier" ]; then
    echo "Expected built CFBundleIdentifier $expected_identifier; found: $built_identifier" >&2
    exit 1
fi

signature_identifier=$(codesign -d --verbose=2 "$app_bundle" 2>&1 | sed -n 's/^Identifier=//p')
if [ "$signature_identifier" != "$expected_identifier" ]; then
    echo "Expected signature identifier $expected_identifier; found: $signature_identifier" >&2
    exit 1
fi

echo "Bundle identity verified: $expected_identifier"

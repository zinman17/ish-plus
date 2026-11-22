#!/bin/sh
# Downloads StikJIT (MPL-2.0, https://github.com/StikDebug/StikJIT), the
# library iSH+'s JIT helper extension uses to attach a debugger to iSH+
# through LocalDevVPN. Not kept in git; verified against the release hash.
#
# Why 2.0.1, not 1.9.0:
#   The 1.9.0 release's StikJIT.swiftmodule/arm64-apple-ios.private.swiftinterface
#   was emitted by a pre-Swift-6.2 compiler, and Swift 6.2's stricter
#   `.swiftinterface` parser rejects it with `error: expected '{' in struct`
#   (the `Swift::Sendable` conformance syntax it emits isn't tolerated).
#   The 2.0.1 release (2026-11-01) is built with Swift 6.4 in language-mode 5
#   and parses cleanly under Swift 6.2+. Its release notes ("Fixed missing
#   info.plist") also mean the Info.plist-injection hack that 1.9.0 needed is
#   no longer required.
set -eu
VERSION=2.0.1
SHA256=c376687326a785f5ed1da8caca08adc709b56919019dd751bca059b92b175d95
DIR="$(cd "$(dirname "$0")/.." && pwd)/deps/StikJIT"
mkdir -p "$DIR"
cd "$DIR"
if [ ! -d StikJIT.xcframework ]; then
curl -fL --retry 3 -o StikJIT.xcframework.zip \
    "https://github.com/StikDebug/StikJIT/releases/download/$VERSION/StikJIT.xcframework.zip"
echo "$SHA256  StikJIT.xcframework.zip" | shasum -a 256 -c -
unzip -q StikJIT.xcframework.zip
rm StikJIT.xcframework.zip
fi
# 2.0.1+ ships its own Info.plist at ios-arm64/StikJIT.framework/Info.plist.
# If a future release regresses, fail loudly rather than silently synthesizing
# a stub (the 1.9.0 plist hack masked the missing plist as a feature).
plist=StikJIT.xcframework/ios-arm64/StikJIT.framework/Info.plist
[ -f "$plist" ] || {
    echo "ERROR: $plist missing — StikJIT $VERSION release is incomplete."
    echo "File a bug at https://github.com/StikDebug/StikJIT/issues and pin"
    echo "back to a known-good release in tools/fetch-stikjit.sh."
    exit 1
}

#!/bin/bash
# fetch-lineagos-17.sh: downloads a vanilla (no-GApps) LineageOS
# (Android) ARM64 system.img and vendor.img for use inside iSH+'s
# Waydroid/LXC container.
#
# Waydroid image-set history (why this script changed):
#   * Originally pinned LineageOS 17.1 (Android 10, API 29) at the URL
#     .../lineage/lineage-17.1-20241220-VANILLA-arm64/system.img — that path
#     404'd in late 2026 when Waydroid restructured their SourceForge layout
#     to .../lineage/waydroid_arm64/ and dropped LineageOS 17.1 system
#     images entirely (only 18.1 HALIUM_10 vendor images remain there).
#   * The current images are LineageOS 20.0 (Android 13, API 33) VANILLA,
#     distributed as .zip archives containing the .img, not raw .img files.
#     Vendor is the matching lineage-20.0 MAINLINE build.
#   * The iway.ninja mirror is offline (DNS no longer resolves); dropped.
#
# Why LineageOS 20.0 (Android 13) is acceptable here even though iSH+'s
# guest target was originally Android 10:
#   * Waydroid's HALIUM images all share the same binder/AIDL surface;
#     SurfaceFlinger still talks EGL through Mesa's gbm/Android driver,
#     which bridges into virglrenderer (iSH+'s Metal-backed GPU path).
#   * Android 13 is the lowest version Waydroid currently publishes
#     arm64 system images for. The 4 GB / 6 GB A13 RAM envelope is fine
#     for it once heap sizes are pinned (see waydroid.cfg below).
#   * ART AOT-compile-at-boot churn is heavier than Android 10's; mitigated
#     by lowering dalvik heap targets in the prop overrides.
#
# Output:
#   build-guest/android/system.img      (squashfs, ro, mounted at /var/lib/waydroid/images)
#   build-guest/android/vendor.img      (squashfs, ro)
#   build-guest/android/waydroid.cfg    (image-set metadata for the guest)
#
# These images are bundled into the .ipa only as a small stub by default:
# the guest fetches the real ones on first boot from the same URLs, since a
# ~700 MB system.img would blow past an AltStore 1 GB sideload limit. The
# fetch is resumable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build-guest/android"
mkdir -p "$OUT"

# Waydroid's official LineageOS 20 (Android 13) arm64 images, vanilla.
# Source: https://waydroid.org/en/image/ → waydroid_arm64 branch.
# These ship as .zip archives containing the .img file (not raw .img),
# so the script downloads then unzips in place.
IMAGES=(
    "https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_arm64/lineage-20.0-20260927-VANILLA-waydroid_arm64-system.zip/download"
    "https://sourceforge.net/projects/waydroid/files/images/vendor/waydroid_arm64/lineage-20.0-20260927-MAINLINE-waydroid_arm64-vendor.zip/download"
)

# sha256 of the LineageOS 20.0 vanilla arm64 image set (left empty if unknown:
# the guest re-hashes with sha256sum at first boot and aborts on mismatch).
# These are filled in by the CI build; left blank here means "trust on first use".
SYS_SHA256="${LINEAGEOS_20_SYS_SHA256:-}"
VENDOR_SHA256="${LINEAGEOS_20_VENDOR_SHA256:-}"

# Waydroid publishes new image builds roughly monthly; the date-stamped URL
# below rolls forward. If this 404s, browse
#   https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_arm64/
# (and /vendor/waydroid_arm64/) for the current VANILLA system zip and the
# matching MAINLINE vendor zip, then update both URLs in lockstep.

fetch() { # url dest [sha256]
    local url="$1" dest="$2" sha="${3:-}"
    if [ -f "$dest" ] && [ -n "$sha" ]; then
        if echo "$sha  $dest" | shasum -a 256 -c - >/dev/null 2>&1; then
            echo "  $dest present (sha256 ok)"
            return 0
        fi
        echo "  $dest sha mismatch, re-fetching"
        rm -f "$dest"
    fi
    [ -f "$dest" ] && return 0
    echo "  fetching $url"
    # The Waydroid images ship as .zip containing the .img; download the zip,
    # then unzip the single .img out of it. -L follows SourceForge's 302 to
    # a CDN, --retry for the CDN's occasional 503s, -C - for resume.
    local zip="$dest.zip"
    curl -fL --retry 3 -C - -o "$zip" "$url"
    # The zip contains exactly one .img at the archive root.
    unzip -o -j "$zip" '*.img' -d "$OUT"
    rm -f "$zip"
    if [ -n "$sha" ]; then
        echo "$sha  $dest" | shasum -a 256 -c -
    fi
}

SYS="$OUT/system.img"
VEN="$OUT/vendor.img"

echo "Fetching LineageOS 20.0 (Android 13) vanilla arm64 images..."
fetch "${IMAGES[0]}" "$SYS" "$SYS_SHA256"
fetch "${IMAGES[1]}" "$VEN" "$VENDOR_SHA256"

# Record the image-set metadata so the guest's android.sh knows the props.
cat > "$OUT/waydroid.cfg" <<EOF
# Waydroid image-set descriptor (ish-plus LineageOS 20.0 build)
[image]
# The version string shown in Waydroid's settings UI.
version=lineage-20.0-20260927-VANILLA-waydroid_arm64
# Android release (13 = API 33) — used by lmkd, ART and SurfaceFlinger.
android_api_level=33
# Hardware properties forced by iSH+'s guest init so Android uses the
# Mesa virglrenderer/ANGLE Metal path, not a software SwiftShader one.
ro.hardware.gralloc=gbm
ro.hardware.egl=mesa
ro.hardware.vulkan=moltenvk
ro.hardware.opengles.version=196609
# Memory-friendly: A13 has 3-4 GB. HeapDalvik sizes picked for 1.5 GB RAM.
# Conservative — Android 13's ART AOT churn is heavier than Android 10's,
# so keep heap targets low to avoid triggering iOS jetsam.
dalvik.vm.heapsize=256m
dalvik.vm.heapgrowthlimit=128m
dalvik.vm.heapstartsize=8m
ro.lmk.critical=15
ro.lmk.low=80
ro.lmk.debug=false
# No GApps; FDroid/Aurora installed by the user inside the container.
ro.com.google.gms=0
EOF

echo
echo "Images ready:"
ls -la "$OUT"

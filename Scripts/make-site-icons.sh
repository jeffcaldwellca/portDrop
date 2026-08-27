#!/usr/bin/env bash
# Derives the website's favicons and PWA icons from the app icon set (site/static/*).
# Re-run after Scripts/make-branding.swift changes the icon, then commit the outputs.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=PortDrop/Resources/Assets.xcassets/AppIcon.appiconset
OUT=site/static
mkdir -p "$OUT"

cp "$SRC/icon_512x512@1x.png" "$OUT/icon-512.png"
cp "$SRC/icon_256x256@1x.png" "$OUT/icon-256.png"
cp "$SRC/icon_32x32@1x.png"   "$OUT/favicon-32.png"
sips -z 192 192 "$SRC/icon_256x256@1x.png" --out "$OUT/icon-192.png"        >/dev/null
sips -z 180 180 "$SRC/icon_256x256@1x.png" --out "$OUT/apple-touch-icon.png" >/dev/null

# favicon.ico: an ICO container wrapping the 16 px and 32 px PNGs (PNG-in-ICO has been supported
# by every browser since Vista-era IE; it avoids shipping a BMP encoder).
python3 - "$OUT/favicon.ico" "$SRC/icon_16x16@1x.png" "$SRC/icon_32x32@1x.png" <<'EOF'
import struct, sys
out, *pngs = sys.argv[1:]
images = [open(p, 'rb').read() for p in pngs]
sizes = [16, 32]
header = struct.pack('<HHH', 0, 1, len(images))          # reserved, type=icon, count
offset = 6 + 16 * len(images)                            # first image starts after the directory
entries, blobs = b'', b''
for size, data in zip(sizes, images):
    entries += struct.pack('<BBBBHHII', size, size, 0, 0, 1, 32, len(data), offset + len(blobs))
    blobs += data
open(out, 'wb').write(header + entries + blobs)
EOF

echo "wrote $OUT/{favicon.ico,favicon-32.png,icon-192.png,icon-256.png,icon-512.png,apple-touch-icon.png}"

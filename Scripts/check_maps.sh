#!/bin/sh
# Build-time check only. Never fetch map data implicitly during a build.
for region in gotland stockholm uppland skane jamtland; do
    if [ ! -f "$SRCROOT/Heimdall/Resources/Maps/$region.zip" ]; then
        echo "error: Missing $region map. Run: python3 Scripts/prepare_region.py --all"
        exit 1
    fi
done

#!/usr/bin/env python3
"""Build and open Heimdall locally using the installed Xcode toolchain."""

import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def run(*command, capture=False):
    return subprocess.run(command, cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="An installed iPhone simulator name or UDID")
    parser.add_argument("--authenticate", action="store_true",
                        help="Use device authentication instead of the simulator preview bypass")
    args = parser.parse_args()

    developer_dir = Path(run("xcode-select", "-p", capture=True).strip())
    sdk_version = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version", capture=True).strip()
    if int(sdk_version.split(".")[0]) < 27:
        raise RuntimeError("Select Xcode 27 or newer in Xcode > Settings > Locations > Command Line Tools.")

    devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json", capture=True))
    candidates = []
    for runtime, entries in devices["devices"].items():
        if ".iOS-" not in runtime:
            continue
        version = tuple(int(part) for part in runtime.split(".iOS-")[1].split("-"))
        if version[0] >= 27:
            candidates.extend((device, version) for device in entries
                              if device.get("isAvailable") and device["name"].startswith("iPhone"))
    if args.device:
        candidates = [(device, version) for device, version in candidates
                      if args.device in (device["name"], device["udid"])]
    if not candidates:
        raise RuntimeError("No matching iOS 27+ iPhone simulator. Install an iOS runtime in Xcode > Settings > Components, then create an iPhone in Device Hub.")
    candidates.sort(key=lambda item: (item[0]["state"] == "Booted", item[1]), reverse=True)
    device = candidates[0][0]
    device_id = device["udid"]
    print(f"Running Heimdall on {device['name']} ({device_id})", flush=True)

    # Xcode 27 displays simulators in Device Hub; older layouts use Simulator.app.
    viewers = [developer_dir.parent / "Applications/DeviceHub.app",
               developer_dir / "Applications/Simulator.app"]
    viewer = next((path for path in viewers if path.exists()), None)
    if viewer is None:
        raise RuntimeError("Cannot locate Device Hub or Simulator in the selected Xcode installation.")
    run("open", str(viewer))

    build_dir = ROOT / "build/LocalRun"
    print("Building the Debug app…", flush=True)
    run("xcodebuild", "-quiet", "-project", "Heimdall.xcodeproj", "-scheme", "Heimdall",
        "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={device_id}",
        "-derivedDataPath", str(build_dir), "CODE_SIGNING_ALLOWED=NO", "build")
    app = build_dir / "Build/Products/Debug-iphonesimulator/Heimdall.app"
    with (app / "Info.plist").open("rb") as info_file:
        bundle_id = plistlib.load(info_file)["CFBundleIdentifier"]
    # Device Hub can change simulator state while opening. Boot after the build,
    # immediately before installation; -b also handles a currently shut-down phone.
    print("Waiting for the iPhone simulator to be ready…", flush=True)
    run("xcrun", "simctl", "bootstatus", device_id, "-b")
    print("Installing Heimdall (the first simulator boot can take a few minutes)…", flush=True)
    run("xcrun", "simctl", "install", device_id, str(app))
    # The app compiles this bypass only for Debug simulator builds.
    launch_args = [] if args.authenticate else ["--ui-testing"]
    print("Opening Heimdall…", flush=True)
    run("xcrun", "simctl", "launch", "--terminate-running-process", device_id, bundle_id, *launch_args)
    run("open", str(viewer))
    print(f"Heimdall is running. Select {device['name']} in {viewer.stem} if its screen is hidden.", flush=True)
    if not args.authenticate:
        print("Simulator preview: device authentication is bypassed. Physical iPhone builds always require authentication.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Could not run Heimdall: {error}", file=sys.stderr)
        sys.exit(1)

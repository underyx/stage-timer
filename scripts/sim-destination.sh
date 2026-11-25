#!/bin/bash
# Prints the xcodebuild -destination the tests run on: the first available iPhone simulator on the
# newest installed iOS runtime, by UDID, so nothing here names a device that the next Xcode drops.
# SIM=<name or UDID> picks one instead (two test runs on one simulator collide).
set -euo pipefail

if [ -n "${SIM:-}" ]; then
    case $SIM in
        *-*-*-*-*) echo "platform=iOS Simulator,id=$SIM" ;;
        *) echo "platform=iOS Simulator,name=$SIM" ;;
    esac
    exit 0
fi

xcrun simctl list devices available --json | python3 -c '
import json, re, sys

runtimes = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"SimRuntime\.iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime)
    phones = [d for d in devices if d.get("isAvailable", True) and d["name"].startswith("iPhone")]
    if match and phones:
        runtimes.append((tuple(int(part or 0) for part in match.groups()), phones))
if not runtimes:
    sys.exit("No iPhone simulator is installed: add an iOS runtime in Xcode > Settings > Components, or set SIM.")
version, phones = max(runtimes, key=lambda item: item[0])
phone = phones[0]
print("%s on iOS %d.%d" % (phone["name"], version[0], version[1]), file=sys.stderr)
print("platform=iOS Simulator,id=" + phone["udid"])
'

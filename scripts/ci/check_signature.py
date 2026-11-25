#!/usr/bin/env python3
"""Checks that a built StageTimer.app is signed for App Store distribution.

    scripts/ci/check_signature.py --team 2LV8JK59ZV --bundle-id dev.bence.stagetimer path/to/StageTimer.app

It checks: a strict signature by an Apple Distribution certificate of the team; the entitlements
application-identifier (<team>.<bundle id>) and com.apple.developer.team-identifier; get-task-allow
false; and an embedded provisioning profile.

Why: xcodebuild says "ARCHIVE SUCCEEDED" and "EXPORT SUCCEEDED" for an app signed with the wrong
identity or with none, and App Store Connect only objects after the upload. The app declares no
entitlements of its own (project.yml has no `entitlements:`); when it gains one, check it here.

Prints the signing authority's kind and the team, never a certificate's name. Exits 0 when all is
well, 1 otherwise. The same idea as underyx/life's ios/scripts/ci/check_signature.py.
"""
import argparse
import os
import plistlib
import subprocess
import sys


def run(*cmd):
    return subprocess.run(cmd, capture_output=True)


def check(app, team, bundle_id):
    problems = []
    verify = run("codesign", "--verify", "--strict", "--deep", app)
    if verify.returncode != 0:
        problems.append(f"codesign --verify failed: {verify.stderr.decode(errors='replace').strip()[:300]}")

    details = run("codesign", "-dvv", app).stderr.decode(errors="replace").splitlines()
    authorities = [line.split("=", 1)[1] for line in details if line.startswith("Authority=")]
    teams = [line.split("=", 1)[1] for line in details if line.startswith("TeamIdentifier=")]
    kind = authorities[0].split(":")[0] if authorities else "unsigned"
    if kind != "Apple Distribution":
        problems.append(f"signed by {kind}, not Apple Distribution")
    if teams != [team]:
        problems.append(f"team {teams[0] if teams else 'none'}, not {team}")

    raw = run("codesign", "-d", "--entitlements", "-", "--xml", app).stdout
    try:
        signed = plistlib.loads(raw) if raw.strip() else {}
    except plistlib.InvalidFileException:
        signed = {}
    expected = {
        "application-identifier": f"{team}.{bundle_id}",
        "com.apple.developer.team-identifier": team,
        "get-task-allow": False,
    }
    for key, value in expected.items():
        if signed.get(key) != value:
            problems.append(f"entitlement {key} is {signed.get(key)!r}, not {value!r}")

    if not os.path.isfile(os.path.join(app, "embedded.mobileprovision")):
        problems.append("no embedded.mobileprovision")

    print(f"{os.path.basename(app)}: {kind}, team {', '.join(teams) or '-'}, "
          f"{len(signed)} entitlements, {'OK' if not problems else 'NOT OK'}", flush=True)
    return problems


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--team", required=True)
    p.add_argument("--bundle-id", required=True)
    p.add_argument("app", help="the .app to check (in an .xcarchive, or unzipped from an .ipa)")
    args = p.parse_args(argv)

    problems = check(args.app, args.team, args.bundle_id) if os.path.isdir(args.app) else [f"{args.app} isn't there"]
    for problem in problems:
        prefix = "::error title=Signature check::" if os.environ.get("GITHUB_ACTIONS") == "true" else "error: "
        print(prefix + problem, file=sys.stderr, flush=True)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

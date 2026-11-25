#!/bin/bash
# Picks the Xcode that CI builds with: the newest released Xcode whose major version is at least
# XCODE_MIN_MAJOR (default 27: ControlSceneDelegate registers a UISceneAccessory, which only the
# iOS 27 SDK has), from /Applications/Xcode*.app (XCODE_SEARCH_DIR overrides the folder). Betas
# are skipped: App Store Connect refuses their builds, and CI should build with what a release
# would. XCODE_APP=/Applications/X.app overrides the choice.
#
# It never runs `sudo xcode-select`: on a self-hosted runner that is the owner's Mac. Under GitHub
# Actions it exports DEVELOPER_DIR for the later steps and sets the step outputs `path`, `version`
# and `build`. Same script as underyx/life's ios/scripts/ci/select-xcode.sh.
set -euo pipefail

min_major=${XCODE_MIN_MAJOR:-27}
search=${XCODE_SEARCH_DIR:-/Applications}

version_of() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null; }
build_of() { /usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$1/Contents/version.plist" 2>/dev/null; }

# Apple's beta builds look like 27B5019j: a 5xxx number and a trailing letter. Releases and release
# candidates don't (27A266a).
is_beta() {
    case $1 in *[Bb]eta*) return 0 ;; esac
    [[ $2 =~ ^[0-9]+[A-Z]5[0-9]{3}[a-z]$ ]]
}

major_of() { echo "${1%%.*}"; }

fail() {
    echo "::error title=No usable Xcode::$1" >&2
    echo "Xcodes in $search:" >&2
    for app in "$search"/Xcode*.app; do
        [ -d "$app" ] && echo "  $app: $(version_of "$app" || echo '?') ($(build_of "$app" || echo '?'))" >&2
    done
    exit 1
}

app=${XCODE_APP:-}
if [ -n "$app" ]; then
    [ -d "$app" ] || fail "XCODE_APP=$app doesn't exist on this runner. Clear the variable, or name an Xcode that's there."
    version=$(version_of "$app") || fail "XCODE_APP=$app has no version: is it an Xcode?"
    [ "$(major_of "$version")" -ge "$min_major" ] 2>/dev/null ||
        fail "XCODE_APP=$app is Xcode $version; this app needs Xcode $min_major or newer."
    if is_beta "$app" "$(build_of "$app" || true)"; then
        echo "::warning::XCODE_APP=$app is a beta; App Store Connect refuses builds made with one."
    fi
else
    app=$(
        for candidate in "$search"/Xcode*.app; do
            [ -d "$candidate" ] || continue
            real=$(cd "$candidate" && pwd -P) # the hosted image's version aliases are symlinks
            version=$(version_of "$real") || continue
            [[ $version =~ ^[0-9]+(\.[0-9]+)*$ ]] || continue
            [ "$(major_of "$version")" -ge "$min_major" ] || continue
            build=$(build_of "$real") || build=unknown
            if is_beta "$candidate" "$build" || is_beta "$real" "$build"; then
                echo "skipping $candidate ($version, $build): beta" >&2
                continue
            fi
            IFS=. read -r a b c _ <<< "$version"
            printf '%04d%04d%04d\t%s\n' "${a:-0}" "${b:-0}" "${c:-0}" "$real"
        done | sort -u | tail -n 1 | cut -f2
    )
    [ -n "$app" ] || fail "No released Xcode $min_major or newer in $search. On GitHub's runners, set the repository variable IOS_RUNS_ON to an image that has one (\"xcode-27\"), or XCODE_APP to one that's installed."
fi

version=$(version_of "$app")
build=$(build_of "$app" || echo unknown)
developer_dir="$app/Contents/Developer"
if [ "${GITHUB_ACTIONS:-}" = true ]; then
    echo "DEVELOPER_DIR=$developer_dir" >> "$GITHUB_ENV"
    {
        echo "path=$app"
        echo "version=$version"
        echo "build=$build"
    } >> "$GITHUB_OUTPUT"
fi
echo "Using $app: Xcode $version ($build)"
DEVELOPER_DIR="$developer_dir" xcodebuild -version
DEVELOPER_DIR="$developer_dir" xcrun --sdk iphoneos --show-sdk-version | sed 's/^/iOS SDK /'

#!/usr/bin/env python3
"""Makes sure the App Store provisioning profiles the TestFlight export names exist, and installs them.

    scripts/ci/asc_profiles.py [--keychain PATH]                      in CI (key in ASC_API_KEY_P8)
    op read 'op://aurora/app-store-connect-api-key/credential' | scripts/ci/asc_profiles.py

Copied from underyx/life (ios/scripts/ci/asc_profiles.py), where it has released that app since
2026-09-28; only this header and the User-Agent differ. Fix a bug in both.

The profile names come from ExportOptions.plist's provisioningProfiles ({bundle ID: name}), next to
this file, so the export, the archive and this script can't disagree. For each one it finds the
ACTIVE IOS_APP_STORE profile of that name for that bundle ID that includes the certificate of an
Apple Distribution identity this machine actually has (`security find-identity`, the team from
ExportOptions.plist). If a live profile of that name for that bundle ID and type exists but lacks
this machine's certificate (the Mac and CI sign with different Apple Distribution certificates), it
is replaced by one that holds its certificates AND this machine's, so whoever signed with it still
can. Otherwise it deletes the dead (INVALID or expired) profiles of that name and creates a new one
for this certificate. A live profile of that name for another bundle ID or type is reported, never
touched. The profile is then written, by UUID, to both folders Xcode reads profiles from. Running
it again changes nothing.

Why profiles by name through the API: the App Store Connect key can't use cloud-managed signing
("Cloud signing permission error"), so `-allowProvisioningUpdates` can't make them at export time.

The .p8 key (PEM) comes from the ASC_API_KEY_P8 environment variable, or else from stdin, never from
an argument. It stays in memory: each token is signed by handing the key to openssl through a pipe
(the same code as line-bites' scripts/ci/asc.py). The key ID and issuer ID come from ASC_KEY_ID and
ASC_ISSUER_ID. Needs only Python 3.9+ and openssl. Nothing printed names a person: certificates are
shown by SHA-1 and serial number.

Exits 0 on success, 1 on an API or signing-setup failure, 2 on bad usage or configuration.
"""
import argparse
import base64
import datetime
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_EXPORT_OPTIONS = os.path.join(HERE, "ExportOptions.plist")
# Neither ID is secret (the .p8 is). The workflow passes the repository variables.
DEFAULT_KEY_ID = "C2NMH2V7VT"
DEFAULT_ISSUER_ID = "a6663286-93fc-457f-b136-61470d3c093d"
TOKEN_LIFETIME = 1200  # Apple's maximum is 20 minutes
PROFILE_TYPES = {"app-store-connect": "IOS_APP_STORE", "app-store": "IOS_APP_STORE"}
# Xcode 16 and later read ~/Library/Developer/Xcode/UserData/Provisioning Profiles; older Xcodes (and
# some tools) read ~/Library/MobileDevice/Provisioning Profiles. Writing both costs nothing.
INSTALL_DIRS = (
    "~/Library/Developer/Xcode/UserData/Provisioning Profiles",
    "~/Library/MobileDevice/Provisioning Profiles",
)
EXPIRY_WARNING_DAYS = 30


class Fail(Exception):
    """A failure with a message fit for the log; exits with `code`."""

    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code


def log(*parts):
    print(*parts, file=sys.stderr, flush=True)


def in_github_actions():
    return os.environ.get("GITHUB_ACTIONS") == "true"


# --- ES256 JWT (as in line-bites' scripts/ci/asc.py) -------------------------------------------------


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _der_length(der: bytes, i: int):
    """Reads a DER length at der[i]; returns (length, index of the first content byte)."""
    if i >= len(der):
        raise ValueError("truncated DER length")
    first = der[i]
    if first < 0x80:
        return first, i + 1
    count = first & 0x7F
    if count == 0 or count > 2 or i + 1 + count > len(der):
        raise ValueError("unsupported DER length")
    return int.from_bytes(der[i + 1 : i + 1 + count], "big"), i + 1 + count


def der_to_raw(der: bytes, size: int = 32) -> bytes:
    """ECDSA-Sig-Value (SEQUENCE { INTEGER r, INTEGER s }) -> r || s, `size` bytes each (JWS form)."""
    if not der or der[0] != 0x30:
        raise ValueError("signature is not a DER SEQUENCE")
    length, i = _der_length(der, 1)
    if i + length != len(der):
        raise ValueError("DER SEQUENCE length doesn't match the signature")
    out = b""
    for name in ("r", "s"):
        if i >= len(der) or der[i] != 0x02:
            raise ValueError(f"DER {name} is not an INTEGER")
        n, i = _der_length(der, i + 1)
        value = der[i : i + n]
        if len(value) != n:
            raise ValueError(f"DER {name} is truncated")
        value = value.lstrip(b"\x00")
        if len(value) > size:
            raise ValueError(f"DER {name} is longer than {size} bytes")
        out += value.rjust(size, b"\x00")
        i += n
    if i != len(der):
        raise ValueError("trailing bytes after the DER signature")
    return out


def sign_es256(pem: bytes, message: bytes) -> bytes:
    """Signs with openssl, which reads the key from a pipe: the key is never written to a file."""
    r, w = os.pipe()
    try:
        os.write(w, pem)  # a .p8 is ~250 bytes, far under the pipe's buffer, so this can't block
    finally:
        os.close(w)
    try:
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", f"/dev/fd/{r}"],
            input=message, capture_output=True, pass_fds=(r,),
        )
    except FileNotFoundError:
        raise Fail("openssl isn't on PATH", 2)
    finally:
        os.close(r)
    if result.returncode != 0:
        # openssl's message names the problem (a malformed key), never the key itself.
        detail = result.stderr.decode(errors="replace").strip().splitlines()
        raise Fail("openssl couldn't sign with the key: " + (detail[0] if detail else "no detail"), 2)
    return der_to_raw(result.stdout)


def mint_token(pem: bytes, key_id: str, issuer_id: str, now=None) -> str:
    now = int(time.time() if now is None else now)
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    claims = b64url(json.dumps(
        {"iss": issuer_id, "iat": now, "exp": now + TOKEN_LIFETIME, "aud": "appstoreconnect-v1"},
        separators=(",", ":")).encode())
    signing_input = f"{header}.{claims}".encode()
    return f"{header}.{claims}.{b64url(sign_es256(pem, signing_input))}"


# --- API client -------------------------------------------------------------------------------------


class ASC:
    def __init__(self, pem: bytes, key_id: str, issuer_id: str):
        self.pem, self.key_id, self.issuer_id = pem, key_id, issuer_id
        self._token, self._minted = None, 0.0

    def token(self):
        if self._token is None or time.time() - self._minted > TOKEN_LIFETIME - 300:
            self._token, self._minted = mint_token(self.pem, self.key_id, self.issuer_id), time.time()
            if in_github_actions():
                # Nothing prints the token; masking it is belt and braces.
                print(f"::add-mask::{self._token}", file=sys.stderr, flush=True)
        return self._token

    def request(self, method, path, body=None, params=None, ok=(200, 201, 204)):
        """Returns (status, parsed JSON or None). Raises Fail on a status outside `ok`."""
        url = path if path.startswith("http") else API + path
        if params:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params, safe="[],.")
        data = json.dumps(body).encode() if body is not None else None
        # Only reads are retried after a server or network error: a POST that failed that way may
        # still have gone through. A 429 means the request wasn't handled, so it's safe to repeat.
        retry = (429, 500, 502, 503, 504) if method == "GET" else (429,)
        for attempt in range(4):
            req = urllib.request.Request(url, method=method, data=data)
            req.add_header("Authorization", f"Bearer {self.token()}")
            req.add_header("Accept", "application/json")
            req.add_header("User-Agent", "stage-screen-release/1")
            if data is not None:
                req.add_header("Content-Type", "application/json")
            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    status, raw = resp.status, resp.read()
            except urllib.error.HTTPError as e:
                status, raw = e.code, e.read()
            except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
                if attempt == 3 or method != "GET":
                    raise Fail(f"{method} {short(url)}: network error: {e}")
                time.sleep(2 ** attempt * 5)
                continue
            if status in retry and attempt < 3:
                log(f"{method} {short(url)}: HTTP {status}, retrying")
                time.sleep(2 ** attempt * 5)
                continue
            parsed = parse_json(raw)
            if status not in ok:
                raise APIError(method, url, status, parsed)
            return status, parsed
        raise AssertionError("unreachable")

    def get_all(self, path, params=None):
        """Follows links.next; returns (all data, all included)."""
        data, included, url = [], [], path
        while url:
            page = self.request("GET", url, params=params)[1] or {}
            params = None  # links.next carries the query
            data += page.get("data") or []
            included += page.get("included") or []
            url = (page.get("links") or {}).get("next")
        return data, included


class APIError(Fail):
    def __init__(self, method, url, status, body):
        self.status, self.body = status, body
        super().__init__(f"{method} {short(url)}: HTTP {status}: {error_text(body)}")


def short(url):
    return url.replace(API, "")


def parse_json(raw):
    if not raw:
        return None
    try:
        return json.loads(raw)
    except ValueError:
        return raw.decode(errors="replace")[:500]


def error_text(body):
    if isinstance(body, dict) and body.get("errors"):
        return "; ".join(
            " - ".join(x for x in (e.get("code"), e.get("title"), e.get("detail")) if x) for e in body["errors"])
    return str(body)[:500] if body else "(no body)"


# --- Local state ------------------------------------------------------------------------------------


def read_export_options(path):
    try:
        with open(path, "rb") as f:
            options = plistlib.load(f)
    except (OSError, plistlib.InvalidFileException) as e:
        raise Fail(f"can't read {path}: {e}", 2)
    profiles = options.get("provisioningProfiles")
    team = options.get("teamID")
    profile_type = PROFILE_TYPES.get(options.get("method"))
    if not isinstance(profiles, dict) or not profiles or not all(
            isinstance(k, str) and isinstance(v, str) and v for k, v in profiles.items()):
        raise Fail(f"{path} has no provisioningProfiles {{bundle ID: profile name}}", 2)
    if not team:
        raise Fail(f"{path} has no teamID", 2)
    if not profile_type:
        raise Fail(f"{path}: method {options.get('method')!r} isn't an App Store export", 2)
    return team, profile_type, profiles


FIND_IDENTITY = re.compile(r'^\s*\d+\)\s+([0-9A-F]{40})\s+"(.*)"\s*$')


def distribution_identities(team, keychain=None):
    """SHA-1s of the valid Apple Distribution code-signing identities for `team` on this machine."""
    cmd = ["security", "find-identity", "-v", "-p", "codesigning"] + ([keychain] if keychain else [])
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise Fail(f"security find-identity failed: {result.stderr.strip()[:300]}")
    found = []
    for line in result.stdout.splitlines():
        m = FIND_IDENTITY.match(line)
        if m and m.group(2).startswith("Apple Distribution:") and m.group(2).endswith(f"({team})"):
            found.append(m.group(1))
    return sorted(set(found))


def install(content: bytes, uuid: str, dirs=INSTALL_DIRS):
    """Writes the profile as <uuid>.mobileprovision into each folder; returns how many changed."""
    if not re.fullmatch(r"[0-9A-Fa-f-]{36}", uuid or ""):
        raise Fail(f"App Store Connect returned a profile with an odd UUID: {uuid!r}")
    changed = 0
    for folder in dirs:
        folder = os.path.expanduser(folder)
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, f"{uuid}.mobileprovision")
        try:
            with open(path, "rb") as f:
                if f.read() == content:
                    continue
        except FileNotFoundError:
            pass
        fd, tmp = tempfile.mkstemp(dir=folder, prefix=".profile.")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(content)
            os.chmod(tmp, 0o644)
            os.replace(tmp, path)
        except BaseException:
            os.unlink(tmp)
            raise
        changed += 1
    return changed


# --- App Store Connect ------------------------------------------------------------------------------


# App Store Connect writes dates as 2027-09-24T15:27:37.000+0000. Python before 3.11 (macOS's
# python3 is 3.9) reads an offset only with a colon, and a fraction only of 3 or 6 digits.
_OFFSET = re.compile(r"(?:Z|([+-]\d{2}):?(\d{2}))$")
_FRACTION = re.compile(r"\.(\d+)")


def parse_date(text):
    """An App Store Connect timestamp as an aware datetime (UTC if it names no zone), or None."""
    if not text:
        return None
    normal = _OFFSET.sub(lambda m: f"{m.group(1)}:{m.group(2)}" if m.group(1) else "+00:00", text)
    normal = _FRACTION.sub(lambda m: "." + m.group(1)[:6].ljust(6, "0"), normal, count=1)
    try:
        parsed = datetime.datetime.fromisoformat(normal)
    except ValueError:
        raise Fail(f"App Store Connect returned a date this script can't read: {text!r}")
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=datetime.timezone.utc)  # noqa: UP017


def matching_certificates(asc, sha1s):
    """The App Store Connect certificates whose DER has one of these SHA-1s: {id: (sha1, serial, expires)}."""
    certs, _ = asc.get_all("/v1/certificates", {
        "fields[certificates]": "certificateContent,serialNumber,certificateType,expirationDate", "limit": 200})
    wanted, found = set(sha1s), {}
    for c in certs:
        a = c.get("attributes") or {}
        try:
            der = base64.b64decode(a.get("certificateContent") or "")
        except ValueError:
            continue
        sha1 = hashlib.sha1(der).hexdigest().upper()
        if sha1 in wanted:
            found[c["id"]] = (sha1, a.get("serialNumber"), a.get("expirationDate"))
    return found


def bundle_id_resource(asc, identifier):
    ids, _ = asc.get_all("/v1/bundleIds", {"filter[identifier]": identifier, "limit": 200,
                                           "fields[bundleIds]": "identifier,platform"})
    # The filter matches more than the exact identifier (dev.bence.life also finds dev.bence.life.widgets).
    exact = [b for b in ids if (b.get("attributes") or {}).get("identifier") == identifier]
    if not exact:
        raise Fail(f"no App ID {identifier} in the developer account (or the key can't see it); "
                   "register it once, e.g. with an automatically signed build in Xcode")
    return exact[0]["id"]


def related_ids(resource, name):
    data = ((resource.get("relationships") or {}).get(name) or {}).get("data")
    if data is None:
        return set()
    if isinstance(data, dict):
        return {data["id"]}
    return {d["id"] for d in data}


def profiles_named(asc, name):
    profiles, _ = asc.get_all("/v1/profiles", {
        "filter[name]": name, "include": "bundleId,certificates", "limit": 200, "limit[certificates]": 50})
    return [p for p in profiles if (p.get("attributes") or {}).get("name") == name]


def is_live(profile, now):
    a = profile.get("attributes") or {}
    expires = parse_date(a.get("expirationDate"))
    return a.get("profileState") == "ACTIVE" and (expires is None or expires > now)


def ensure_profile(asc, name, bundle, profile_type, certs, now):
    """Returns (profile resource with profileContent, what happened)."""
    bundle_res = bundle_id_resource(asc, bundle)
    candidates = profiles_named(asc, name)
    live = [p for p in candidates if is_live(p, now)]
    usable = [p for p in live
              if p["attributes"].get("profileType") == profile_type
              and related_ids(p, "bundleId") == {bundle_res}
              and related_ids(p, "certificates") & set(certs)]
    if usable:
        best = max(usable, key=lambda p: p["attributes"].get("expirationDate") or "")
        return best, "found"
    same_app = [p for p in live
                if p["attributes"].get("profileType") == profile_type
                and related_ids(p, "bundleId") == {bundle_res}]
    if live and len(same_app) < len(live):
        p = next(x for x in live if x not in same_app)["attributes"]
        raise Fail(
            f'"{name}" exists and is {p.get("profileState")}, but it isn\'t an {profile_type} profile for '
            f"{bundle}. Something else uses the name: look at it in the developer portal before changing "
            "or deleting it.")
    keep = set()
    for p in same_app:
        # Signed with another Apple Distribution certificate (the Mac's, or CI's): replace it with a
        # profile for both, so the other signer keeps working and this job can sign too.
        keep |= related_ids(p, "certificates")
    for old in candidates:
        a = old["attributes"]
        if old in same_app:
            why = "to add this job's certificate to it"
        else:
            why = f"({a.get('profileState')}, expires {a.get('expirationDate')}), so the name is free"
        log(f'deleting the profile "{name}" ({a.get("uuid")}) {why}')
        asc.request("DELETE", f"/v1/profiles/{old['id']}")
    wanted_certs = sorted(set(certs) | keep)
    _, created = asc.request("POST", "/v1/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": profile_type},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_res}},
            "certificates": {"data": [{"type": "certificates", "id": cid} for cid in wanted_certs]},
        }}})
    return (created or {}).get("data") or {}, ("replaced" if keep else "created")


def run(asc, args):
    team, profile_type, wanted = read_export_options(args.export_options)
    sha1s = distribution_identities(team, args.keychain)
    if not sha1s:
        raise Fail(f"no valid Apple Distribution identity for team {team} in "
                   f"{args.keychain or 'the keychain search list'} (security find-identity -v -p codesigning)")
    log(f"Apple Distribution identities here: {', '.join(sha1s)}")
    certs = matching_certificates(asc, sha1s)
    if not certs:
        raise Fail("App Store Connect has no certificate matching this machine's Apple Distribution "
                   f"identity (SHA-1 {', '.join(sha1s)}): was it revoked?")
    for sha1, serial, expires in certs.values():
        log(f"certificate SHA-1 {sha1}, serial {serial}, expires {expires}")

    now = datetime.datetime.now(datetime.timezone.utc)  # noqa: UP017 -- datetime.UTC is 3.11+; macOS's python3 is 3.9
    report = []
    for bundle, name in sorted(wanted.items()):
        profile, what = ensure_profile(asc, name, bundle, profile_type, certs, now)
        a = profile.get("attributes") or {}
        content = a.get("profileContent")
        if not content:
            raise Fail(f'App Store Connect returned "{name}" without its content')
        changed = install(base64.b64decode(content), a.get("uuid"))
        expires = parse_date(a.get("expirationDate"))
        left = (expires - now).days if expires else None
        log(f'{bundle}: "{name}" {a.get("uuid")} {what}, '
            f"{'installed' if changed else 'already installed'}, expires {a.get('expirationDate')}")
        if left is not None and left < EXPIRY_WARNING_DAYS:
            msg = f'"{name}" expires in {left} days; the certificate probably does too'
            print(f"::warning::{msg}" if in_github_actions() else f"warning: {msg}", file=sys.stderr)
        report.append({"bundle_id": bundle, "name": name, "uuid": a.get("uuid"), "result": what,
                       "expires": a.get("expirationDate")})
    print(json.dumps(report))


# --- Entry point ------------------------------------------------------------------------------------


def read_key():
    pem = os.environ.get("ASC_API_KEY_P8", "")
    if not pem.strip() and not sys.stdin.isatty():
        pem = sys.stdin.read()
    if not pem.strip():
        raise Fail("no key: set ASC_API_KEY_P8, or pipe the .p8 to stdin", 2)
    if "-----BEGIN" not in pem or "PRIVATE KEY-----" not in pem:
        raise Fail("the key doesn't look like a .p8 (PEM private key)", 2)
    return pem.strip().encode() + b"\n"


def command_escape(text):
    return str(text).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def parser():
    p = argparse.ArgumentParser(
        prog="asc_profiles.py", description=__doc__.split("\n\n")[0],
        epilog="Key: ASC_API_KEY_P8 or stdin. IDs: ASC_KEY_ID, ASC_ISSUER_ID.",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--export-options", default=DEFAULT_EXPORT_OPTIONS,
                   help="the ExportOptions.plist whose provisioningProfiles to ensure (default: next to this file)")
    p.add_argument("--keychain", help="look for the signing identity only in this keychain")
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        key_id = os.environ.get("ASC_KEY_ID") or DEFAULT_KEY_ID
        issuer_id = os.environ.get("ASC_ISSUER_ID") or DEFAULT_ISSUER_ID
        run(ASC(read_key(), key_id, issuer_id), args)
    except Fail as e:
        if in_github_actions():
            print(f"::error title=asc_profiles.py::{command_escape(e)}", file=sys.stderr, flush=True)
        else:
            log(f"asc_profiles.py: {e}")
        return e.code
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())

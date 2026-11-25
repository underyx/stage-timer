#!/usr/bin/env python3
"""asc_profiles.py against a fake App Store Connect, with Apple's own date format (…000+0000).

    /usr/bin/python3 scripts/ci/test_asc_profiles.py

Copied from underyx/life with asc_profiles.py. The two bundle IDs and profile names below are that
app's and stay as the fixture (an app and its extension, where one identifier is a prefix of the
other): the tests write their own ExportOptions.plist, not this repository's.

Run it with macOS's /usr/bin/python3 (3.9), which is what the self-hosted runner gets when its
recorded PATH lacks Homebrew, and with PATH=/usr/bin:/bin to sign with the system openssl. The key
is a throwaway P-256 key made for the test; the signing identity lookup is stubbed.
"""
import base64
import contextlib
import hashlib
import http.server
import io
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc_profiles  # noqa: E402

CERT_DER = b"fake distribution certificate"
CERT_SHA1 = hashlib.sha1(CERT_DER).hexdigest().upper()
FUTURE = "2027-09-24T15:27:37.000+0000"  # Apple's format: no colon in the offset
PAST = "2025-09-24T15:27:37.000+0000"
BUNDLES = {"dev.bence.life": "B1", "dev.bence.life.widgets": "B2"}
EXPORT_OPTIONS = {
    "method": "app-store-connect",
    "teamID": "TESTTEAM00",
    "signingStyle": "manual",
    "signingCertificate": "Apple Distribution",
    "provisioningProfiles": {"dev.bence.life": "Life App Store", "dev.bence.life.widgets": "Life Widgets App Store"},
}


class FakeASC:
    def __init__(self):
        self.profiles, self.calls, self.next_id = {}, [], 1

    def add_profile(self, name, bundle, cert="C1", state="ACTIVE", expires=FUTURE):
        pid = f"P{self.next_id}"
        self.next_id += 1
        certs = [cert] if isinstance(cert, str) else list(cert)
        self.profiles[pid] = {"name": name, "bundle": BUNDLES[bundle], "certs": certs, "state": state,
                              "expires": expires, "uuid": f"00000000-0000-0000-0000-{self.next_id:012d}"}
        return pid

    def resource(self, pid):
        p = self.profiles[pid]
        return {"type": "profiles", "id": pid, "attributes": {
            "name": p["name"], "profileType": "IOS_APP_STORE", "profileState": p["state"],
            "expirationDate": p["expires"], "uuid": p["uuid"],
            "profileContent": base64.b64encode(f"profile {pid}".encode()).decode()},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": p["bundle"]}},
                              "certificates": {"data": [{"type": "certificates", "id": c}
                                                        for c in p["certs"]]}}}

    def handle(self, method, path, query, body):
        self.calls.append((method, path))
        if method == "GET" and path == "/v1/certificates":
            return 200, {"data": [{"type": "certificates", "id": "C1", "attributes": {
                "certificateContent": base64.b64encode(CERT_DER).decode(),
                "serialNumber": "33C926FD1ADF5B8F337A1897D1B28887", "expirationDate": FUTURE}}]}
        if method == "GET" and path == "/v1/bundleIds":
            # Like the real filter, a prefix finds the widget extension too.
            wanted = query["filter[identifier]"][0]
            return 200, {"data": [{"type": "bundleIds", "id": bid, "attributes": {"identifier": ident}}
                                  for ident, bid in BUNDLES.items() if ident.startswith(wanted)]}
        if method == "GET" and path == "/v1/profiles":
            name = query["filter[name]"][0]
            return 200, {"data": [self.resource(pid) for pid, p in self.profiles.items()
                                  if name in p["name"]]}
        if method == "DELETE" and path.startswith("/v1/profiles/"):
            del self.profiles[path.rsplit("/", 1)[1]]
            return 204, None
        if method == "POST" and path == "/v1/profiles":
            data = body["data"]
            cert = [c["id"] for c in data["relationships"]["certificates"]["data"]]
            bundle = next(k for k, v in BUNDLES.items()
                          if v == data["relationships"]["bundleId"]["data"]["id"])
            return 201, {"data": self.resource(self.add_profile(data["attributes"]["name"], bundle, cert))}
        return 404, {"errors": [{"code": "NOT_FOUND", "title": f"{method} {path}"}]}


class Handler(http.server.BaseHTTPRequestHandler):
    fake = None

    def _serve(self):
        url = urllib.parse.urlsplit(self.path)
        auth = self.headers.get("Authorization", "")
        assert auth.startswith("Bearer ") and auth.count(".") == 2, auth
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length)) if length else None
        status, reply = self.fake.handle(self.command, url.path, urllib.parse.parse_qs(url.query), body)
        raw = json.dumps(reply).encode() if reply is not None else b""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    do_GET = do_POST = do_DELETE = _serve

    def log_message(self, *args):
        pass


class ProfilesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="asc-profiles-test.")
        # A throwaway key, only for this test (openssl from PATH, as the script uses).
        ec = subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout"],
                            check=True, capture_output=True).stdout
        cls.pem = subprocess.run(["openssl", "pkcs8", "-topk8", "-nocrypt"], input=ec,
                                 check=True, capture_output=True).stdout
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.api = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        shutil.rmtree(cls.tmp)

    def setUp(self):
        self.fake = Handler.fake = FakeASC()
        self.home = tempfile.mkdtemp(dir=self.tmp)
        patches = [(asc_profiles, "API", self.api),
                   (asc_profiles, "distribution_identities", lambda team, keychain=None: [CERT_SHA1])]
        for obj, name, value in patches:
            self.addCleanup(setattr, obj, name, getattr(obj, name))
            setattr(obj, name, value)
        self.addCleanup(os.environ.__setitem__, "HOME", os.environ["HOME"])
        os.environ["HOME"] = self.home  # install() writes under ~/Library
        os.environ.pop("GITHUB_ACTIONS", None)

    def run_script(self):
        options = os.path.join(self.home, "ExportOptions.plist")
        with open(options, "wb") as f:
            plistlib.dump(EXPORT_OPTIONS, f)
        args = asc_profiles.parser().parse_args(["--export-options", options])
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            asc_profiles.run(asc_profiles.ASC(self.pem, "TESTKEY123", "00000000-0000-0000-0000-000000000000"),
                             args)
        return {r["bundle_id"]: r for r in json.loads(out.getvalue())}, err.getvalue()

    def installed(self):
        found = set()
        for folder in asc_profiles.INSTALL_DIRS:
            path = os.path.expanduser(folder)
            found |= {os.path.join(folder, f) for f in os.listdir(path)} if os.path.isdir(path) else set()
        return found

    def test_parse_date_reads_apples_format(self):
        self.assertEqual(asc_profiles.parse_date(FUTURE).isoformat(), "2027-09-24T15:27:37+00:00")
        self.assertEqual(asc_profiles.parse_date("2027-09-24T15:27:37Z").isoformat(),
                         "2027-09-24T15:27:37+00:00")
        self.assertEqual(asc_profiles.parse_date("2027-09-24T08:27:37.5-0700").utcoffset().total_seconds(),
                         -7 * 3600)
        self.assertIsNone(asc_profiles.parse_date(None))
        with self.assertRaises(asc_profiles.Fail):
            asc_profiles.parse_date("next year")

    def test_finds_and_installs_live_profiles_then_changes_nothing(self):
        self.fake.add_profile("Life App Store", "dev.bence.life")
        self.fake.add_profile("Life Widgets App Store", "dev.bence.life.widgets")
        report, _ = self.run_script()
        self.assertEqual({b: r["result"] for b, r in report.items()},
                         {"dev.bence.life": "found", "dev.bence.life.widgets": "found"})
        self.assertEqual(len(self.installed()), 4)  # two profiles, two folders
        self.assertNotIn("POST", [m for m, _ in self.fake.calls])
        _, log = self.run_script()
        self.assertEqual(log.count("already installed"), 2)

    def test_replaces_expired_and_creates_missing(self):
        self.fake.add_profile("Life App Store", "dev.bence.life", expires=PAST)
        report, _ = self.run_script()
        self.assertEqual({b: r["result"] for b, r in report.items()},
                         {"dev.bence.life": "created", "dev.bence.life.widgets": "created"})
        self.assertEqual([m for m, _ in self.fake.calls if m != "GET"], ["DELETE", "POST", "POST"])
        self.assertEqual({p["expires"] for p in self.fake.profiles.values()}, {FUTURE})

    def test_adds_this_certificate_to_a_live_profile_for_another(self):
        # The Mac signs with one Apple Distribution certificate and CI with another: the named
        # profile is replaced by one for both, so neither signer loses it.
        self.fake.add_profile("Life App Store", "dev.bence.life", cert="C-OTHER")
        self.fake.add_profile("Life Widgets App Store", "dev.bence.life.widgets", cert=["C-OTHER", "C1"])
        report, _ = self.run_script()
        self.assertEqual({b: r["result"] for b, r in report.items()},
                         {"dev.bence.life": "replaced", "dev.bence.life.widgets": "found"})
        self.assertEqual([m for m, _ in self.fake.calls if m != "GET"], ["DELETE", "POST"])
        app = [p for p in self.fake.profiles.values() if p["name"] == "Life App Store"]
        self.assertEqual([sorted(p["certs"]) for p in app], [["C-OTHER", "C1"]])
        _, log = self.run_script()  # and then nothing changes
        self.assertEqual(log.count("already installed"), 2)

    def test_leaves_a_same_named_profile_for_another_app_alone(self):
        self.fake.add_profile("Life App Store", "dev.bence.life.widgets", cert="C-OTHER")
        with self.assertRaisesRegex(asc_profiles.Fail, "Something else uses the name"):
            self.run_script()
        self.assertEqual([m for m, _ in self.fake.calls if m != "GET"], [])


if __name__ == "__main__":
    unittest.main(verbosity=2)

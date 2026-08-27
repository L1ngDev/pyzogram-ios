#!/usr/bin/env python3
"""Generate a self-signed code-signing identity + provisioning profiles.

This lets the Bazel/rules_apple build produce a device IPA without any Apple
developer account. The IPA is signed with this throwaway identity and embeds
self-signed profiles; it is NOT trusted by Apple. Sideloadly re-signs the IPA
with the user's own Apple ID at install time, so the throwaway identity only
needs to let the local `codesign` step succeed.
"""
import datetime
import os
import plistlib
import shutil
import subprocess
import sys
import uuid

OUT = os.environ.get("CODESIGN_DIR", "codesigning")
CERT_DIR = os.path.join(OUT, "certs")
PROF_DIR = os.path.join(OUT, "profiles")

# Must match build-system/appstore-configuration.json (team_id / bundle_id),
# otherwise the profile's application-identifier won't match and the build
# will skip the profile.
TEAM_ID = "C67CF9S4VU"
BUNDLE_ID = "ph.telegra.Telegraph"
PASS = "pyzogram"

os.makedirs(CERT_DIR, exist_ok=True)
os.makedirs(PROF_DIR, exist_ok=True)


def run(args):
    print("+ " + " ".join(args), flush=True)
    subprocess.check_call(args)


# 1. Self-signed CA
run(["openssl", "genrsa", "-out", "ca.key", "2048"])
run(["openssl", "req", "-x509", "-new", "-nodes", "-key", "ca.key",
     "-subj", "/CN=Pyzogram Self-Sign CA", "-days", "3650", "-out", "ca.crt"])

# 2. Code-signing cert (iPhone Developer style, OU = team id)
run(["openssl", "genrsa", "-out", "dev.key", "2048"])
ext = (
    "[req]\n"
    "distinguished_name = dn\n"
    "[dn]\n"
    "OU = {team}\n"
    "CN = iPhone Developer: Pyzogram\n"
    "[v3]\n"
    "basicConstraints = critical, CA:FALSE\n"
    "keyUsage = critical, digitalSignature, keyEncipherment\n"
    "extendedKeyUsage = critical, 1.3.6.1.5.5.7.3.3, 1.2.840.113635.100.6.1.13\n"
    "1.2.840.113635.100.6.1.13 = critical, ASN1:NULL\n"
).format(team=TEAM_ID)
with open("dev.ext", "w") as f:
    f.write(ext)
run(["openssl", "req", "-new", "-key", "dev.key",
     "-subj", "/OU={team}/CN=iPhone Developer: Pyzogram".format(team=TEAM_ID),
     "-out", "dev.csr"])
run(["openssl", "x509", "-req", "-in", "dev.csr", "-CA", "ca.crt", "-CAkey", "ca.key",
     "-CAcreateserial", "-days", "3650", "-extfile", "dev.ext", "-extensions", "v3",
     "-out", "dev.crt"])

# 3. Export p12 + copy DER cert for the codesigning directory
run(["openssl", "pkcs12", "-export", "-out", os.path.join(CERT_DIR, "dev.p12"),
     "-inkey", "dev.key", "-in", "dev.crt", "-passout", "pass:" + PASS])
shutil.copy("dev.crt", os.path.join(CERT_DIR, "dev.cer"))
run(["openssl", "x509", "-in", "dev.crt", "-out", "dev.der", "-outform", "DER"])
dev_cert_der = open("dev.der", "rb").read()

# 4. Provisioning profiles (one per bundle-id suffix the build expects)
targets = [
    ("", "Telegram", True),
    (".Share", "Share", False),
    (".NotificationContent", "NotificationContent", False),
    (".NotificationService", "NotificationService", False),
    (".Widget", "Widget", False),
    (".SiriIntents", "Intents", False),
    (".BroadcastUpload", "BroadcastUpload", False),
]

for suffix, name, is_base in targets:
    app_id = "{team}.{bundle}{suffix}".format(team=TEAM_ID, bundle=BUNDLE_ID, suffix=suffix)
    entitlements = {
        "application-identifier": app_id,
        "com.apple.developer.team-identifier": TEAM_ID,
        "get-task-allow": True,
        "keychain-access-groups": ["{team}.{bundle}".format(team=TEAM_ID, bundle=BUNDLE_ID)],
    }
    if is_base:
        entitlements["aps-environment"] = "development"
    profile = {
        "AppIDName": "Pyzogram",
        "ApplicationIdentifierPrefix": [TEAM_ID],
        "CreationDate": datetime.datetime(2026, 1, 1, 0, 0, 0),
        "Platform": ["iOS"],
        "IsXcodeManaged": False,
        "DeveloperCertificates": [dev_cert_der],
        "Entitlements": entitlements,
        "ExpirationDate": datetime.datetime(2030, 1, 1, 0, 0, 0),
        "Name": "Pyzogram {name}".format(name=name),
        "ProvisionsAllDevices": True,
        "TeamIdentifier": [TEAM_ID],
        "TeamName": "Pyzogram",
        "UUID": str(uuid.uuid4()).upper(),
        "Version": 1,
    }
    plist_path = "{name}.plist".format(name=name)
    with open(plist_path, "wb") as f:
        f.write(plistlib.dumps(profile, fmt=plistlib.FMT_XML))
    run(["openssl", "smime", "-sign", "-in", plist_path,
         "-out", os.path.join(PROF_DIR, name + ".mobileprovision"),
         "-signer", "dev.crt", "-inkey", "dev.key", "-certfile", "ca.crt",
         "-outform", "DER", "-nodetach"])

print("Generated self-signed codesigning material in " + OUT)

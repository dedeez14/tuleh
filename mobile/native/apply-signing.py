#!/usr/bin/env python3
# Auto-Update Tahap 4 — suntik signingConfig rilis ke app/build.gradle hasil
# `cap add android`, membaca kredensial dari environment (GitHub Secrets).
# Hanya dijalankan CI bila secret keystore tersedia. Idempoten.

import io
import os
import re
import sys

GRADLE = os.path.join("mobile", "android", "app", "build.gradle")

SIGNING_BLOCK = (
    "    signingConfigs {\n"
    "        release {\n"
    "            storeFile file(System.getenv(\"ANDROID_KEYSTORE_PATH\"))\n"
    "            storePassword System.getenv(\"ANDROID_KS_PASS\")\n"
    "            keyAlias System.getenv(\"ANDROID_KEY_ALIAS\")\n"
    "            keyPassword System.getenv(\"ANDROID_KEY_PASS\")\n"
    "        }\n"
    "    }\n"
)


def main():
    if not os.path.exists(GRADLE):
        print("!! build.gradle tak ditemukan:", GRADLE)
        sys.exit(1)
    with io.open(GRADLE, "r", encoding="utf-8") as f:
        s = f.read()

    if "signingConfigs" in s and "ANDROID_KEYSTORE_PATH" in s:
        print("== signingConfig sudah dipasang")
        return

    # 1) Sisipkan signingConfigs tepat setelah pembuka `android {`.
    new_s, n = re.subn(r"android\s*\{\s*\n", lambda m: m.group(0) + SIGNING_BLOCK, s, count=1)
    if n != 1:
        print("!! blok `android {` tak ditemukan")
        sys.exit(1)
    s = new_s

    # 2) buildTypes.release memakai signingConfig rilis.
    s, n = re.subn(r"(buildTypes\s*\{\s*release\s*\{)",
                   r"\1\n            signingConfig signingConfigs.release", s, count=1)
    if n != 1:
        print("!! buildTypes.release tak ditemukan — signingConfig tak terpasang di release")
        sys.exit(1)

    with io.open(GRADLE, "w", encoding="utf-8") as f:
        f.write(s)
    print("++ signingConfig rilis terpasang di build.gradle")


if __name__ == "__main__":
    main()

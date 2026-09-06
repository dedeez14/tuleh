#!/usr/bin/env python3
# Auto-Update Tahap 4 — sunting proyek Android hasil `cap add android`:
#   1) izin REQUEST_INSTALL_PACKAGES di AndroidManifest.xml
#   2) jalur FileProvider external-files (agar APK bisa dibagikan ke pemasang)
# Idempoten: aman dijalankan berulang.

import io
import os
import re
import sys

APP = os.path.join("mobile", "android", "app", "src", "main")
MANIFEST = os.path.join(APP, "AndroidManifest.xml")
FILE_PATHS = os.path.join(APP, "res", "xml", "file_paths.xml")

PERM = '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />'
# Android 13+: notifikasi "pembaruan siap dipasang" (unduhan selesai saat app di latar).
PERM_NOTIF = '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />'
EXT_FILES = '<external-files-path name="tuleh_apk" path="." />'


def read(path):
    with io.open(path, "r", encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(text)


def patch_manifest():
    if not os.path.exists(MANIFEST):
        print("!! AndroidManifest.xml tidak ditemukan:", MANIFEST)
        sys.exit(1)
    s = read(MANIFEST)
    for nama, perm in (("REQUEST_INSTALL_PACKAGES", PERM), ("POST_NOTIFICATIONS", PERM_NOTIF)):
        if nama in s:
            print("== izin %s sudah ada" % nama)
            continue
        # Sisipkan tepat sebelum <application ...>
        m = re.search(r"\n(\s*)<application", s)
        if not m:
            print("!! tag <application> tak ditemukan di manifest")
            sys.exit(1)
        indent = m.group(1)
        s = s[:m.start()] + "\n" + indent + perm + s[m.start():]
        print("++ izin %s ditambahkan" % nama)
    write(MANIFEST, s)


def patch_file_paths():
    if not os.path.exists(FILE_PATHS):
        # Buat berkas minimal bila Capacitor tak menghasilkannya.
        os.makedirs(os.path.dirname(FILE_PATHS), exist_ok=True)
        write(FILE_PATHS,
              "<?xml version='1.0' encoding='utf-8'?>\n"
              "<paths xmlns:android=\"http://schemas.android.com/apk/res-android\">\n"
              "    " + EXT_FILES + "\n"
              "</paths>\n")
        print("++ file_paths.xml dibuat")
        return
    s = read(FILE_PATHS)
    if "external-files-path" in s and "tuleh_apk" in s:
        print("== external-files-path sudah ada")
        return
    s = re.sub(r"(\s*)</paths>", r"\1    " + EXT_FILES + r"\1</paths>", s, count=1)
    write(FILE_PATHS, s)
    print("++ external-files-path ditambahkan ke file_paths.xml")


if __name__ == "__main__":
    patch_manifest()
    patch_file_paths()
    print("Patch Android selesai.")

#!/usr/bin/env python3
"""Génère une source AltStore/SideStore (apps.json) pointant vers l'IPA de la release.

Usage : make_source.py <ipa> <version> <owner/repo> <tag>
"""
import datetime
import json
import os
import sys

ipa, version, repo, tag = sys.argv[1:5]
base = f"https://github.com/{repo}"
raw = f"https://raw.githubusercontent.com/{repo}/{tag}"
icon = f"{raw}/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

source = {
    "name": "SkullCorp",
    "identifier": "com.skullcorp.source",
    "sourceURL": f"{base}/releases/latest/download/altstore-source.json",
    "iconURL": icon,
    "website": base,
    "apps": [
        {
            "name": "SkullWidgets",
            "bundleIdentifier": "com.skullcorp.skullwidgets",
            "developerName": "SkullCorp",
            "subtitle": "Widgets iOS pour tes web apps",
            "localizedDescription": "Affiche les infos de tes web apps (ou de Home Assistant) dans des widgets "
                                    "et déclenche leurs actions depuis l'écran d'accueil ou Raccourcis.",
            "iconURL": icon,
            "tintColor": "FF9534",
            "category": "utilities",
            "versions": [
                {
                    "version": version,
                    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "downloadURL": f"{base}/releases/download/{tag}/SkullWidgets.ipa",
                    "size": os.path.getsize(ipa),
                    "minOSVersion": "17.0",
                }
            ],
            "appPermissions": {
                "entitlements": ["com.apple.security.application-groups"],
                "privacy": {
                    "NSLocalNetworkUsageDescription": "Contacter tes web apps et Home Assistant sur le réseau local."
                },
            },
        }
    ],
    "news": [],
}
json.dump(source, sys.stdout, indent=2, ensure_ascii=False)

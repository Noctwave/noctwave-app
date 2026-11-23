#!/usr/bin/env python3
"""
tools/update_version_feed.py — фиды версий и AltStore/GBox-источник на gh-pages.

Каналы и файлы:
  --channel stable   : version.json (автообновление) + apps.json
  --channel beta|rc  : beta.json (opt-in бета-канал) + apps.json
  --channel preview  : apps.json только (rolling dev-сборка main)

apps.json — единый GBox/AltStore-источник: все живые каналы, по одной
свежайшей сборке на канал. Каждый запуск обновляет запись своего канала,
остальные подтягиваются из опубликованного apps.json на gh-pages.

Вызывается ТОЛЬКО из релизного и preview-воркфлоу. Деплой на gh-pages
выполняет workflow (peaceiris/actions-gh-pages, keep_files).
"""

import argparse
import json
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

BUNDLE_ID = "com.noctwave.noctwaveApp"
DEVELOPER_NAME = "Noctwave"
TINT_COLOR = "6366F1"
APP_DESCRIPTION = (
    "Noctwave — офлайн-пульт для BLE-устройств через Bluetooth Advertising. "
    "Без аккаунтов, телеметрии и подписок."
)
ICON_PATH = "docs/appicon.png"

CHANNEL_APP_NAMES = {
    "stable": "Noctwave",
    "beta": "Noctwave (Beta)",
    "rc": "Noctwave (RC)",
    "preview": "Noctwave (Dev)",
}
CHANNEL_ORDER = ["stable", "rc", "beta", "preview"]

# Неизменяемые имена файлов в rolling-релизе preview и latest-релизе stable.
PREVIEW_APK = "Noctwave-preview.apk"
PREVIEW_IPA = "Noctwave-preview.ipa"
STABLE_APK = "Noctwave.apk"
STABLE_IPA = "Noctwave.ipa"


def asset_urls(repo, channel, version):
    base = f"https://github.com/{repo}/releases"
    if channel == "stable":
        return {
            "download_url": f"{base}/latest",
            "apk_url": f"{base}/latest/download/{STABLE_APK}",
            "ipa_url": f"{base}/latest/download/{STABLE_IPA}",
        }
    if channel in ("beta", "rc"):
        tag = f"{base}/download/v{version}"
        return {
            "download_url": f"{base}/tag/v{version}",
            "apk_url": f"{tag}/Noctwave-v{version}.apk",
            "ipa_url": f"{tag}/Noctwave-v{version}.ipa",
        }
    # preview (rolling dev)
    return {
        "download_url": f"{base}/download/preview/{PREVIEW_IPA}",
        "apk_url": f"{base}/download/preview/{PREVIEW_APK}",
        "ipa_url": f"{base}/download/preview/{PREVIEW_IPA}",
    }


def build_app_entry(repo, channel, version):
    now = datetime.now(timezone.utc)
    description = (
        f"{APP_DESCRIPTION}\n\n"
        f"Канал: {channel}\n"
        f"Сборка: {version}\n"
        f"Обновлено: {now.strftime('%Y-%m-%d %H:%M UTC')}"
    )
    return {
        "name": CHANNEL_APP_NAMES[channel],
        "bundleIdentifier": BUNDLE_ID,
        "developerName": DEVELOPER_NAME,
        "localizedDescription": description,
        "iconURL": f"https://raw.githubusercontent.com/{repo}/main/{ICON_PATH}",
        "version": version,
        "versionDate": now.isoformat(),
        "downloadURL": asset_urls(repo, channel, version)["ipa_url"],
        "tintColor": TINT_COLOR,
        "channel": channel,
    }


def fetch_published_apps(repo):
    url = f"https://raw.githubusercontent.com/{repo}/gh-pages/apps.json"
    try:
        with urllib.request.urlopen(url, timeout=15) as r:
            data = json.loads(r.read().decode("utf-8"))
        apps = data.get("apps", [])
        return apps if isinstance(apps, list) else []
    except Exception as e:
        print(f"WARN: cannot fetch published apps.json ({e}); starting fresh", file=sys.stderr)
        return []


def build_source(repo, channel, version):
    entry = build_app_entry(repo, channel, version)
    apps = []
    for a in fetch_published_apps(repo):
        if (isinstance(a, dict)
                and a.get("channel") in CHANNEL_ORDER
                and a.get("channel") != channel
                and a.get("name") != entry["name"]):
            a = dict(a)
            a["bundleIdentifier"] = BUNDLE_ID
            a["developerName"] = DEVELOPER_NAME
            apps.append(a)
    apps.append(entry)
    apps.sort(key=lambda a: CHANNEL_ORDER.index(a.get("channel"))
              if a.get("channel") in CHANNEL_ORDER else len(CHANNEL_ORDER))
    return {
        "name": "Noctwave",
        "identifier": "noctwave-app",
        "sourceURL": f"https://raw.githubusercontent.com/{repo}/gh-pages/apps.json",
        "apps": apps,
    }


def main():
    ap = argparse.ArgumentParser(description="Фиды версий и GBox/AltStore-источник")
    ap.add_argument("--channel", required=True, choices=["stable", "beta", "rc", "preview"])
    ap.add_argument("--version", required=True)
    ap.add_argument("--build-number", type=int, required=True)
    ap.add_argument("--commit-sha", default="")
    ap.add_argument("--repo", required=True, help="OWNER/REPO")
    ap.add_argument("--out-dir", default="dist_version")
    args = ap.parse_args()

    repo = args.repo
    channel = args.channel
    urls = asset_urls(repo, channel, args.version)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []

    # 1) Канальные фиды обновлений
    if channel in ("stable", "beta", "rc"):
        feed = {
            "version": args.version,
            "build": args.build_number,
            "critical": False,
            "min_supported_build": 1,
            "changelog": "Подробности — на странице релиза на GitHub.",
            "changelog_url": urls["download_url"],
            "download_url": urls["download_url"],
            "apk_url": urls["apk_url"],
            "ipa_url": urls["ipa_url"],
            "channel": "stable" if channel == "stable" else channel,
            "prerelease": channel != "stable",
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        if args.commit_sha:
            feed["commit_sha"] = args.commit_sha
        feed_name = "version.json" if channel == "stable" else "beta.json"
        (out_dir / feed_name).write_text(
            json.dumps(feed, indent=2, ensure_ascii=False), encoding="utf-8")
        written.append(feed_name)

    # 2) Единый GBox/AltStore-источник
    source = build_source(repo, channel, args.version)
    source_json = json.dumps(source, indent=2, ensure_ascii=False)
    for filename in ("apps.json", "apps-beta.json"):
        (out_dir / filename).write_text(source_json, encoding="utf-8")
        written.append(filename)

    print(f"Generated in {out_dir}: {', '.join(written)}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
tools/publish_release.py — публикация GitHub Release с APK + IPA.

Каналы:
  stable  — обычный релиз по тегу v1.0.0 (не prerelease), имена файлов
            неизменные (Noctwave.apk / Noctwave.ipa) для ссылок latest/download.
  beta|rc — иммутабельный prerelease v1.0.0-beta.N, имена с версией.
  preview — ОДИН rolling-prerelease с тегом `preview`: файлы заменяются
            (--clobber), релизы не плодятся.

Использует gh CLI (GITHUB_TOKEN / GH_TOKEN из окружения).
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path


def run(cmd, check=True):
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, check=check)


def main():
    ap = argparse.ArgumentParser(description="Публикация релиза Noctwave")
    ap.add_argument("--channel", required=True, choices=["stable", "beta", "rc", "preview"])
    ap.add_argument("--version", required=True)
    ap.add_argument("--build-number", type=int, required=True)
    ap.add_argument("--commit-sha", default="")
    ap.add_argument("--target", default="main",
                    help="target_commitish для создания релиза: ПОЛНЫЙ sha "
                         "(40 символов) или имя ветки. Короткий sha "
                         "отклоняется API с 422.")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--apk", default=None)
    ap.add_argument("--ipa", default=None)
    args = ap.parse_args()

    if not args.apk and not args.ipa:
        sys.exit("Нужен хотя бы один артефакт: --apk или --ipa")

    channel = args.channel
    version = args.version

    # Готовим файлы с канальными именами.
    staged = Path("dist_release")
    staged.mkdir(parents=True, exist_ok=True)
    files = []
    if args.apk:
        if channel == "stable":
            name = "Noctwave.apk"
        elif channel == "preview":
            name = "Noctwave-preview.apk"
        else:
            name = f"Noctwave-v{version}.apk"
        dst = staged / name
        dst.write_bytes(Path(args.apk).read_bytes())
        files.append(str(dst))
    if args.ipa:
        if channel == "stable":
            name = "Noctwave.ipa"
        elif channel == "preview":
            name = "Noctwave-preview.ipa"
        else:
            name = f"Noctwave-v{version}.ipa"
        dst = staged / name
        dst.write_bytes(Path(args.ipa).read_bytes())
        files.append(str(dst))

    repo = args.repo
    if channel == "preview":
        # Rolling-prerelease: создаём если нет, затем заменяем файлы.
        tag = "preview"
        title = f"Noctwave preview {version}"
        notes = (
            f"Rolling dev-сборка main.\n\n"
            f"Версия: {version}\n"
            f"Build: {args.build_number}\n"
            f"Commit: {args.commit_sha}\n\n"
            f"Этот релиз перезаписывается каждым push в main."
        )
        exists = run(
            ["gh", "release", "view", tag, "--repo", repo], check=False
        ).returncode == 0
        if not exists:
            run([
                "gh", "release", "create", tag, "--repo", repo,
                "--prerelease", "--title", title, "--notes", notes,
                "--target", args.target,
            ])
        run([
            "gh", "release", "upload", tag, "--repo", repo, "--clobber", *files,
        ])
        run([
            "gh", "release", "edit", tag, "--repo", repo,
            "--title", title, "--notes", notes,
        ])
    else:
        tag = f"v{version}"
        title = f"Noctwave {version}"
        notes = (
            f"Версия: {version}\n"
            f"Канал: {channel}\n"
            f"Build: {args.build_number}\n"
            f"Commit: {args.commit_sha}"
        )
        cmd = [
            "gh", "release", "create", tag, "--repo", repo,
            "--title", title, "--notes", notes, *files,
        ]
        if channel != "stable":
            cmd.insert(cmd.index("--title"), "--prerelease")
        run(cmd)

    print(f"Published {channel} release {version} with {len(files)} file(s)")


if __name__ == "__main__":
    main()

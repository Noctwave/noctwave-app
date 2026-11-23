#!/usr/bin/env python3
"""
tools/versioning.py — единый генератор версий для CI Noctwave (по образцу
эталонного krasava-app/tools/versioning.py, адаптировано под Flutter).

Каналы и форматы:
  stable   тег v1.0.0 / v1.0.1      → версия 1.0.0
  beta|rc  тег v1.0.0-beta.1        → версия 1.0.0-beta.1 (prerelease)
  dev      push в main              → {RELEASE_VERSION}-dev.<номер линии>

Числовой BUILD_NUMBER (Android versionCode / iOS CFBundleVersion) =
epoch-секунды, вычисленные ОДИН раз в resolve-джобе. Все джобы берут
готовое число через --build-id ${{ needs.resolve.outputs.build_id }}.
Влезает в Int32 (max 2147483647).

Версия линии разработки живёт ТОЛЬКО в pubspec.yaml (поле version без
+build). Полные версии с суффиксами CI подставляет через --build-name /
--build-number флаги flutter build — файлы в репо не патчатся.

Команды:
  resolve — вычислить версию и вывести в $GITHUB_OUTPUT
  prepare — то же + вывести флаги flutter build (build_flags)
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

PUBSPEC_FILE = "pubspec.yaml"

# v1.0.0 | v1.0 | v1.0.0-beta.1 | v1.0.0-rc.2
TAG_RE = re.compile(r"^v(\d+\.\d+(?:\.\d+)?)(?:-(beta|rc)\.(\d+))?$")

MAX_BUILD_ID = 2_147_483_647


def read_release_version():
    content = Path(PUBSPEC_FILE).read_text(encoding="utf-8")
    m = re.search(r"^version:\s*(\d+\.\d+(?:\.\d+)?)", content, re.MULTILINE)
    if not m:
        sys.exit(f"Не найдена версия в {PUBSPEC_FILE}")
    version = m.group(1)
    # Нормализуем к трём компонентам: 1.0 → 1.0.0
    parts = version.split(".")
    while len(parts) < 3:
        parts.append("0")
    return ".".join(parts)


def short_sha():
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"], text=True
        ).strip()
    except Exception:
        sha = os.environ.get("GITHUB_SHA", "local")
        return sha[:8] if sha else "local"


def compute_build_id(build_time):
    if build_time:
        dt = datetime.fromisoformat(build_time.replace("Z", "+00:00"))
        bid = int(dt.timestamp())
    else:
        bid = int(datetime.now(timezone.utc).timestamp())
    if bid > MAX_BUILD_ID:
        sys.exit(f"build id {bid} превышает Int32 max ({MAX_BUILD_ID})")
    return bid


def next_dev_number(prev_version, release_version):
    """Номер дев-сборки текущей линии: 1.0.0-dev.17 → 18; смена линии → 1."""
    m = prev_version and re.search(r"(\d+\.\d+\.\d+)-dev\.(\d+)", prev_version)
    if m and m.group(1) == release_version:
        return int(m.group(2)) + 1
    return 1


def resolve(channel, tag, build_id, prev_version=None):
    release_version = read_release_version()
    if tag:
        m = TAG_RE.match(tag.strip())
        if not m:
            sys.exit(
                f"Некорректный тег '{tag}'. Ожидается v1.0.0, v1.0.1, "
                f"v1.0.0-beta.1 или v1.0.0-rc.1"
            )
        version = m.group(1)
        channel = m.group(2) or "stable"
        if m.group(2):
            version += f"-{m.group(2)}.{m.group(3)}"
    elif channel == "dev":
        version = f"{release_version}-dev.{next_dev_number(prev_version, release_version)}"
    else:
        sys.exit("Для stable/beta/rc нужен --tag, для dev — --channel dev")

    # iOS CFBundleShortVersionString любит числовую базу без суффикса.
    numeric_core = version.split("-")[0]

    return {
        "version": version,
        "numeric_version": numeric_core,
        "channel": channel,
        "prerelease": "true" if channel != "stable" else "false",
        "build_id": str(build_id),
        "commit_sha": short_sha(),
        "prev_version": prev_version or "",
        "build_flags": f"--build-name={numeric_core} --build-number={build_id}",
    }


def emit(info):
    out_file = os.environ.get("GITHUB_OUTPUT")
    if out_file:
        with open(out_file, "a", encoding="utf-8") as f:
            for k, v in info.items():
                f.write(f"{k}={v}\n")
    print("==========================================")
    print("VERSION RESOLVED")
    print(json.dumps(info, indent=2, ensure_ascii=False))
    print("==========================================")


def main():
    ap = argparse.ArgumentParser(description="Единый генератор версий CI Noctwave")
    ap.add_argument("command", choices=["resolve", "prepare"])
    ap.add_argument("--channel", default=None, help="dev (для тегов канал выводится из тега)")
    ap.add_argument("--tag", default=None, help="v1.0.0 | v1.0.0-beta.1 | v1.0.0-rc.1")
    ap.add_argument("--prev-version", default=None,
                    help="Имя rolling-релиза preview: предыдущий номер линии +1")
    ap.add_argument("--build-id", type=int, default=None,
                    help="Готовый BUILD_NUMBER из needs.resolve.outputs.build_id")
    ap.add_argument("--build-time", default=None, help="ISO8601 для локальных тестов")
    args = ap.parse_args()

    if not args.tag and not args.channel:
        sys.exit("Нужен --tag или --channel")

    build_id = args.build_id if args.build_id else compute_build_id(args.build_time)
    info = resolve(args.channel, args.tag, build_id, args.prev_version)
    emit(info)


if __name__ == "__main__":
    main()

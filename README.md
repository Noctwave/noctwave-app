# Noctwave App (PulseLocal)

Кроссплатформенное мобильное приложение (Flutter) для локального управления
BLE-устройствами через **BLE Advertising** — автономная offline-first замена
официальному клиенту без аккаунтов, телеметрии и подписок.

Полное техническое задание: [code_artifact.md](code_artifact.md).

## Возможности

- **Протокол LoveSpouse**: 11-байтовый payload (8-байтовый префикс + 3-байтовая команда).
  - Android — `BluetoothLeAdvertiser` + `ManufacturerData (0xFFF0)`.
  - iOS — XOR pre-whitening маска + упаковка в шесть 16-битных `CBUUID`
    (обход запрета `ManufacturerData` в `CoreBluetooth`).
- **TX-планировщик**: квантование сигнала, дедупликация, троттлинг 4–6 Гц,
  burst-окна 350/700 мс, приоритетная команда СТОП.
- **Импорт профилей**: по коду / QR (API zlmicro, однократный запрос),
  оффлайн-база пресетов, ручное создание.
- **Режимы управления**: Пульт (мультиканальность, Hold-to-Boost),
  Жест (1D-кривая / 2D XY-пэд + Loop), Ритмы (запись REC, плеер),
  Автопилот (Wave / Pulse / Ramp / Chaos).
- **Debug Mode**: Сыщик команд (Command Hunter), HEX-инжектор,
  инспектор пакетов (RAM ring-buffer 200), тюнинг таймингов движка.
- **OLED-замок**: истинный чёрный, wakelock, разблокировка удержанием,
  «Громкость вниз» = экстренный СТОП.
- **Zero telemetry**: никаких аналитических SDK; логи Debug Mode — только в RAM.

## Структура

```
lib/
  app.dart                     # Корневой виджет, тема, навигация
  core/
    ble/
      love_spouse_codec.dart   # Кодирование пакетов (вектор из ТЗ 5.3)
      ble_advertiser.dart      # MethodChannel мост к нативному BLE-слою
      tx_scheduler.dart        # Планировщик передачи (burst/throttle/stop)
    models/                    # DeviceProfile, каналы, пресеты, ритмы
  features/
    devices/                   # Список устройств, добавление, empty state
    control/                   # Экран управления + OLED-замок
    profile/                   # Локальные настройки
android/.../BleAdvertiserPlugin.kt   # Нативный рекламщик (Kotlin)
ios/Runner/BleAdvertiserPlugin.swift # Нативный рекламщик (Swift/CoreBluetooth)
test/                          # Unit-тесты (контрольный вектор обязателен)
.github/workflows/ci.yml       # CI: analyze + test + APK + iOS no-codesign
```

## Разработка

```bash
flutter pub get
flutter analyze
flutter test
flutter run                # Android-устройство
flutter build apk --release
flutter build ios --release --no-codesign
```

Требования: Flutter stable (Dart 3.x), Android SDK (minSdk 29), Xcode 15+ для iOS.

## CI и дистрибуция

GitHub Actions на каждый push/PR в `main`:

1. **Resolve Build Version** — единый номер сборки на весь запуск
   (`tools/versioning.py`): push в main → `1.0.0-dev.N` (rolling),
   тег `v1.0.0` → stable, `v1.0.0-beta.N` / `-rc.N` → prerelease.
2. **Analyze & Unit Tests** — `flutter analyze` + `flutter test --coverage`.
3. **Build Android APK** — релизный `.apk` → artifact.
4. **Build iOS** — сборка без подписи (`--no-codesign`), `.ipa` → artifact.
5. **Push в main** → rolling-prerelease [`preview`](https://github.com/Noctwave/noctwave-app/releases/tag/preview)
   (один релиз, файлы перезаписываются) + обновление GBox/AltStore-источника.
6. **Тег `v*`** → GitHub Release с APK + IPA + фиды версий на `gh-pages`.

### Установка iOS (GBox / AltStore / SideStore)

Добавьте источник (Source) в GBox/AltStore:

```
https://raw.githubusercontent.com/Noctwave/noctwave-app/gh-pages/apps.json
```

Источник содержит все каналы: **Noctwave** (stable), **Noctwave (Dev)**
(preview-сборки main). IPA неподписанный — подпись выполняется при
установке через GBox/AltStore/SideStore вашим сертификатом.

### Фиды версий (gh-pages)

| Файл | Назначение |
| :--- | :--- |
| `apps.json` / `apps-beta.json` | Единый GBox/AltStore-источник (все каналы) |
| `version.json` | Stable-фид обновлений (версия, build, apk_url, ipa_url) |
| `beta.json` | Beta/RC-фид обновлений |

Ссылки: `https://noctwave.github.io/noctwave-app/apps.json` (после первого
деплоя gh-pages) либо raw-адрес выше.

## Безопасность и приватность

- Разрешения запрашиваются строго по факту использования (камера — QR-сканер,
  микрофон — режим «Микрофон»).
- Cleartext HTTP разрешён только для `lovespouse.zlmicro.com` (одноразовый
  импорт профиля по коду).
- Все данные хранятся локально; экспорт/импорт базы в один `.json`.

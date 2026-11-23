# Noctwave App (PulseLocal)

Кроссплатформенное мобильное приложение (Flutter) для локального управления
BLE-устройствами через **BLE Advertising** — автономная offline-first замена
официальному клиенту без аккаунтов, телеметрии и подписок.

Полное техническое задание: [code_artifact.md](code_artifact.md).

## Возможности (MVP)

- **Протокол LoveSpouse**: 11-байтовый payload (8-байтовый префикс + 3-байтовая команда).
  - Android — `BluetoothLeAdvertiser` + `ManufacturerData (0xFFF0)`.
  - iOS — XOR pre-whitening маска + упаковка в шесть 16-битных `CBUUID`
    (обход запрета `ManufacturerData` в `CoreBluetooth`).
- **TX-планировщик**: квантование сигнала, дедупликация, троттлинг 4–6 Гц,
  burst-окна 350/700 мс, приоритетная команда СТОП.
- **UI**: OLED Dark дизайн-система, вкладки «Устройства»/«Профиль»,
  экран управления с нижним доком (TX · REC · СТОП), оверлей OLED-замка.
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

## CI

GitHub Actions на каждый push/PR в `main`:

1. **Analyze & Unit Tests** — `flutter analyze` + `flutter test --coverage`.
2. **Build Android APK** — релизный `.apk` выгружается как artifact.
3. **Build iOS** — сборка без подписи (`--no-codesign`), `.zip` с `Runner.app`
   выгружается как artifact.

## Безопасность и приватность

- Разрешения запрашиваются строго по факту использования (камера — QR-сканер,
  микрофон — режим «Микрофон»).
- Cleartext HTTP разрешён только для `lovespouse.zlmicro.com` (одноразовый
  импорт профиля по коду).
- Все данные хранятся локально; экспорт/импорт базы в один `.json`.

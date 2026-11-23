Открытых исходников самого LoveSpouse нет — разработчик (**Weibu IoT / 威步智能物联**, Bundle ID `com.life.LoveSpouse`) держит код закрытым. Зато сообщество достаточно глубоко отреверсило и APK, и сам радиопротокол, и нашлась **одна критически важная деталь**, которая сильно упростит разработку **Noctwave**.

### Главная находка: под капотом это BroadLink Fastcon BLE

Реверс через Ghidra показал, что протокол LoveSpouse / MuSe / Leten — это не уникальная разработка, а стандартный **Fastcon BLE (от BroadLink)**, на котором также работают дешёвые китайские BLE-лампочки (BRmesh / brLight).

Почему это важно для твоего парсера API:

* Эндпоинт `zlmicro.com` возвращает **не готовые BLE-байты** (`6D B6 43...`), а сырой `BroadcastPrefix` (например, `"77 62 4d 53 45"`, что в ASCII читается как `"wbMSE"`) и короткую 1-байтовую команду (например, `"30"` для стопа).
* Внутри приложения эти сырые данные прогоняются через функцию **`get_rf_payload(prefix, command)`** (добавляется заголовок, CRC16 и выполняется BLE whitening), и именно она на выходе выдаёт готовые 11 байт для эфира: `6D B6 43 CE 97 FE 42 7C E5 15 7D`.
* **Плюс для Noctwave:** если один раз переписать `get_rf_payload` на Dart/Kotlin, приложению не придётся гадать или хранить таблицы под каждое семейство — оно сможет на лету собирать валидные BLE-пакеты из *любого* JSON-ответа `zlmicro.com`, включая редкие модели и игрушки-клоны (MuSe, Leten).

---

### Что известно про API `zlmicro.com` и базы устройств

* **Один бэкенд на несколько брендов:** домены `*.zlmicro.com` (ThinkPHP-движок с маршрутами `index.php?g=App&m=Diyapp&a=...`) обслуживают сразу **LoveSpouse**, **MuSe (暮瑟)** и часть **Leten**.
* **Открытый каталог:** публично задокументирован эндпоинт `getproductdetail&barcode={code}&userid=-1`. Авторизация там не требуется, а коды моделей — это обычные числа. Исследователи в треде Buttplug.io выгружали оттуда базу целиком — в ней **более 1000 моделей**.
* **Готовых публичных дампов БД** на GitHub почти не выкладывают, но при желании ты можешь один раз аккуратно прогнать скрипт по `barcode` и собрать компактный оффлайн-справочник (без картинок тысяча профилей займёт пару сотен килобайт в сжатом JSON/SQLite), зашив его прямо в **Noctwave**.
* **Известные префиксы семейств** (для оффлайн-базы и режима «не знаю код»):
* `wbMSE` (`77 62 4d 53 45`) → `6D B6 43 CE 97 FE 42 7C` (самое массовое семейство)
* `wbspy` → `6D B6 43 F2 53 82 42 7C`
* `wb162343` → `6D B6 43 AE 99 24 42 7C`
* `wb4B9665` → `6D B6 43 CA 34 9E 42 7C`
* Пятый префикс и таблицы команд нагрева/вакуума лежат в открытом коде `love-spouse-controller`.



---

### Полезные open-source репозитории (откуда брать код и таблицы)

* **[buttplugio/docs.buttplug.io #2](https://github.com/buttplugio/docs.buttplug.io/issues/2)** — главная база знаний по протоколу. Внутри есть:
* декомпилированный Java-код `get_rf_payload`;
* раскладка 2-канальных команд (`D5..D6` для 1-го канала, `A5..A6` для 2-го, причём у моделей с подсветкой 2-й канал управляет цветом LED);
* точная формула iOS pre-whitening XOR;
* важный баг/особенность прошивок: часть паттернов (например, `0xE0B82A`) меняет ритм в момент, когда реклама *прекращается*, поэтому для некоторых команд важно не рвать вещание слишком короткими паузами.


* **[hirusha-adi/love-spouse-controller](https://github.com/hirusha-adi/love-spouse-controller)** *(MIT, Kotlin)* — самый свежий оффлайн Android-контроллер. Оттуда стоит взять готовый каталог из 5 префиксов, команды для 9 режимов вибрации, нагрева и 5 уровней всасывания, а также идею режима **All-prefix cycle** (перебор всех 5 префиксов по ~300 мс, если код игрушки неизвестен).
* **[Sfrl79/ble-toy-mcp](https://github.com/Sfrl79/ble-toy-mcp)** — проект управления семейством MuSe / LoveSpouse / Leten, в документации хорошо разобрана связка `*.zlmicro.com` + `getproductdetail` и маркеры для самостоятельного поиска констант в свежих APK (`6d b6 43` / `42 7c`).
* **[Fi0nee/LS-Buttplug](https://github.com/Fi0nee/LS-Buttplug)** и **[Fi0nee/BLE-HEX-Picker](https://github.com/Fi0nee)** — помимо шлюза под ESP32, там есть отдельная утилита `BLE-HEX-Picker` для перебора HEX-команд. Хороший референс для твоего Debug Mode («Сыщик команд»).
* **[Wilaz/LVS-Gateway](https://github.com/Wilaz/LVS-Gateway)** и **[IngeniousKink/LVS-Gateway](https://github.com/IngeniousKink/LVS-Gateway)** — ESP32-прошивки с таблицами команд для MuSe / LoveSpouse / Leten.
* **[Penta0308/LS-Intiface-Bridge](https://github.com/Penta0308/LS-Intiface-Bridge)** — чистый референс Android `BluetoothLeAdvertiser` (флаги legacy / connectable / scannable + `0xFFF0`) и маппинг уровней `0..20`.
* **[simondankelmann/Bluetooth-LE-Spam](https://github.com/simondankelmann/Bluetooth-LE-Spam)** — среди прочего содержит готовый «Lovespouse Stop List» (список стоп-пакетов по разным устройствам — можно подсмотреть для кнопки универсального СТОПа).
* **[ArcadeMachinist/brMeshMQTT](https://github.com/ArcadeMachinist/brMeshMQTT)** — чистая реализация `get_rf_payload` (BroadLink Fastcon BLE), если понадобится перепроверить математику CRC16 и whitening.

Если захочешь, я могу прямо сейчас расписать полную реализацию связки **`zlmicro JSON` → `get_rf_payload` → Android `ManufacturerData` / iOS `CBUUID**` и проверить её на контрольном примере (`wbMSE` + `30` → `6DB643CE97FE427CE5157D` → 6 iOS UUID), чтобы этот блок у тебя сразу работал без сюрпризов.
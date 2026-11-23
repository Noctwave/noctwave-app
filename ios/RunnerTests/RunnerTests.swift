import Flutter
import Testing
import UIKit

@testable import Runner

struct RunnerTests {

    // MARK: - Контрольный вектор ТЗ 5.3 (обязательный unit-тест)

    /// Вход: prefix = 6D B6 43 CE 97 FE 42 7C, command = E5 15 7D (СТОП).
    /// После XOR + 0x0B: F9 08 49 23 AE CB C1 D1 6E 9C 3D 0B.
    /// Ожидаемые CBUUID: 08F9 2349 CBAE D1C1 9C6E 0B3D.
    @Test func xorPreWhiteningReferenceVector() {
        let plugin = BleAdvertiserPlugin()
        let uuids = plugin.encodeUuids(prefixHex: "6DB643CE97FE427C", commandHex: "E5157D")
        #expect(uuids.count == 6)
        #expect(uuids.map { $0.uuidString } == ["08F9", "2349", "CBAE", "D1C1", "9C6E", "0B3D"])
    }

    /// Тот же префикс, команда максимума E6 8E 4F: первая пара UUID
    /// зависит только от префикса и остаётся 08F9.
    @Test func prefixPairStableAcrossCommands() {
        let plugin = BleAdvertiserPlugin()
        let uuids = plugin.encodeUuids(prefixHex: "6DB643CE97FE427C", commandHex: "E68E4F")
        #expect(uuids.count == 6)
        #expect(uuids.first?.uuidString == "08F9")
    }

    // MARK: - hexToBytes

    @Test func hexToBytesParsesMixedCase() {
        let bytes = BleAdvertiserPlugin.hexToBytes("6db643Ce97Fe427C")
        #expect(bytes == [0x6D, 0xB6, 0x43, 0xCE, 0x97, 0xFE, 0x42, 0x7C])
    }

    @Test func hexToBytesIgnoresSeparators() {
        let bytes = BleAdvertiserPlugin.hexToBytes("6D B6 43:CE-97 FE 42 7C")
        #expect(bytes.count == 8)
        #expect(bytes.first == 0x6D)
        #expect(bytes.last == 0x7C)
    }

    @Test func hexToBytesEmptyGivesEmpty() {
        #expect(BleAdvertiserPlugin.hexToBytes("").isEmpty)
    }

    // MARK: - Валидация пейлоада

    @Test func wrongPayloadLengthGivesNoUuids() {
        let plugin = BleAdvertiserPlugin()
        #expect(plugin.encodeUuids(prefixHex: "AABB", commandHex: "E5157D").isEmpty)
        #expect(plugin.encodeUuids(prefixHex: "6DB643CE97FE427C", commandHex: "E5").isEmpty)
    }

    /// Терминатор 0x0B всегда попадает в последнюю пару: младший байт
    /// последнего UUID = 0x3D (XOR 0x40 ^ 0x0B), старший = 0x0B.
    @Test func terminatorLandsInLastUuid() {
        let plugin = BleAdvertiserPlugin()
        let uuids = plugin.encodeUuids(prefixHex: "0000000000000000", commandHex: "000000")
        // raw[10] = 0x00 → encoded[10] = 0x40, encoded[11] = 0x0B.
        // Последняя пара: (encoded[10], encoded[11]) → UUID "0B40".
        #expect(uuids.last?.uuidString == "0B40")
    }
}

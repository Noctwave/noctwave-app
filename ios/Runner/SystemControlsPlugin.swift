import AVFoundation
import Flutter
import UIKit

/**
 * Системные функции OLED-замка (ТЗ 3.2.4), iOS:
 * - setKeepScreenOn → UIApplication.shared.isIdleTimerDisabled;
 * - «Громкость вниз» → событие volumeDown в Dart через наблюдение за
 *   AVAudioSession.outputVolume (hardware key events сторонним
 *   приложениям недоступны; громкость наблюдаем в foreground).
 */
class SystemControlsPlugin: NSObject, FlutterPlugin {
    static let channelName = "com.pulselocal/system_controls"

    private var channel: FlutterMethodChannel?
    private var volumeObservation: NSKeyValueObservation?
    private var lastVolume: Float = -1

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = SystemControlsPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.startVolumeObservation()
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setKeepScreenOn":
            let enabled = call.arguments as? Bool ?? false
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = enabled
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startVolumeObservation() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        lastVolume = session.outputVolume
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] sess, _ in
            guard let self = self else { return }
            let current = sess.outputVolume
            if self.lastVolume >= 0 && current < self.lastVolume {
                self.channel?.invokeMethod("volumeDown", arguments: nil)
            }
            self.lastVolume = current
        }
    }
}

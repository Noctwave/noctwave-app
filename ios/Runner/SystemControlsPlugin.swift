import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/**
 * Системные функции OLED-замка (ТЗ 3.2.4), iOS:
 * - setKeepScreenOn → UIApplication.shared.isIdleTimerDisabled;
 * - «Громкость вниз» → событие volumeDown в Dart.
 *
 * На iOS hardware key events сторонним приложениям недоступны. Используются
 * два механизма: скрытый MPVolumeView (системный слайдер громкости, работает
 * даже когда громкость уже на минимуме) и наблюдение AVAudioSession.outputVolume.
 * Повторные срабатывания подавляются дебаунсом.
 */
class SystemControlsPlugin: NSObject, FlutterPlugin {
    static let channelName = "com.pulselocal/system_controls"

    /// Сильная ссылка: инстанс не должен быть освобождён после register.
    private static var retainedInstance: SystemControlsPlugin?

    /// Дебаунс между событиями volumeDown, мс (два механизма не должны
    /// дублировать один и тот же СТОП).
    private static let volumeEventDebounceMs: Double = 300

    private var channel: FlutterMethodChannel?
    private var volumeObservation: NSKeyValueObservation?
    private var lastVolume: Float = -1
    private var lastEventAt: Date = .distantPast
    private var volumeView: MPVolumeView?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = SystemControlsPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        retainedInstance = instance
        instance.setupAudioSession()
        instance.startVolumeObservation()
        instance.installVolumeView()
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

    /// Аудиосессия .playback + .mixWithOthers: позволяет читать outputVolume
    /// и не прерывает музыку пользователя.
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func startVolumeObservation() {
        let session = AVAudioSession.sharedInstance()
        lastVolume = session.outputVolume
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] sess, _ in
            guard let self = self else { return }
            let current = sess.outputVolume
            if self.lastVolume >= 0 && current < self.lastVolume {
                self.emitVolumeDown()
            }
            self.lastVolume = current
        }
    }

    /// Скрытый MPVolumeView: при нажатии аппаратных кнопок громкости iOS
    /// меняет значение его слайдера — событие приходит даже когда системная
    /// громкость уже на минимуме и outputVolume не меняется.
    private func installVolumeView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
            view.showsRouteButton = false
            view.showsVolumeSlider = true
            view.alpha = 0.01
            if let window = Self.keyWindow() {
                window.addSubview(view)
            }
            self.volumeView = view
            if let slider = view.subviews.compactMap({ $0 as? UISlider }).first {
                slider.addTarget(self, action: #selector(self.volumeSliderChanged(_:)), for: .valueChanged)
            }
        }
    }

    @objc private func volumeSliderChanged(_ slider: UISlider) {
        // Любой скачок вниз по системному слайдеру = нажатие «громкость вниз».
        let previous = lastVolume
        let current = slider.value
        lastVolume = current
        if previous >= 0 && current < previous {
            emitVolumeDown()
        }
    }

    /// Шлёт событие в Dart не чаще раза в [volumeEventDebounceMs].
    private func emitVolumeDown() {
        let now = Date()
        guard now.timeIntervalSince(lastEventAt) * 1000 >= Self.volumeEventDebounceMs else { return }
        lastEventAt = now
        channel?.invokeMethod("volumeDown", arguments: nil)
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }
}

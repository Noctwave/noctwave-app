import AVFoundation
import Flutter
import UIKit

/**
 * Нативный PCM-декодер аудиофайлов для FFT-анализа (ТЗ 4.4).
 *
 * Читает локальный файл (MP3/M4A/WAV/FLAC) через AVAudioFile в
 * нормализованный Float32 PCM и стримит окна в Dart через EventChannel.
 * Dart-сторона прогоняет окна через FftAnalyser (40–150 Гц).
 *
 * Декод идёт в фоне; скорость стрима привязана к позиции плеера —
 * Dart запрашивает окно для конкретного момента времени (метод
 * windowAt), чтобы не было рассинхронизации и дрейфа.
 */
class PcmDecoderPlugin: NSObject, FlutterPlugin {
    static let channelName = "com.pulselocal/pcm_decoder"

    private static var retainedInstance: PcmDecoderPlugin?

    private var channel: FlutterMethodChannel?
    /// Декодированные сэмплы моно-микса и частота дискретизации.
    private var samples: [Float] = []
    private var sampleRate: Double = 44100
    private var loadedPath: String?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = PcmDecoderPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        retainedInstance = instance
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "load":
            let args = call.arguments as? [String: Any] ?? [:]
            let path = args["path"] as? String ?? ""
            loadFile(path: path, result: result)
        case "windowAt":
            let args = call.arguments as? [String: Any] ?? [:]
            let ms = args["positionMs"] as? Int ?? 0
            let size = args["fftSize"] as? Int ?? 1024
            result(window(atMs: ms, size: size))
        case "sampleRate":
            result(sampleRate)
        case "durationMs":
            result(samples.isEmpty ? 0 : Int(Double(samples.count) / sampleRate * 1000))
        case "unload":
            samples = []
            loadedPath = nil
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Декодирует файл в моно Float32 PCM (в фоне, чтобы не блокировать UI).
    private func loadFile(path: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let url = URL(fileURLWithPath: path)
                let file = try AVAudioFile(forReading: url)
                let format = file.processingFormat
                let frameCount = AVAudioFrameCount(file.length)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "DECODE_FAILED", message: "Не удалось создать буфер", details: nil))
                    }
                    return
                }
                try file.read(into: buffer)
                guard let channelData = buffer.floatChannelData else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "DECODE_FAILED", message: "Нет PCM-данных", details: nil))
                    }
                    return
                }
                let frames = Int(buffer.frameLength)
                let channels = Int(format.channelCount)
                // Моно-микс: усредняем каналы.
                var mono = [Float](repeating: 0, count: frames)
                if channels == 1 {
                    mono = Array(UnsafeBufferPointer(start: channelData[0], count: frames))
                } else {
                    for ch in 0..<channels {
                        let data = channelData[ch]
                        for i in 0..<frames {
                            mono[i] += data[i] / Float(channels)
                        }
                    }
                }
                DispatchQueue.main.async {
                    self.samples = mono
                    self.sampleRate = format.sampleRate
                    self.loadedPath = path
                    result([
                        "sampleRate": format.sampleRate,
                        "frames": frames,
                        "durationMs": Int(Double(frames) / format.sampleRate * 1000),
                    ])
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DECODE_FAILED", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    /// Возвращает окно из [size] сэмплов, заканчивающееся на позиции [atMs].
    /// Если позиция в начале файла — окно дополняется нулями слева.
    private func window(atMs: Int, size: Int) -> [Double] {
        guard !samples.isEmpty, size > 0 else { return [] }
        let endSample = Int(Double(atMs) / 1000.0 * sampleRate)
        let clampedEnd = min(max(endSample, 0), samples.count)
        let startSample = clampedEnd - size
        var window = [Double](repeating: 0, count: size)
        for i in 0..<size {
            let idx = startSample + i
            if idx >= 0 && idx < samples.count {
                window[i] = Double(samples[idx])
            }
        }
        return window
    }
}

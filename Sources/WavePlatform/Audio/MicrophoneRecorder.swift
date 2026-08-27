import AVFoundation
import Foundation
import WaveCore

/// Captures microphone audio as mono 16 kHz float PCM held in memory
/// (PRD §11.2). Nothing is written to disk at any point (PRD §21).
public actor MicrophoneRecorder: AudioRecording {
    /// What the STT engines expect. Whisper models are trained at 16 kHz.
    public static let targetSampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private let detector = SpeechDetector()
    private var samples: [Float] = []
    private var deviceName = "System Default"
    private var isRunning = false

    /// Called when a hand-picked microphone could not be selected and Wave fell
    /// back to the system default (PRD §11.1).
    private let onFallbackToDefault: @Sendable (String) -> Void

    public init(onFallbackToDefault: @escaping @Sendable (String) -> Void = { _ in }) {
        self.onFallbackToDefault = onFallbackToDefault
    }

    public func start(
        microphoneUniqueID: String?,
        onLevel: @escaping @Sendable (Float) -> Void
    ) async throws {
        guard !isRunning else { return }
        samples.removeAll(keepingCapacity: true)

        if let microphoneUniqueID {
            do {
                deviceName = try selectInputDevice(uniqueID: microphoneUniqueID)
            } catch {
                // The chosen microphone is gone. Fall back rather than fail,
                // and tell the user (PRD §11.1).
                deviceName = "System Default"
                onFallbackToDefault(microphoneUniqueID)
            }
        } else {
            deviceName = "System Default"
        }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw WaveError.microphoneUnavailable
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw WaveError.microphoneUnavailable
        }

        let detector = self.detector
        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            guard let converted = Self.convert(buffer, using: converter, to: targetFormat) else { return }
            onLevel(detector.level(samples: converted[...]))
            Task { await self?.append(converted) }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw WaveError.microphoneUnavailable
        }
        isRunning = true
    }

    public func stop() async -> CapturedAudio {
        guard isRunning else {
            return CapturedAudio(samples: [], sampleRate: Self.targetSampleRate, deviceName: deviceName)
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        let captured = samples
        // Release the audio as soon as it is handed over (PRD §21).
        samples = []
        return CapturedAudio(
            samples: captured,
            sampleRate: Self.targetSampleRate,
            deviceName: deviceName
        )
    }

    public func cancel() async {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        samples = []
    }

    private func append(_ newSamples: [Float]) {
        samples.append(contentsOf: newSamples)
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> [Float]? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1_024)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    /// Points the engine's input at a specific device. Throws if it is gone.
    private func selectInputDevice(uniqueID: String) throws -> String {
        guard let device = AudioDeviceLister.inputDevices().first(where: { $0.uniqueID == uniqueID }) else {
            throw WaveError.microphoneUnavailable
        }
        var deviceID = device.id
        let status = AudioUnitSetProperty(
            engine.inputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else { throw WaveError.microphoneUnavailable }
        return device.name
    }
}

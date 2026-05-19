import AVFoundation
import Foundation

/// Streaming PCM recorder. Captures the mic via `AVAudioEngine`, downsamples /
/// downmixes to 16 kHz mono Int16 little-endian, and yields the raw bytes
/// through an `AsyncStream<Data>`.
///
/// Used by the Phrase tab to feed Soniox real-time STT in the exact format the
/// service expects: `pcm_s16le` at 16000 Hz, 1 channel.
///
/// Lifecycle:
///   let recorder = PCMStreamRecorder()
///   let stream   = try recorder.start()      // throws on permission / engine fail
///   for await chunk in stream { /* send to WS */ }
///   recorder.stop()                          // also closes the AsyncStream
@MainActor
final class PCMStreamRecorder {
    enum RecorderError: LocalizedError {
        case permissionDenied
        case engineStartFailed(any Error)
        case converterUnavailable
        var errorDescription: String? {
            switch self {
            case .permissionDenied:           return "Microphone permission denied"
            case .engineStartFailed(let e):   return "Audio engine start failed: \(e.localizedDescription)"
            case .converterUnavailable:       return "Could not build PCM converter"
            }
        }
    }

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var continuation: AsyncStream<Data>.Continuation?
    private(set) var isRunning = false
    private(set) var chunksProduced = 0
    /// Watchdog timestamp — used so the orchestrator can detect a "WS open
    /// but mic starved" scenario (AVAudioEngine alive but installTap never
    /// fires, e.g. when WebRTC has exclusive control of the input bus).
    private(set) var startedAt: Date?
    /// Accumulated Int16 PCM bytes since `start()`. Used by the Bridge tab to
    /// stash the raw recording into a WAV file on `stop()` so we can ship it
    /// to the backend for offline Gemini + Soniox-async comparison.
    private var capturedPCM = Data()

    static let outputSampleRate: Double = 16_000

    /// `configureSession`: when `true` (default) the recorder switches the
    /// shared `AVAudioSession` into `.measurement` mode for clean PCM. Pass
    /// `false` when something else already configured the session — most
    /// importantly Bridge, where WebRTC needs `.voiceChat` for echo
    /// cancellation. In that case we tap the (voice-processed) input alongside
    /// WebRTC without touching the session category.
    func start(configureSession: Bool = true) async throws -> AsyncStream<Data> {
        guard !isRunning else {
            // already running — return a fresh empty stream
            let (stream, _) = AsyncStream<Data>.makeStream()
            return stream
        }
        guard await AudioSessionConfigurator.requestMicPermission() else {
            throw RecorderError.permissionDenied
        }
        if configureSession {
            AudioSessionConfigurator.configure(.measurement)
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // Surface degenerate input formats up front instead of silently
        // installing a tap that never fires. iOS occasionally returns a
        // sample-rate-zero format if `outputFormat(forBus:)` is called before
        // the audio session has finished negotiating the route.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            DiagLogger.shared.log(.audio, "PCM start aborted — degenerate input format \(inputFormat.sampleRate)Hz \(inputFormat.channelCount)ch")
            throw RecorderError.converterUnavailable
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.outputSampleRate,
            channels: 1,
            interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            DiagLogger.shared.log(.audio, "PCM start aborted — converter \(inputFormat.sampleRate)Hz \(inputFormat.channelCount)ch → 16kHz mono failed")
            throw RecorderError.converterUnavailable
        }
        self.engine = engine
        self.converter = converter

        let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.continuation = continuation

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        // Give the converter generous headroom so the resampler filter's tail
        // can produce its last block without truncation.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // Output capacity sized 2× the theoretical to absorb resampler
            // filter latency. Float32 inputs from AVAudioEngine downsampled to
            // Int16 16kHz mono.
            let theoretical = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 0.5)
            let outputCapacity = max(theoretical * 2, 256)
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                                   frameCapacity: outputCapacity)
            else { return }

            var error: NSError?
            var bufferDelivered = false
            // The converter is a streaming sample-rate-converter. It needs the
            // input via the closure, and may call the closure multiple times
            // per `convert(to:)` invocation. `.noDataNow` (vs `.endOfStream`)
            // tells the converter "no fresh input right now, but I might have
            // more later" — that's the correct status for a continuous tap.
            // The previous code used `.endOfStream` which caused the
            // converter to emit zero frames in some configurations.
            let status = converter.convert(to: outBuffer, error: &error) { _, inStatus in
                if bufferDelivered {
                    inStatus.pointee = .noDataNow
                    return nil
                }
                bufferDelivered = true
                inStatus.pointee = .haveData
                return buffer
            }

            if let error {
                if self.chunksProduced < 5 || self.chunksProduced % 100 == 0 {
                    DiagLogger.shared.log(.audio, "PCM convert error: \(error.localizedDescription)")
                }
                return
            }
            if status == .error {
                if self.chunksProduced < 5 || self.chunksProduced % 100 == 0 {
                    DiagLogger.shared.log(.audio, "PCM convert returned .error status")
                }
                return
            }
            guard let ptr = outBuffer.int16ChannelData?[0] else { return }
            let frameCount = Int(outBuffer.frameLength)
            let count = frameCount * MemoryLayout<Int16>.size
            guard count > 0 else {
                // Surface this loud and clear — it's the bug we just hunted
                // down. If the converter keeps returning 0 frames we want to
                // know about it without scrolling through 750 zero logs.
                if self.chunksProduced < 5 || self.chunksProduced % 100 == 0 {
                    DiagLogger.shared.log(.audio, "PCM tap fired but converter produced 0 frames (input \(buffer.frameLength) frames @ \(Int(inputFormat.sampleRate))Hz, status=\(status.rawValue))")
                }
                self.chunksProduced += 1
                return
            }
            let data = Data(bytes: ptr, count: count)
            self.continuation?.yield(data)
            self.capturedPCM.append(data)
            self.chunksProduced += 1
            if self.chunksProduced == 1 || self.chunksProduced % 100 == 0 {
                let n = self.chunksProduced
                DiagLogger.shared.log(.audio, "PCM chunk #\(n): \(count)B (\(frameCount) frames, total captured=\(self.capturedPCM.count)B)")
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.engine = nil
            self.continuation = nil
            DiagLogger.shared.log(.audio, "PCM engine.start FAILED — \(error.localizedDescription)")
            throw RecorderError.engineStartFailed(error)
        }
        isRunning = true
        startedAt = Date()
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputs = route.inputs.map { "\($0.portType.rawValue)/\($0.portName)" }.joined(separator: ",")
        let outputs = route.outputs.map { "\($0.portType.rawValue)/\($0.portName)" }.joined(separator: ",")
        DiagLogger.shared.log(.audio, "PCM streaming started (configureSession=\(configureSession), in=\(Int(inputFormat.sampleRate))Hz \(inputFormat.channelCount)ch → 16kHz mono, route: ←\(inputs) →\(outputs))")
        return stream
    }

    func stop() {
        guard isRunning else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        continuation?.finish()
        continuation = nil
        isRunning = false
        DiagLogger.shared.log(.audio, "PCM streaming stopped (\(chunksProduced) chunks total, \(capturedPCM.count)B captured)")
        chunksProduced = 0
    }

    /// Returns the captured PCM as a self-contained WAV file (16-bit mono
    /// 16kHz), written to a temp path. Returns `nil` if no audio was captured.
    /// Caller is responsible for cleanup.
    func writeCapturedWAV(filename: String) -> URL? {
        guard !capturedPCM.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        let sampleRate: UInt32 = UInt32(Self.outputSampleRate)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign: UInt16 = channels * bitsPerSample / 8
        let dataSize: UInt32 = UInt32(capturedPCM.count)
        let chunkSize: UInt32 = 36 + dataSize

        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8))
        header.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })   // subchunk1 size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian)  { Array($0) })   // PCM
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian)   { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian)   { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        header.append(contentsOf: Array("data".utf8))
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian)   { Array($0) })

        do {
            try (header + capturedPCM).write(to: url)
            DiagLogger.shared.log(.audio, "WAV written to \(url.lastPathComponent) — \(capturedPCM.count)B PCM, \(Double(capturedPCM.count) / Double(byteRate))s")
            return url
        } catch {
            DiagLogger.shared.log(.audio, "WAV write failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Drop any buffered PCM. Call after uploading the WAV.
    func clearCapture() {
        capturedPCM.removeAll(keepingCapacity: false)
    }
}

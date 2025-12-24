import AVFoundation
import Combine
import CoreAudio
import Foundation

final class AudioMonitor: ObservableObject, @unchecked Sendable {
    @Published var devices: [AudioDevice] = []
    @Published var selectedDeviceID: AudioDeviceID = 0
    @Published var level: Float = 0
    @Published var isRunning = false
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var isOverdubbing = false
    @Published var loopDuration: TimeInterval = 0
    @Published var chordName: String = "--"
    @Published var chordConfidence: Float = 0
    @Published var permissionStatus: String = "Unknown"
    @Published var lastError: String?

    private let deviceManager = AudioDeviceManager()
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let bufferSize: AVAudioFrameCount = 4096
    private let maxLoopSeconds: TimeInterval = 120

    private var isEngineConfigured = false
    private var inputFormat: AVAudioFormat?
    private var loopFormat: AVAudioFormat?
    private var loopBuffer: AVAudioPCMBuffer?
    private var chordEngine: ChordDetectionEngine?
    private let analysisQueue = DispatchQueue(label: "shred.audio.analysis")

    nonisolated(unsafe) private var loopSamples: [Float] = []
    nonisolated(unsafe) private var loopFrameCount = 0
    nonisolated(unsafe) private var recordingSamples: [Float] = []
    nonisolated(unsafe) private var recordWriteIndex = 0
    nonisolated(unsafe) private var overdubSamples: [Float] = []
    nonisolated(unsafe) private var overdubWriteIndex = 0
    nonisolated(unsafe) private var recordingActive = false
    nonisolated(unsafe) private var overdubActive = false
    nonisolated(unsafe) private var noDetectionCount = 0
    nonisolated(unsafe) private var lastDetectedChord = ""
    nonisolated(unsafe) private var chordHoldCount = 0
    nonisolated(unsafe) private var smoothedConfidence: Float = 0

    func refreshDevices() {
        let devices = deviceManager.inputDevices()
        updateOnMain {
            self.devices = devices
        }

        if let defaultID = deviceManager.defaultInputDeviceID(), devices.contains(where: { $0.id == defaultID }) {
            updateOnMain {
                self.selectedDeviceID = defaultID
            }
        } else if let first = devices.first {
            updateOnMain {
                self.selectedDeviceID = first.id
            }
        }
    }

    func selectDevice(_ deviceID: AudioDeviceID) {
        guard deviceID != 0 else { return }
        updateOnMain {
            self.selectedDeviceID = deviceID
        }
        deviceManager.setDefaultInputDevice(deviceID)
        if isRunning {
            restartMonitoring()
        }
    }

    func requestAccessAndStart() {
        updateOnMain {
            self.lastError = nil
        }
        updatePermissionStatus()

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startMonitoring()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.updatePermissionStatus()
                    if granted {
                        self.startMonitoring()
                    } else {
                        self.lastError = "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone."
                    }
                }
            }
        case .denied, .restricted:
            updateOnMain {
                self.lastError = "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone."
            }
        @unknown default:
            updateOnMain {
                self.lastError = "Microphone access unavailable."
            }
        }
    }

    func stopMonitoring() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        recordingActive = false
        overdubActive = false
        updateOnMain {
            self.isRunning = false
            self.level = 0
        }
    }

    func startRecording() {
        guard isRunning, !isRecording else { return }
        stopPlayback()

        guard let format = inputFormat else { return }
        let maxFrames = Int(format.sampleRate * maxLoopSeconds)
        recordingSamples = Array(repeating: 0, count: maxFrames)
        recordWriteIndex = 0
        recordingActive = true
        updateOnMain {
            self.isRecording = true
        }
        loopBuffer = nil
        loopSamples = []
        loopFrameCount = 0
        updateOnMain {
            self.loopDuration = 0
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        updateOnMain {
            self.isRecording = false
        }
        recordingActive = false

        let frames = recordWriteIndex
        guard frames > 0, let format = loopFormat ?? inputFormat else { return }
        loopFrameCount = frames
        loopSamples = Array(recordingSamples.prefix(frames))
        loopBuffer = makeBuffer(from: loopSamples, format: format)
        updateOnMain {
            self.loopDuration = Double(frames) / format.sampleRate
        }
    }

    func playLoop() {
        guard let buffer = loopBuffer else { return }
        guard isRunning else { return }

        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        playerNode.play()
        updateOnMain {
            self.isPlaying = true
        }
    }

    func stopPlayback() {
        playerNode.stop()
        updateOnMain {
            self.isPlaying = false
            self.isOverdubbing = false
        }
        overdubActive = false
    }

    func startOverdub() {
        guard !isRecording, loopFrameCount > 0 else { return }
        guard isRunning else { return }

        overdubSamples = Array(repeating: 0, count: loopFrameCount)
        overdubWriteIndex = 0
        overdubActive = true
        updateOnMain {
            self.isOverdubbing = true
        }

        if isPlaying {
            playerNode.stop()
        }
        if let buffer = loopBuffer {
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
            playerNode.play()
            updateOnMain {
                self.isPlaying = true
            }
        }
    }

    func stopOverdub() {
        guard isOverdubbing else { return }
        updateOnMain {
            self.isOverdubbing = false
        }
        overdubActive = false

        guard loopFrameCount > 0 else { return }
        for index in 0..<loopFrameCount {
            loopSamples[index] += overdubSamples[index]
        }

        if let format = loopFormat ?? inputFormat {
            loopBuffer = makeBuffer(from: loopSamples, format: format)
        }

        if isPlaying {
            playLoop()
        }
    }

    func clearLoop() {
        stopPlayback()
        updateOnMain {
            self.isRecording = false
        }
        recordingActive = false
        loopBuffer = nil
        loopSamples = []
        loopFrameCount = 0
        updateOnMain {
            self.loopDuration = 0
        }
    }

    private func restartMonitoring() {
        stopPlayback()
        stopMonitoring()
        startMonitoring()
    }

    private func startMonitoring() {
        guard !isRunning else { return }
        updateOnMain {
            self.lastError = nil
        }
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputFormat = format
        loopFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)
        chordEngine = ChordDetectionEngine(sampleRate: format.sampleRate, frameSize: Int(bufferSize))

        if !isEngineConfigured {
            engine.attach(playerNode)
            if let loopFormat {
                engine.connect(playerNode, to: engine.mainMixerNode, format: loopFormat)
            } else {
                engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            }
            isEngineConfigured = true
        }
        engine.mainMixerNode.outputVolume = 1.0
        playerNode.volume = 1.0

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            updateOnMain {
                self.isRunning = true
            }
        } catch {
            inputNode.removeTap(onBus: 0)
            updateOnMain {
                self.isRunning = false
                self.lastError = "Failed to start audio engine."
            }
        }
    }

    nonisolated func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let samples = channelData[0]

        if recordingActive {
            let remaining = recordingSamples.count - recordWriteIndex
            let copyCount = min(remaining, frameLength)
            if copyCount > 0 {
                for index in 0..<copyCount {
                    recordingSamples[recordWriteIndex + index] = samples[index]
                }
                recordWriteIndex += copyCount
            }
            if recordWriteIndex >= recordingSamples.count {
                DispatchQueue.main.async { [weak self] in
                    self?.stopRecording()
                }
            }
        }

        if overdubActive, loopFrameCount > 0 {
            for index in 0..<frameLength {
                let targetIndex = (overdubWriteIndex + index) % loopFrameCount
                overdubSamples[targetIndex] += samples[index]
            }
            overdubWriteIndex = (overdubWriteIndex + frameLength) % loopFrameCount
        }

        var sum: Float = 0
        for index in 0..<frameLength {
            let sample = samples[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        let clamped = min(max(rms * 12.0, 0), 1)

        updateOnMain { [weak self] in
            self?.level = clamped
        }

        analyzeChords(buffer: buffer)
    }

    nonisolated private func analyzeChords(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        analysisQueue.async { [weak self] in
            guard let self else { return }
            guard let engine = self.chordEngine else { return }
            if let detected = engine.analyze(samples: samples) {
                self.noDetectionCount = 0
                let minConfidence: Float = 0.2
                if detected.confidence >= minConfidence {
                    if detected.name == self.lastDetectedChord {
                        self.chordHoldCount += 1
                    } else {
                        self.chordHoldCount = 0
                        self.lastDetectedChord = detected.name
                    }
                    if self.chordHoldCount >= 2 {
                        self.smoothedConfidence = self.smoothedConfidence * 0.7 + detected.confidence * 0.3
                        let name = detected.name
                        let confidence = self.smoothedConfidence
                        self.updateOnMain {
                            self.chordName = name
                            self.chordConfidence = confidence
                        }
                    }
                }
            } else {
                self.noDetectionCount += 1
                if self.noDetectionCount >= 20 {
                    self.lastDetectedChord = ""
                    self.chordHoldCount = 0
                    self.smoothedConfidence = 0
                    self.updateOnMain {
                        self.chordName = "--"
                        self.chordConfidence = 0
                    }
                }
            }
        }
    }

    private func makeBuffer(from samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)
        let fadeSamples = min(Int(format.sampleRate * 0.005), max(samples.count / 2, 1))
        let totalSamples = samples.count
        for index in 0..<totalSamples {
            var sample = samples[index]
            if index < fadeSamples {
                sample *= Float(index) / Float(fadeSamples)
            } else if index >= totalSamples - fadeSamples {
                sample *= Float(totalSamples - index) / Float(fadeSamples)
            }
            channelData[0][index] = sample
            if channelCount > 1 {
                for channel in 1..<channelCount {
                    channelData[channel][index] = sample
                }
            }
        }
        return buffer
    }

    private func updatePermissionStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            updateOnMain {
                self.permissionStatus = "Granted"
            }
        case .notDetermined:
            updateOnMain {
                self.permissionStatus = "Not Determined"
            }
        case .denied:
            updateOnMain {
                self.permissionStatus = "Denied"
            }
        case .restricted:
            updateOnMain {
                self.permissionStatus = "Restricted"
            }
        @unknown default:
            updateOnMain {
                self.permissionStatus = "Unknown"
            }
        }
    }

    private func updateOnMain(_ work: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

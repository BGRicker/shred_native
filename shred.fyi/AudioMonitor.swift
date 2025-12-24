import AVFoundation
import Combine
import Foundation

final class AudioMonitor: ObservableObject {
    @Published var devices: [AudioDevice] = []
    @Published var selectedDeviceID: AudioDeviceID = 0
    @Published var level: Float = 0
    @Published var isRunning = false

    private let deviceManager = AudioDeviceManager()
    private let engine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount = 1024

    func refreshDevices() {
        let devices = deviceManager.inputDevices()
        self.devices = devices

        if let defaultID = deviceManager.defaultInputDeviceID(), devices.contains(where: { $0.id == defaultID }) {
            selectedDeviceID = defaultID
        } else if let first = devices.first {
            selectedDeviceID = first.id
        }
    }

    func selectDevice(_ deviceID: AudioDeviceID) {
        guard deviceID != 0 else { return }
        selectedDeviceID = deviceID
        deviceManager.setDefaultInputDevice(deviceID)
        if isRunning {
            restartMonitoring()
        }
    }

    func requestAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startMonitoring()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startMonitoring()
                    }
                }
            }
        default:
            break
        }
    }

    func stopMonitoring() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
    }

    private func restartMonitoring() {
        stopMonitoring()
        startMonitoring()
    }

    private func startMonitoring() {
        guard !isRunning else { return }
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            inputNode.removeTap(onBus: 0)
            isRunning = false
        }
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        let samples = channelData[0]
        for index in 0..<frameLength {
            let sample = samples[index]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        let clamped = min(max(rms * 12.0, 0), 1)

        DispatchQueue.main.async { [weak self] in
            self?.level = clamped
        }
    }
}

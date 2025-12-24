import CoreAudio
import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = AudioMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("shred.fyi")
                .font(.title)

            VStack(alignment: .leading, spacing: 8) {
                Text("Input Device")
                    .font(.headline)

                if monitor.devices.isEmpty {
                    Text("No input devices detected")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Input Device", selection: deviceSelectionBinding) {
                        ForEach(monitor.devices) { device in
                            Text(device.name)
                                .tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Input Level")
                    .font(.headline)

                ProgressView(value: monitor.level)
                    .progressViewStyle(.linear)

                Text("Microphone access: \(monitor.permissionStatus)")
                    .foregroundStyle(.secondary)

                if let error = monitor.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Chord Detection")
                    .font(.headline)

                Text(monitor.chordName)
                    .font(.title2)

                Text(String(format: "Confidence: %.2f", monitor.chordConfidence))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Looper")
                    .font(.headline)

                Text(loopDurationText)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button(monitor.isRecording ? "Stop Recording" : "Record") {
                        if monitor.isRecording {
                            monitor.stopRecording()
                        } else {
                            monitor.startRecording()
                        }
                    }
                    .disabled(!monitor.isRunning || monitor.isPlaying || monitor.isOverdubbing)

                    Button(monitor.isPlaying ? "Stop" : "Play") {
                        if monitor.isPlaying {
                            monitor.stopPlayback()
                        } else {
                            monitor.playLoop()
                        }
                    }
                    .disabled(monitor.isRecording || monitor.loopDuration == 0)

                    Button(monitor.isOverdubbing ? "Stop Overdub" : "Overdub") {
                        if monitor.isOverdubbing {
                            monitor.stopOverdub()
                        } else {
                            monitor.startOverdub()
                        }
                    }
                    .disabled(monitor.isRecording || monitor.loopDuration == 0)

                    Button("Clear") {
                        monitor.clearLoop()
                    }
                    .disabled(monitor.isRecording)
                }
            }

            HStack(spacing: 12) {
                Button(monitor.isRunning ? "Stop Monitoring" : "Start Monitoring") {
                    if monitor.isRunning {
                        monitor.stopMonitoring()
                    } else {
                        monitor.requestAccessAndStart()
                    }
                }

                Button("Refresh Devices") {
                    monitor.refreshDevices()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 360)
        .onAppear {
            monitor.refreshDevices()
            monitor.requestAccessAndStart()
        }
    }

    private var deviceSelectionBinding: Binding<AudioDeviceID> {
        Binding(
            get: { monitor.selectedDeviceID },
            set: { monitor.selectDevice($0) }
        )
    }

    private var loopDurationText: String {
        if monitor.loopDuration == 0 {
            return "No loop recorded"
        }
        return String(format: "Loop length: %.2f s", monitor.loopDuration)
    }
}

#Preview {
    ContentView()
}

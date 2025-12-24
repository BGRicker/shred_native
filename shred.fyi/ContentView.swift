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
        .frame(minWidth: 420, minHeight: 280)
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
}

#Preview {
    ContentView()
}

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("shred.fyi")
                .font(.title)
            Text("Scaffolding ready")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 240)
    }
}

#Preview {
    ContentView()
}

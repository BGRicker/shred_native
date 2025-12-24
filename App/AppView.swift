import ComposableArchitecture
import SwiftUI

struct AppView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            VStack(spacing: 16) {
                Text(viewStore.isAudioProcessing ? "Audio Running" : "Audio Stopped")
                    .font(.title2)

                Button(viewStore.isAudioProcessing ? "Stop" : "Start") {
                    viewStore.send(viewStore.isAudioProcessing ? .stopButtonTapped : .startButtonTapped)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(minWidth: 320, minHeight: 240)
        }
    }
}

#Preview {
    AppView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    )
}

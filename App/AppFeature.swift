import ComposableArchitecture

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var isAudioProcessing = false
    }

    enum Action: Equatable {
        case startButtonTapped
        case stopButtonTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .startButtonTapped:
                state.isAudioProcessing = true
                return .none
            case .stopButtonTapped:
                state.isAudioProcessing = false
                return .none
            }
        }
    }
}

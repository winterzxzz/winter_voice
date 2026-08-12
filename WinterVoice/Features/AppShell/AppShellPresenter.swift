import Combine

@MainActor
final class AppShellPresenter: ObservableObject {
    @Published private(set) var selection: AppShellDestination
    @Published private(set) var transcription: TranscriptionCapability

    let dictationPresenter: DictationPresenter
    private let interactor: AppShellInteracting
    private let router: AppRouter
    private var cancellables = Set<AnyCancellable>()

    init(
        dictationPresenter: DictationPresenter,
        interactor: AppShellInteracting,
        router: AppRouter
    ) {
        self.dictationPresenter = dictationPresenter
        self.interactor = interactor
        self.router = router
        selection = router.selection
        transcription = interactor.transcriptionCapability()
        router.$selection.assign(to: &$selection)
    }

    func navigate(to destination: AppShellDestination) {
        router.navigate(to: destination)
    }

    func refresh() {
        dictationPresenter.refreshPermissions()
        transcription = interactor.transcriptionCapability()
    }

    func activateApplication() {
        router.activateApplication()
    }
}

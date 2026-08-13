import Combine

@MainActor
final class AppShellPresenter: ObservableObject {
    @Published private(set) var selection: AppShellDestination
    let dictationPresenter: DictationPresenter
    let providerConfiguration: ProviderConfigurationStore
    let modelManager: ModelManager
    let history: HistoryStore
    let dictionary: DictionaryStore
    private let router: AppRouter
    private var cancellables = Set<AnyCancellable>()

    init(
        dictationPresenter: DictationPresenter,
        router: AppRouter,
        providerConfiguration: ProviderConfigurationStore,
        modelManager: ModelManager,
        history: HistoryStore,
        dictionary: DictionaryStore
    ) {
        self.dictationPresenter = dictationPresenter
        self.router = router
        self.providerConfiguration = providerConfiguration
        self.modelManager = modelManager
        self.history = history
        self.dictionary = dictionary
        selection = router.selection
        router.$selection.assign(to: &$selection)
        providerConfiguration.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        modelManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        history.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        dictionary.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func navigate(to destination: AppShellDestination) {
        router.navigate(to: destination)
    }

    func refresh() {
        dictationPresenter.refreshPermissions()
    }

    func activateApplication() {
        router.activateApplication()
    }

    var providerStatus: ProviderStatus {
        providerConfiguration.status(localModels: modelManager)
    }
}

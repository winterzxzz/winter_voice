import Combine

@MainActor
final class OnboardingPresenter: ObservableObject {
    @Published private(set) var isPresented: Bool
    @Published private var wizard = OnboardingWizard()

    let dictationPresenter: DictationPresenter
    private let interactor: OnboardingInteractor

    init(
        dictationPresenter: DictationPresenter,
        interactor: OnboardingInteractor
    ) {
        self.dictationPresenter = dictationPresenter
        self.interactor = interactor
        isPresented = interactor.shouldPresentOnLaunch(
            permissions: dictationPresenter.permissions
        )
    }

    var progress: OnboardingProgress {
        OnboardingProgress(permissions: dictationPresenter.permissions)
    }

    var nextPermission: AppPermission? {
        guard case .needsPermission(let permission) = progress else { return nil }
        return permission
    }

    var pageIndex: Int { wizard.pageIndex }
    var currentPermission: AppPermission { wizard.currentPermission }
    var canGoBack: Bool { wizard.canGoBack }
    var isLastPage: Bool { wizard.isLastPage }

    func back() { wizard.back() }

    func next() {
        if isLastPage {
            complete()
        } else {
            wizard.next()
        }
    }

    func performNextAction() {
        guard let nextPermission else { return }
        dictationPresenter.request(nextPermission)
    }

    func request(_ permission: AppPermission) {
        dictationPresenter.request(permission)
    }

    func openSystemSettings(for permission: AppPermission) {
        dictationPresenter.openSystemSettings(for: permission)
    }

    func refresh() {
        dictationPresenter.refreshPermissions()
    }

    func complete() {
        guard interactor.complete(with: dictationPresenter.permissions) else { return }
        isPresented = false
    }

    func deferForNow() {
        interactor.deferForNow()
        isPresented = false
    }

    func restart() {
        interactor.resetCompletion()
        dictationPresenter.refreshPermissions()
        wizard.reset()
        isPresented = true
    }
}

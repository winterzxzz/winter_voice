import SwiftUI

struct LaunchGateView: View {
    @ObservedObject var onboardingPresenter: OnboardingPresenter
    let shellPresenter: AppShellPresenter

    var body: some View {
        if onboardingPresenter.isPresented {
            OnboardingView(presenter: onboardingPresenter)
        } else {
            AppShellView(
                presenter: shellPresenter,
                onboardingPresenter: onboardingPresenter
            )
        }
    }
}

import SwiftUI

struct RecordingPanelView: View {
    @ObservedObject var presenter: DictationPresenter

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if presenter.state == .recording {
                    Circle().fill(.red).frame(width: 12, height: 12)
                } else if case .failed = presenter.state {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(presenter.statusTitle).font(.headline)
                if let detail = presenter.statusDetail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(minWidth: 260, maxWidth: 420, alignment: .leading)
        .background(.regularMaterial)
    }
}

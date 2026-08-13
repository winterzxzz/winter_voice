import SwiftUI

/// Dark, rounded, hairline-bordered input matching the reference UI. Applied to
/// `TextField`/`SecureField` via `.textFieldStyle(.wv)`.
struct WVTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        return configuration
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Theme.inset, in: shape)
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1))
    }
}

extension TextFieldStyle where Self == WVTextFieldStyle {
    static var wv: WVTextFieldStyle { WVTextFieldStyle() }
}

/// A labeled field stacked vertically: caption label above a `.wv` input.
struct WVField<Field: View>: View {
    let label: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.wvCaption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            field
        }
    }
}

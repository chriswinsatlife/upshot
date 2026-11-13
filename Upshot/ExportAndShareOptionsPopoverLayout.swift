import SwiftUI

struct ExportAndShareOptionsPopoverLayout<Header: View, Content: View>: View {
    let confirmTitle: String
    var isConfirmDisabled = false
    var width: CGFloat = 320
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    init(
        confirmTitle: String,
        isConfirmDisabled: Bool = false,
        width: CGFloat = 320,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.confirmTitle = confirmTitle
        self.isConfirmDisabled = isConfirmDisabled
        self.width = width
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            header()
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xxl)

            InterfaceFormPage {
                content()
            }
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.m) {
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isConfirmDisabled)
            }
            .buttonStyle(.interfaceAction)
            .padding(.horizontal, Space.xxl)
            .padding(.bottom, Space.xxl)
        }
        .frame(width: width)
    }
}

extension ExportAndShareOptionsPopoverLayout where Header == EmptyView {
    init(
        confirmTitle: String,
        isConfirmDisabled: Bool = false,
        width: CGFloat = 320,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            confirmTitle: confirmTitle,
            isConfirmDisabled: isConfirmDisabled,
            width: width,
            onCancel: onCancel,
            onConfirm: onConfirm,
            header: { EmptyView() },
            content: content
        )
    }
}

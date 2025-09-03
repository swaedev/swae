import SwiftUI

struct HCenter<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        HStack {
            Spacer()
            self.content()
            Spacer()
        }
    }
}

import SwiftUI

/// The clickable discipline chips under the header. A chip is a filter, not a
/// label: clicking it narrows the list to that group, clicking it again clears
/// the filter, and several chips can be on at once.
/// Stub: the chips work stream provides the real implementation.
struct PlatformFilterBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        EmptyView()
    }
}

enum FilterChecks {
    static func all() -> [(String, Bool)] { [] }
}

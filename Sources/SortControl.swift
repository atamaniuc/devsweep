import SwiftUI

/// The asc/desc control for the main list, next to the search box.
/// Stub: the sorting work stream provides the real menu.
struct SortControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        EmptyView()
    }
}

enum SortChecks {
    static func all() -> [(String, Bool)] { [] }
}

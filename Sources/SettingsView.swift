import SwiftUI

/// The Settings window (⌘,): low-disk alerts and saved view presets.
/// Stub: the settings work stream replaces this with the real tabs.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: AppModel

    var body: some View {
        Text(L("Настройки", "Settings"))
            .frame(width: 560, height: 420)
    }
}

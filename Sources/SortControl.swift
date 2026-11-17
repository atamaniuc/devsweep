import SwiftUI

/// Compact asc/desc control, shared by the main window and the dry-run sheet.
/// The menu picks the key (Size or Name); picking the already active key flips
/// the direction (`SortState.select`), and the arrow button flips it in one
/// click. The label always shows the current state ("Size ↓"), so the list
/// order never needs a legend.
struct SortPicker: View {
    @Binding var sort: SortState

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(SortKey.allCases) { key in
                    Button {
                        sort.select(key)
                    } label: {
                        Label {
                            Text(key.title)
                        } icon: {
                            if sort.key == key {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: key.symbol)
                            }
                        }
                    }
                }
                Divider()
                Button {
                    sort.flip()
                } label: {
                    Label(L("Переключить направление", "Flip direction"),
                          systemImage: "arrow.up.arrow.down")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: sort.key.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(sort.key.title)
                        .font(.system(size: 13, weight: .medium))
                    Text(sort.direction.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L("Сортировка: размер или название. Выберите ключ в меню; повторный выбор активного ключа меняет направление.",
                    "Sort by size or name. Pick a key in the menu; picking the active key again flips the direction."))

            Button {
                sort.flip()
            } label: {
                Image(systemName: sort.direction.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L("Сейчас \(sort.key.title): \(sort.direction.title). Нажмите, чтобы переключить направление.",
                    "Now \(sort.key.title): \(sort.direction.title). Click to flip the direction."))
            .accessibilityLabel(L("Направление сортировки", "Sort direction"))
        }
    }
}

/// The asc/desc control for the main list, next to the search box. Sorting is a
/// pure in-memory re-order of the scan result: the list, the group order and the
/// "Check all/Uncheck all" targets follow the published `model.sort` immediately.
struct SortControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SortPicker(sort: $model.sort)
    }
}

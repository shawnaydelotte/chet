import SwiftUI

struct CategoryLegend: View {
    @Environment(ScanState.self) private var state

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FileCategory.allCases) { cat in
                    let isHidden = state.hiddenCategories.contains(cat)

                    Button {
                        state.toggleCategory(cat)
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(cat.color)
                                .frame(width: 8, height: 8)
                                .opacity(isHidden ? 0.3 : 1)

                            Text(cat.displayName)
                                .font(.caption2)
                                .foregroundStyle(isHidden ? .tertiary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

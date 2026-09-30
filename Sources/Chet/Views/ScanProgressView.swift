import SwiftUI

struct ScanProgressView: View {
    @Environment(ScanState.self) private var state

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Scanning...")
                .font(.title3.weight(.medium))

            VStack(spacing: 4) {
                Text("\(state.filesScanned.formatted()) items scanned")
                    .monospacedDigit()

                Text(state.scanProgress)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 400)
            }
            .font(.caption)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

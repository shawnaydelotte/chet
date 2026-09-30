import SwiftUI

struct SidebarView: View {
    @Environment(ScanState.self) private var state

    var body: some View {
        Group {
            if let root = state.rootNode {
                List(selection: Binding(
                    get: { state.selectedNode?.id },
                    set: { id in
                        state.selectInSidebar(id.flatMap { findNode(id: $0, in: root) })
                    }
                )) {
                    OutlineGroup(root.sortedChildren, id: \.id, children: \.optionalChildren) { node in
                        SidebarRow(node: node)
                            .tag(node.id)
                    }
                }
                .listStyle(.sidebar)
            } else {
                Text("No scan data")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(state.rootNode?.name ?? "Chet")
    }

    private func findNode(id: UUID, in node: FileNode) -> FileNode? {
        if node.id == id { return node }
        for child in node.children {
            if let found = findNode(id: id, in: child) { return found }
        }
        return nil
    }
}

struct SidebarRow: View {
    @Environment(ScanState.self) private var state
    let node: FileNode

    private var barColor: Color {
        node.isDirectory ? .secondary : node.category.color
    }

    var body: some View {
        let _ = state.lastTreeMutation
        HStack(spacing: 6) {
            Image(systemName: node.isDirectory ? "folder.fill" : node.category.icon)
                .foregroundStyle(node.isDirectory ? .secondary : node.category.color)
                .frame(width: 16)

            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Text(SizeFormatter.format(node.size))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor.opacity(0.22))
                    .frame(width: max(2, proxy.size.width * node.relativeToSiblings))
            }
        }
        .contextMenu {
            if node.isDirectory {
                Button("Analyze This Directory") {
                    state.drillInto(node)
                }
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: node.url.path)
            }
        }
    }
}

extension FileNode {
    var optionalChildren: [FileNode]? {
        isDirectory && !children.isEmpty ? sortedChildren : nil
    }
}
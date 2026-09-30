import Observation
import SwiftUI

@Observable
@MainActor
final class HoverState {
    var hoveredNode: FileNode?
    var hoverLocation: CGPoint = .zero
}
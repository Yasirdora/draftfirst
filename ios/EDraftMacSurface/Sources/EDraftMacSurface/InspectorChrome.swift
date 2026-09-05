import EDraftCore
import Foundation
import SwiftUI

/// Presentation of the inspector, not its contents.
///
/// Hidden until summoned. Following the caret changes which section is
/// proposed; it must not open the pane — a third column that appears on
/// every arrow key is a narrower page, and the page is the product.
@Observable
@MainActor
final class InspectorChrome {
    var isPresented = false
    var segment: InspectorFocus = .title

    func follow(kind: ScreenplayKind?) {
        segment = InspectorFocus.proposed(for: kind)
    }

    func toggle() {
        isPresented.toggle()
    }
}

/// So the menu bar can summon the frontmost document's inspector.
public struct InspectorPresentedKey: FocusedValueKey {
    public typealias Value = Binding<Bool>
}

extension FocusedValues {
    public var inspectorPresented: Binding<Bool>? {
        get { self[InspectorPresentedKey.self] }
        set { self[InspectorPresentedKey.self] = newValue }
    }
}

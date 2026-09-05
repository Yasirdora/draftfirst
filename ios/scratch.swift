import Foundation
import SwiftUI
@testable import EDraftCore
@testable import EDraftMacSurface

@MainActor
func run() {
    let editor = EditorState(source: "")
    editor.reportEditing(true)
    let control = ElementModeControl(editor: editor)
    let mirror = String(describing: control.body)
    print("MIRROR:")
    print(mirror)
}
run()

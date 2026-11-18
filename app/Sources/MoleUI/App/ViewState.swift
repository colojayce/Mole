import SwiftUI

/// `@State` under the macOS 27 SDK resolves to the `State` macro, whose plugin
/// (SwiftUIMacros) ships only with Xcode. A type alias resolves to the property
/// wrapper instead, so CommandLineTools can build the app. Use `@ViewState`
/// wherever SwiftUI code would write `@State`.
typealias ViewState<Value> = SwiftUI.State<Value>

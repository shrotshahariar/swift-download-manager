import SwiftUI

/// Drop-in replacement for SwiftUI's `@State`.
///
/// On recent SDKs `@State` is a Swift macro whose compiler plugin ships only with full Xcode,
/// so it can't be built with the Command Line Tools alone. This wrapper stores the value in a
/// `@StateObject` box instead, which behaves the same for view-local state.
final class LocalBox<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}

@propertyWrapper
struct Local<T>: DynamicProperty {
    @StateObject private var box: LocalBox<T>

    init(wrappedValue: T) {
        _box = StateObject(wrappedValue: LocalBox(wrappedValue))
    }

    var wrappedValue: T {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<T> {
        let box = self.box
        return Binding(get: { box.value }, set: { box.value = $0 })
    }
}

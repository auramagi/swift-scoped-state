//
//  ContainerScopeModifier.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

/// Adapts an externally owned container to the scope type stored in the
/// environment. The concrete container type does not escape this modifier.
@MainActor private struct ContainerScopeModifier<Container: AnyObject, Scope>: ViewModifier {
    @ContainerScopeProvider<Container, Scope> private var scope: ScopedStateStorage<Scope>

    init(container: Container, scope keyPath: KeyPath<Container, Scope>) {
        self._scope = ContainerScopeProvider(container: container, keyPath: keyPath)
    }

    func body(content: Content) -> some View {
        content
            .environment(scope)
    }
}

@MainActor @propertyWrapper private struct ContainerScopeProvider<Container: AnyObject, Scope>: @MainActor DynamicProperty {
    @MainActor private final class Coordinator {
        let storage = ScopedStateStorage<Scope>()

        private var container: Container?

        private var keyPath: KeyPath<Container, Scope>?

        func update(container: Container, keyPath: KeyPath<Container, Scope>) {
            guard self.container !== container || self.keyPath != keyPath else {
                return
            }

            storage.setValue(container[keyPath: keyPath], notifyingObservers: false)

            self.container = container
            self.keyPath = keyPath
        }
    }

    @State private var coordinator = Coordinator()

    let container: Container

    let keyPath: KeyPath<Container, Scope>

    func update() {
        coordinator.update(container: container, keyPath: keyPath)
    }

    var wrappedValue: ScopedStateStorage<Scope> {
        coordinator.storage
    }
}

/// Adds root-scope provision to SwiftUI views.
extension View {
    /// Provides a scope from an externally owned container.
    ///
    /// Keep the container at a stable identity, commonly with `@State`, and
    /// select the scope it provides with a key path.
    ///
    /// ```swift
    /// struct RootView: View {
    ///     @State private var container = AppContainer()
    ///
    ///     var body: some View {
    ///         ContentView()
    ///             .container(container, scope: \.appScope)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - container: The reference-type container that owns the scope
    ///     implementation.
    ///   - scope: A key path to the scope provided to descendant views.
    /// - Returns: A view that provides the selected scope to its subtree.
    @MainActor public func container<Container: AnyObject, Scope>(
        _ container: Container,
        scope: KeyPath<Container, Scope>
    ) -> some View {
        modifier(ContainerScopeModifier(container: container, scope: scope))
    }
}

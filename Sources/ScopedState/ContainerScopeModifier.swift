//
//  ContainerScopeModifier.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

/// Puts the container's scope in the environment without exposing the container type.
@MainActor private struct ContainerScopeModifier<Container: AnyObject, Scope>: ViewModifier {
    @ContainerScopeProvider<Container, Scope> private var scope: ScopedStateStorage<Scope>

    @State private var snapshots = ScopeSnapshot<Scope>.Cache()

    init(container: Container, scope keyPath: KeyPath<Container, Scope>) {
        self._scope = ContainerScopeProvider(container: container, keyPath: keyPath)
    }

    func body(content: Content) -> some View {
        content
            .environment(snapshots.snapshot(from: scope))
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

extension View {
    /// Provides a scope from an externally owned container.
    ///
    /// Select the container's scope with a key path. Keep the container's
    /// identity stable across view updates, for example by storing it in `@State`.
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
    ///   - container: The object that provides the scope.
    ///   - scope: A key path to the scope provided to descendant views.
    /// - Returns: A view that provides the selected scope to its subtree.
    @MainActor public func container<Container: AnyObject, Scope>(
        _ container: Container,
        scope: KeyPath<Container, Scope>
    ) -> some View {
        modifier(ContainerScopeModifier(container: container, scope: scope))
    }
}

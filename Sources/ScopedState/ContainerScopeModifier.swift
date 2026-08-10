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

            storage.value = container[keyPath: keyPath]
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

/// Installs a scope whose binding-backed connections remain live as its
/// SwiftUI view container updates.
@MainActor private struct ViewContainerScopeModifier<Container: View, Scope>: ViewModifier {
    let scope: ScopedStateStorage<Scope>

    init(container: Container, scope keyPath: KeyPath<Container, Scope>) {
        let storage = ScopedStateStorage<Scope>()
        storage.value = container[keyPath: keyPath]
        self.scope = storage
    }

    func body(content: Content) -> some View {
        content
            .environment(scope)
    }
}

extension View {
    /// Establishes a scope from an externally owned container.
    @MainActor public func container<Container: AnyObject, Scope>(
        _ container: Container,
        scope: KeyPath<Container, Scope>
    ) -> some View {
        modifier(ContainerScopeModifier(container: container, scope: scope))
    }

    /// Establishes a scope whose connections can be derived from a SwiftUI
    /// view's dynamic properties, including native bindings.
    @MainActor public func container<Container: View, Scope>(
        _ container: Container,
        scope: KeyPath<Container, Scope>
    ) -> some View {
        modifier(ViewContainerScopeModifier(container: container, scope: scope))
    }
}

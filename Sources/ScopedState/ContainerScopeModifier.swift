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

        var container: Container?

        var keyPath: KeyPath<Container, Scope>?
    }

    @State private var coordinator = Coordinator()

    let container: Container

    let keyPath: KeyPath<Container, Scope>

    func update() {
        guard coordinator.container !== container || coordinator.keyPath != keyPath else {
            return
        }

        coordinator.storage.value = container[keyPath: keyPath]
        coordinator.container = container
        coordinator.keyPath = keyPath
    }

    var wrappedValue: ScopedStateStorage<Scope> {
        coordinator.storage
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
}

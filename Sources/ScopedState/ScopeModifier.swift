//
//  ScopeModifier.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

@MainActor private struct ScopeModifier<ParentScope, Configuration, Connected: ConnectedValue>: ViewModifier {
    @ScopedState<ParentScope, Configuration, Connected> private var scope: Connected.WrappedValue

    init(scope: ScopedState<ParentScope, Configuration, Connected>) {
        self._scope = scope
    }

    func body(content: Content) -> some View {
        content
            .environment(_scope.storage)
    }
}

extension View {
    /// Connects a scope without configuration at this point in the SwiftUI view tree. The
    /// live session retains any state or container created by the connection until the
    /// subtree disappears.
    @MainActor public func scope<ParentScope, Connected: ConnectedValue>(
        _ keyPath: KeyPath<ParentScope, GenericConnection<Void, Connected>>
    ) -> some View {
        modifier(ScopeModifier(scope: ScopedState(keyPath)))
    }

    /// Connects a configured scope at this point in the SwiftUI view tree. The live session
    /// retains any state or container created by the connection until the subtree disappears.
    @MainActor public func scope<ParentScope, Configuration, Connected: ConnectedValue>(
        _ keyPath: KeyPath<ParentScope, GenericConnection<Configuration, Connected>>,
        configuration: Configuration
    ) -> some View {
        modifier(ScopeModifier(scope: ScopedState(keyPath, configuration: configuration)))
    }
}

//
//  ScopeModifier.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

@MainActor private struct ScopeModifier<ParentScope, Configuration, Connected: ConnectedValue>: ViewModifier {
    @ScopedState<ParentScope, Configuration, Connected> private var scope: Connected.WrappedValue

    init(
        connection: KeyPath<ParentScope, ConnectionDefinition<Configuration, Connected>>,
        configuration: Configuration
    ) {
        self._scope = ScopedState(connection, configuration: configuration)
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
        _ connection: KeyPath<ParentScope, ConnectionDefinition<Void, Connected>>
    ) -> some View {
        scope(connection, configuration: ())
    }

    /// Connects a configured scope at this point in the SwiftUI view tree. The live session
    /// retains any state or container created by the connection until the subtree disappears.
    @MainActor public func scope<ParentScope, Configuration, Connected: ConnectedValue>(
        _ connection: KeyPath<ParentScope, ConnectionDefinition<Configuration, Connected>>,
        configuration: Configuration
    ) -> some View {
        modifier(ScopeModifier(connection: connection, configuration: configuration))
    }
}

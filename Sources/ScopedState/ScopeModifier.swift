//
//  ScopeModifier.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

@MainActor private struct ScopeModifier<ParentScope, Input, Connected: ConnectedValue>: ViewModifier {
    @ScopedState<ParentScope, Input, Connected> private var scope: Connected.WrappedValue

    init(
        connection: KeyPath<ParentScope, ConnectionDefinition<Input, Connected>>,
        input: Input
    ) {
        self._scope = ScopedState(connection, input: input)
    }

    func body(content: Content) -> some View {
        content.environment(_scope.storage)
    }
}

extension View {
    /// Connects a scope without input at this SwiftUI location. The live session
    /// retains any state or container created by the connection until the location
    /// disappears.
    @MainActor public func scope<ParentScope, Connected: ConnectedValue>(
        _ connection: KeyPath<ParentScope, ConnectionDefinition<Void, Connected>>
    ) -> some View {
        scope(connection, input: ())
    }

    /// Connects an input-bearing scope at this SwiftUI location. The live session
    /// retains any state or container created by the connection until the location
    /// disappears.
    @MainActor public func scope<ParentScope, Input, Connected: ConnectedValue>(
        _ connection: KeyPath<ParentScope, ConnectionDefinition<Input, Connected>>,
        input: Input
    ) -> some View {
        modifier(ScopeModifier(connection: connection, input: input))
    }
}

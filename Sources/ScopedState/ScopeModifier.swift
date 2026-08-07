//
//  ScopeModifier.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

@MainActor private struct ScopeModifier<ParentScope, Input: Equatable, Scope>: ViewModifier {
    @ScopedState<ReadOnlyConnectionKey<ParentScope, Input, Scope>> private var scope: Scope

    init(
        connection: KeyPath<ParentScope, Connection<Input, Scope>>,
        input: Input
    ) {
        self._scope = ScopedState(connection, input: input)
    }

    func body(content: Content) -> some View {
        content.environment(_scope.storage)
    }
}

extension View {
    /// Connects an input-bearing scope at this SwiftUI location. The live session
    /// retains any state or container created by the connection until the location
    /// disappears.
    @MainActor public func scope<ParentScope, Scope, Input: Equatable>(
        _ connection: KeyPath<ParentScope, Connection<Input, Scope>>,
        input: Input
    ) -> some View {
        modifier(ScopeModifier(connection: connection, input: input))
    }
}

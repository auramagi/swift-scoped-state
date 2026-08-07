//
//  ScopeModifier.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

@MainActor private struct ScopeModifier<ParentScope, Input: Equatable, Scope>: ViewModifier {
    @ScopeProvider<ParentScope, Input, Scope> private var scope: ScopedStateStorage<Scope>

    init(
        connection: KeyPath<ParentScope, Connection<Input, Scope>>,
        input: Input
    ) {
        self._scope = ScopeProvider(connection: connection, input: input)
    }

    func body(content: Content) -> some View {
        content.environment(scope)
    }
}

@MainActor @propertyWrapper private struct ScopeProvider<ParentScope, Input: Equatable, Scope>: @MainActor DynamicProperty {
    @Environment(ScopedStateStorage<ParentScope>.self) private var parentScope

    @State private var host = ConnectionHost<Connection<Input, Scope>>()

    private let connection: KeyPath<ParentScope, Connection<Input, Scope>>

    private let input: Input

    init(
        connection: KeyPath<ParentScope, Connection<Input, Scope>>,
        input: Input
    ) {
        self.connection = connection
        self.input = input
    }

    func update() {
        host.connectIfNeeded(
            to: parentScope.requiredValue[keyPath: connection],
            input: input
        )
    }

    var wrappedValue: ScopedStateStorage<Scope> {
        host.storage
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

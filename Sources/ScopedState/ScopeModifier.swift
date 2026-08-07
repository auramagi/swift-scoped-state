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
        factory: KeyPath<ParentScope, ConnectionFactory<Input, Scope>>,
        input: Input
    ) {
        self._scope = ScopeProvider(factory: factory, input: input)
    }

    func body(content: Content) -> some View {
        content.environment(scope)
    }
}

@MainActor @propertyWrapper private struct ScopeProvider<ParentScope, Input: Equatable, Scope>: @MainActor DynamicProperty {
    @Environment(ScopedStateStorage<ParentScope>.self) private var parentScope

    @State private var host = ConnectionHost<ConnectionFactory<Input, Scope>>()

    private let factory: KeyPath<ParentScope, ConnectionFactory<Input, Scope>>

    private let input: Input

    init(
        factory: KeyPath<ParentScope, ConnectionFactory<Input, Scope>>,
        input: Input
    ) {
        self.factory = factory
        self.input = input
    }

    func update() {
        host.connectIfNeeded(
            to: parentScope.requiredValue[keyPath: factory],
            input: input
        )
    }

    var wrappedValue: ScopedStateStorage<Scope> {
        host.storage
    }
}

extension View {
    /// Connects an input-bearing scope at this SwiftUI location. The live session
    /// retains any state or container created by the factory until the location
    /// disappears.
    @MainActor public func scope<ParentScope, Input: Equatable, Scope>(
        _ factory: KeyPath<ParentScope, ConnectionFactory<Input, Scope>>,
        input: Input
    ) -> some View {
        modifier(ScopeModifier(factory: factory, input: input))
    }
}

//
//  ScopeModifier.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

@MainActor private struct ScopeModifier<ParentScope, Configuration: Equatable, Scope>: ViewModifier {
    @ScopedState<ParentScope, Configuration, Scope, ReadOnlyValueProjection<Scope>> private var scope: Scope

    init(scope: ScopedState<ParentScope, Configuration, Scope, ReadOnlyValueProjection<Scope>>) {
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
    @MainActor public func scope<ParentScope, Scope>(
        _ keyPath: KeyPath<ParentScope, Connection<Scope>>
    ) -> some View {
        modifier(ScopeModifier(scope: ScopedState(keyPath)))
    }

    /// Connects a configured scope at this point in the SwiftUI view tree. The live session
    /// retains any state or container created by the connection until the subtree disappears.
    @MainActor public func scope<ParentScope, Configuration: Equatable, Scope>(
        _ keyPath: KeyPath<ParentScope, ConfiguredConnection<Scope, Configuration>>,
        configuration: Configuration
    ) -> some View {
        modifier(ScopeModifier(scope: ScopedState(keyPath, configuration: configuration)))
    }
}

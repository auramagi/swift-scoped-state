//
//  ScopeModifier.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

@MainActor private struct ScopeModifier<ParentScope, Definition: ValueDefinition>: ViewModifier {
    @ScopedState<ParentScope, Definition, ReadOnlyValueProjection<Definition.Value>> private var scope: Definition.Value

    init(scope: ScopedState<ParentScope, Definition, ReadOnlyValueProjection<Definition.Value>>) {
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
    @MainActor public func scope<ParentScope, Definition: ValueDefinition>(
        _ keyPath: KeyPath<ParentScope, GenericConnection<Definition>>
    ) -> some View where Definition.Configuration == Void {
        modifier(ScopeModifier(scope: ScopedState(keyPath)))
    }

    /// Connects a configured scope at this point in the SwiftUI view tree. The live session
    /// retains any state or container created by the connection until the subtree disappears.
    @MainActor public func scope<ParentScope, Definition: ValueDefinition>(
        _ keyPath: KeyPath<ParentScope, GenericConnection<Definition>>,
        configuration: Definition.Configuration
    ) -> some View {
        modifier(ScopeModifier(scope: ScopedState(keyPath, configuration: configuration)))
    }
}

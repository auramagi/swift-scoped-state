//
//  ScopeModifier.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

@MainActor private struct ScopeModifier<ParentScope, Configuration: Equatable, Scope>: ViewModifier {
    @ScopedState<ParentScope, Configuration, Scope, ReadOnlyValueProjection<Scope>> private var scope: Scope

    @State private var snapshots = ScopeSnapshot<Scope>.Cache()

    init(scope: ScopedState<ParentScope, Configuration, Scope, ReadOnlyValueProjection<Scope>>) {
        self._scope = scope
    }

    func body(content: Content) -> some View {
        content
            .environment(snapshots.snapshot(from: _scope.storage))
    }
}

extension View {
    /// Resolves an unconfigured child scope and provides it to descendant views.
    ///
    /// The connection stays active for the lifetime of this modifier's SwiftUI state.
    ///
    /// - Parameter keyPath: A key path from the current scope to a child-scope
    ///   connection.
    /// - Returns: A view that provides the child scope to its subtree.
    @MainActor public func scope<ParentScope, Scope>(
        _ keyPath: KeyPath<ParentScope, Connection<Scope>>
    ) -> some View {
        modifier(ScopeModifier(scope: ScopedState(keyPath)))
    }

    /// Resolves a configured child scope and provides it to descendant views.
    ///
    /// ```swift
    /// ForEach(todoIDs, id: \.self) { id in
    ///     TodoRow()
    ///         .scope(\AppScope.todoScope, configuration: id)
    /// }
    /// ```
    ///
    /// The connection stays active for the lifetime of this modifier's SwiftUI
    /// state. Changing `configuration` reconfigures the connection.
    ///
    /// - Parameters:
    ///   - keyPath: A key path from the current scope to a configured
    ///     child-scope connection.
    ///   - configuration: The context used to establish the child scope.
    /// - Returns: A view that provides the configured child scope to its subtree.
    @MainActor public func scope<ParentScope, Configuration: Equatable, Scope>(
        _ keyPath: KeyPath<ParentScope, ConfiguredConnection<Scope, Configuration>>,
        configuration: Configuration
    ) -> some View {
        modifier(ScopeModifier(scope: ScopedState(keyPath, configuration: configuration)))
    }
}

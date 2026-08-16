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

/// Adds child-scope provision to SwiftUI views.
extension View {
    /// Derives and provides an unconfigured child scope at this point in the
    /// view hierarchy.
    ///
    /// The active connection retains resources created for the child scope for
    /// the lifetime of this modifier's SwiftUI state.
    ///
    /// - Parameter keyPath: A key path from the current scope to a child-scope
    ///   connection.
    /// - Returns: A view that provides the child scope to its subtree.
    @MainActor public func scope<ParentScope, Scope>(
        _ keyPath: KeyPath<ParentScope, Connection<Scope>>
    ) -> some View {
        modifier(ScopeModifier(scope: ScopedState(keyPath)))
    }

    /// Derives and provides a configured child scope at this point in the view
    /// hierarchy.
    ///
    /// ```swift
    /// ForEach(todoIDs, id: \.self) { id in
    ///     TodoRow()
    ///         .scope(\AppScope.todoScope, configuration: id)
    /// }
    /// ```
    ///
    /// The active connection retains resources created for the child scope for
    /// the lifetime of this modifier's SwiftUI state. Changing `configuration`
    /// reconfigures the connection for the new context.
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

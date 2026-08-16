//
//  ScopedState+ObservableObject.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-12.
//

import Combine

extension ScopedState where Value: ObservableObject {
    /// Creates writable configured scoped state that observes
    /// `objectWillChange` on the connected object.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the connection in its scope.
    ///   - configuration: The configuration used to establish the connection.
    public init(
        _ keyPath: KeyPath<Scope, WritableConfiguredConnection<Value, Configuration>>,
        configuration: Configuration
    ) where Projection == ReadWriteValueProjection<Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }

    /// Creates read-only configured scoped state that observes
    /// `objectWillChange` on the connected object.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the connection in its scope.
    ///   - configuration: The configuration used to establish the connection.
    public init(
        _ keyPath: KeyPath<Scope, ConfiguredConnection<Value, Configuration>>,
        configuration: Configuration
    ) where Projection == ReadOnlyValueProjection<Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }
}

extension ScopedState where Value: ObservableObject & Equatable {
    /// Creates writable configured scoped state that observes
    /// `objectWillChange` on the connected object.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the connection in its scope.
    ///   - configuration: The configuration used to establish the connection.
    public init(
        _ keyPath: KeyPath<Scope, WritableConfiguredConnection<Value, Configuration>>,
        configuration: Configuration
    ) where Projection == ReadWriteValueProjection<Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }

    /// Creates read-only configured scoped state that observes
    /// `objectWillChange` on the connected object.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the connection in its scope.
    ///   - configuration: The configuration used to establish the connection.
    public init(
        _ keyPath: KeyPath<Scope, ConfiguredConnection<Value, Configuration>>,
        configuration: Configuration
    ) where Projection == ReadOnlyValueProjection<Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }
}

extension ScopedState where Configuration == EmptyConfiguration, Value: ObservableObject {
    /// Creates writable unconfigured scoped state that observes
    /// `objectWillChange` on the connected object.
    ///
    /// - Parameter keyPath: The key path to the connection in its scope.
    public init(
        _ keyPath: KeyPath<Scope, WritableConnection<Value>>
    ) where Projection == ReadWriteValueProjection<Value> {
        self.init(keyPath, configuration: .init(), valueBehavior: .observableObject)
    }

    /// Creates read-only unconfigured scoped state that observes
    /// `objectWillChange` on the connected object.
    ///
    /// - Parameter keyPath: The key path to the connection in its scope.
    public init(
        _ keyPath: KeyPath<Scope, Connection<Value>>
    ) where Projection == ReadOnlyValueProjection<Value> {
        self.init(keyPath, configuration: .init(), valueBehavior: .observableObject)
    }
}

extension ScopedState where Configuration == EmptyConfiguration, Value: ObservableObject & Equatable {
    /// Creates writable unconfigured scoped state that observes
    /// `objectWillChange` on the connected object.
    ///
    /// - Parameter keyPath: The key path to the connection in its scope.
    public init(
        _ keyPath: KeyPath<Scope, WritableConnection<Value>>
    ) where Projection == ReadWriteValueProjection<Value> {
        self.init(keyPath, configuration: .init(), valueBehavior: .observableObject)
    }

    /// Creates read-only unconfigured scoped state that observes
    /// `objectWillChange` on the connected object.
    ///
    /// - Parameter keyPath: The key path to the connection in its scope.
    public init(
        _ keyPath: KeyPath<Scope, Connection<Value>>
    ) where Projection == ReadOnlyValueProjection<Value> {
        self.init(keyPath, configuration: .init(), valueBehavior: .observableObject)
    }
}

private extension ScopedState.ValueBehavior where Value: ObservableObject {
    static var observableObject: Self {
        Self(
            areEquivalent: { $0 === $1 },
            makeObservation: { value, invalidate in
                let observation = value.objectWillChange.sink { _ in
                    invalidate()
                }
                return CancellationToken {
                    observation.cancel()
                }
            }
        )
    }
}

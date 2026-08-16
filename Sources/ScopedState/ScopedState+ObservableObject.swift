//
//  ScopedState+ObservableObject.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-12.
//

import Combine

extension ScopedState where Value: ObservableObject {
    public init(
        _ keyPath: KeyPath<Scope, WritableConfiguredConnection<Value, Configuration>>,
        configuration: Configuration
    ) where Projection == ReadWriteValueProjection<Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }

    public init(
        _ keyPath: KeyPath<Scope, ConfiguredConnection<Value, Configuration>>,
        configuration: Configuration
    ) where Projection == ReadOnlyValueProjection<Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }
}

extension ScopedState where Value: ObservableObject & Equatable {
    public init(
        _ keyPath: KeyPath<Scope, WritableConfiguredConnection<Value, Configuration>>,
        configuration: Configuration
    ) where Projection == ReadWriteValueProjection<Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }

    public init(
        _ keyPath: KeyPath<Scope, ConfiguredConnection<Value, Configuration>>,
        configuration: Configuration
    ) where Projection == ReadOnlyValueProjection<Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }
}

extension ScopedState where Configuration == EmptyConfiguration, Value: ObservableObject {
    public init(
        _ keyPath: KeyPath<Scope, WritableConnection<Value>>
    ) where Projection == ReadWriteValueProjection<Value> {
        self.init(keyPath, configuration: .init(), valueBehavior: .observableObject)
    }

    public init(
        _ keyPath: KeyPath<Scope, Connection<Value>>
    ) where Projection == ReadOnlyValueProjection<Value> {
        self.init(keyPath, configuration: .init(), valueBehavior: .observableObject)
    }
}

extension ScopedState where Configuration == EmptyConfiguration, Value: ObservableObject & Equatable {
    public init(
        _ keyPath: KeyPath<Scope, WritableConnection<Value>>
    ) where Projection == ReadWriteValueProjection<Value> {
        self.init(keyPath, configuration: .init(), valueBehavior: .observableObject)
    }

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

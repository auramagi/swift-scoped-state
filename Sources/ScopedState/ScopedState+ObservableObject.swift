//
//  ScopedState+ObservableObject.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-12.
//

import Combine

extension ScopedState where Definition.Value: ObservableObject {
    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Definition>>,
        configuration: Definition.Configuration
    ) where Definition: WritableValueDefinition, Projection == ReadWriteValueProjection<Definition.Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Definition>>,
        configuration: Definition.Configuration,
        readOnly: Void = ()
    ) where Projection == ReadOnlyValueProjection<Definition.Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }
}

extension ScopedState where Definition.Value: ObservableObject & Equatable {
    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Definition>>,
        configuration: Definition.Configuration
    ) where Definition: WritableValueDefinition, Projection == ReadWriteValueProjection<Definition.Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Definition>>,
        configuration: Definition.Configuration,
        readOnly: Void = ()
    ) where Projection == ReadOnlyValueProjection<Definition.Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }
}

extension ScopedState where Definition.Configuration == EmptyConfiguration, Definition.Value: ObservableObject {
    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Definition>>
    ) where Definition: WritableValueDefinition, Projection == ReadWriteValueProjection<Definition.Value> {
        self.init(keyPath, configuration: .init(), valueBehavior: .observableObject)
    }

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Definition>>,
        readOnly: Void = ()
    ) where Projection == ReadOnlyValueProjection<Definition.Value> {
        self.init(keyPath, configuration: .init(), valueBehavior: .observableObject)
    }
}

extension ScopedState where Definition.Configuration == EmptyConfiguration, Definition.Value: ObservableObject & Equatable {
    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Definition>>
    ) where Definition: WritableValueDefinition, Projection == ReadWriteValueProjection<Definition.Value> {
        self.init(keyPath, configuration: .init(), valueBehavior: .observableObject)
    }

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Definition>>,
        readOnly: Void = ()
    ) where Projection == ReadOnlyValueProjection<Definition.Value> {
        self.init(keyPath, configuration: .init(), valueBehavior: .observableObject)
    }
}

private extension ScopedState.ValueBehavior where Definition.Value: ObservableObject {
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

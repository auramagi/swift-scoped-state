//
//  ScopedState+ObservableObject.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-12.
//

import Combine

extension ScopedState where Connected.WrappedValue: ObservableObject {
    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>,
        configuration: Configuration
    ) {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }
}

extension ScopedState where Connected.WrappedValue: ObservableObject & Equatable {
    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>,
        configuration: Configuration
    ) {
        self.init(keyPath, configuration: configuration, valueBehavior: .observableObject)
    }
}

extension ScopedState where Configuration == Void, Connected.WrappedValue: ObservableObject {
    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>
    ) {
        self.init(keyPath, configuration: (), valueBehavior: .observableObject)
    }
}

extension ScopedState where Configuration == Void, Connected.WrappedValue: ObservableObject & Equatable {
    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>
    ) {
        self.init(keyPath, configuration: (), valueBehavior: .observableObject)
    }
}

private extension ScopedState.ValueBehavior where Connected.WrappedValue: ObservableObject {
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

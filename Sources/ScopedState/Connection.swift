//
//  Connection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-08.
//

public typealias Connection<Value> = GenericConnection<ReadOnlyValueDefinition<Void, Value>>

extension Connection {
    public typealias Configuration<NewConfiguration> = GenericConnection<ReadOnlyValueDefinition<NewConfiguration, Definition.Value>>

    public typealias Writable = GenericConnection<ReadWriteValueDefinition<Definition.Configuration, Definition.Value>>
}

/// The generic implementation underlying the public `Connection<Value>` family.
@MainActor public struct GenericConnection<Definition: ValueDefinition> {
    public typealias Session = ConnectionSession<Definition.Configuration, Definition.Value>

    let makeSession: (Definition.Configuration) -> Session

    let configurationsEqual: (Definition.Configuration, Definition.Configuration) -> Bool

    public init(
        makeSession: @escaping (Definition.Configuration) -> Session,
        configurationsEqual: @escaping (Definition.Configuration, Definition.Configuration) -> Bool
    ) {
        self.makeSession = makeSession
        self.configurationsEqual = configurationsEqual
    }
}

extension GenericConnection where Definition.Configuration: Equatable {
    public init(
        makeSession: @escaping (Definition.Configuration) -> Session
    ) {
        self.init(
            makeSession: makeSession,
            configurationsEqual: { $0 == $1 }
        )
    }
}

extension GenericConnection where Definition.Configuration == Void {
    public init(
        makeSession: @escaping () -> Session
    ) {
        self.init(
            makeSession: { _ in makeSession() },
            configurationsEqual: { _, _ in true }
        )
    }
}

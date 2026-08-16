//
//  Connection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-08.
//

public typealias Connection<Value> = GenericConnection<ReadOnlyValueDefinition<EmptyConfiguration, Value>>

extension Connection {
    public typealias Configuration<NewConfiguration: Equatable> = GenericConnection<ReadOnlyValueDefinition<NewConfiguration, Definition.Value>>

    public typealias Writable = GenericConnection<ReadWriteValueDefinition<Definition.Configuration, Definition.Value>>
}

/// The generic implementation underlying the public `Connection<Value>` family.
@MainActor public struct GenericConnection<Definition: ValueDefinition> {
    public typealias Session = ConnectionSession<Definition.Configuration, Definition.Value>

    let makeSession: (Definition.Configuration) -> Session

    public init(
        makeSession: @escaping (Definition.Configuration) -> Session
    ) {
        self.makeSession = makeSession
    }
}

extension GenericConnection where Definition.Configuration == EmptyConfiguration {
    public init(
        makeSession: @escaping () -> Session
    ) {
        self.init(makeSession: { _ in makeSession() })
    }
}

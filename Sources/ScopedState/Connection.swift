//
//  Connection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-08.
//

public typealias Connection<WrappedValue> = GenericConnection<Void, ReadOnlyConnectedValue<WrappedValue>>

extension Connection {
    public typealias Configuration<NewConfiguration> = GenericConnection<NewConfiguration, Connected>

    public typealias Writable = GenericConnection<Configuration, WritableConnectedValue<Connected.WrappedValue>>
}

/// The generic implementation underlying the public `Connection<Value>` family.
@MainActor public struct GenericConnection<Configuration, Connected: ConnectedValue> {
    public typealias Session = ConnectionSession<Configuration, Connected.WrappedValue>

    let makeSession: (Configuration) -> Session

    let configurationsEqual: (Configuration, Configuration) -> Bool

    public init(
        makeSession: @escaping (Configuration) -> Session,
        configurationsEqual: @escaping (Configuration, Configuration) -> Bool
    ) {
        self.makeSession = makeSession
        self.configurationsEqual = configurationsEqual
    }
}

extension GenericConnection where Configuration: Equatable {
    public init(
        makeSession: @escaping (Configuration) -> Session
    ) {
        self.init(
            makeSession: makeSession,
            configurationsEqual: { $0 == $1 }
        )
    }
}

extension GenericConnection where Configuration == Void {
    public init(
        makeSession: @escaping () -> Session
    ) {
        self.init(
            makeSession: { _ in makeSession() },
            configurationsEqual: { _, _ in true }
        )
    }
}

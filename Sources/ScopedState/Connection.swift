//
//  Connection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-08.
//

import Combine

public typealias Connection<WrappedValue> = ConnectionDefinition<Void, ReadOnlyConnectedValue<WrappedValue>>

extension Connection {
    public typealias Configuration<NewConfiguration> = ConnectionDefinition<NewConfiguration, Connected>

    public typealias Writable = ConnectionDefinition<Configuration, WritableConnectedValue<Connected.WrappedValue>>
}

/// The generic implementation underlying the public `Connection<Value>` family.
@MainActor public struct ConnectionDefinition<Configuration, Connected: ConnectedValue> {
    /// A live connection created for one position in the SwiftUI view tree.
    /// Its closures retain any implementation object needed to keep the value alive.
    @MainActor public struct Session {
        let currentValue: @MainActor () -> Connected.WrappedValue

        let updates: any Publisher<Connected.WrappedValue, Never>

        let setValue: (@MainActor (Connected.WrappedValue) -> Void)?

        let updateConfiguration: @MainActor (Configuration) -> Void

        public init<WrappedValue>(
            currentValue: @escaping @MainActor () -> WrappedValue,
            updates: any Publisher<WrappedValue, Never>,
            updateConfiguration: @escaping @MainActor (Configuration) -> Void = { _ in }
        ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
            self.currentValue = currentValue
            self.updates = updates
            self.setValue = nil
            self.updateConfiguration = updateConfiguration
        }

        public init<WrappedValue>(
            currentValue: @escaping @MainActor () -> WrappedValue,
            updates: any Publisher<WrappedValue, Never>,
            setValue: @escaping @MainActor (WrappedValue) -> Void,
            updateConfiguration: @escaping @MainActor (Configuration) -> Void = { _ in }
        ) where Connected == WritableConnectedValue<WrappedValue> {
            self.currentValue = currentValue
            self.updates = updates
            self.setValue = setValue
            self.updateConfiguration = updateConfiguration
        }
    }

    private final class IdentityToken { }

    private let configurationsEqual: @MainActor (Configuration, Configuration) -> Bool

    private let createSession: @MainActor (Configuration) -> Session

    private let identityToken = IdentityToken()

    private init(
        configurationsEqual: @escaping @MainActor (Configuration, Configuration) -> Bool,
        createSession: @escaping @MainActor (Configuration) -> Session
    ) {
        self.configurationsEqual = configurationsEqual
        self.createSession = createSession
    }

    var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    func configurationsAreEqual(
        _ lhs: Configuration,
        _ rhs: Configuration
    ) -> Bool {
        configurationsEqual(lhs, rhs)
    }

    func makeSession(configuration: Configuration) -> Session {
        createSession(configuration)
    }
}

extension ConnectionDefinition {
    public init(
        configurationsAreEqual: @escaping @MainActor (Configuration, Configuration) -> Bool,
        createSession: @escaping @MainActor (Configuration) -> Session
    ) {
        self.init(
            configurationsEqual: configurationsAreEqual,
            createSession: createSession
        )
    }
}

extension ConnectionDefinition where Configuration: Equatable {
    public init(
        createSession: @escaping @MainActor (Configuration) -> Session
    ) {
        self.init(
            configurationsAreEqual: { $0 == $1 },
            createSession: createSession
        )
    }
}

extension ConnectionDefinition where Configuration == Void {
    public init(
        createSession: @escaping @MainActor () -> Session
    ) {
        self.init(
            configurationsAreEqual: { _, _ in true },
            createSession: { _ in createSession() }
        )
    }

    public init<WrappedValue>(
        currentValue: @escaping @MainActor () -> WrappedValue,
        updates: any Publisher<WrappedValue, Never>
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.init {
            Session(
                currentValue: currentValue,
                updates: updates
            )
        }
    }

    public init<WrappedValue>(
        currentValue: @escaping @MainActor () -> WrappedValue,
        updates: any Publisher<WrappedValue, Never>,
        setValue: @escaping @MainActor (WrappedValue) -> Void
    ) where Connected == WritableConnectedValue<WrappedValue> {
        self.init {
            Session(
                currentValue: currentValue,
                updates: updates,
                setValue: setValue
            )
        }
    }
}

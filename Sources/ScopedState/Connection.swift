//
//  Connection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-08.
//

import Combine
import SwiftUI

final class IdentityToken {}

public protocol ConnectedValue {
    associatedtype WrappedValue

    associatedtype Projection

    @MainActor static func transformProjection(_ projection: ScopedStateProjection<WrappedValue>) -> Projection
}

public enum ReadOnlyConnectedValue<WrappedValue>: ConnectedValue {
    @MainActor public static func transformProjection(_ projection: ScopedStateProjection<WrappedValue>) -> ScopedStateProjection<WrappedValue> {
        projection
    }
}

public enum WritableConnectedValue<WrappedValue>: ConnectedValue {
    @MainActor public static func transformProjection(_ projection: ScopedStateProjection<WrappedValue>) -> Binding<WrappedValue> {
        projection.binding
    }
}

/// The generic implementation underlying the public `Connection<Value>` family.
@MainActor public struct ConnectionDefinition<ConnectionConfiguration, Connected: ConnectedValue> {
    /// A live connection created for one position in the SwiftUI view tree.
    /// Its closures retain any implementation object needed to keep the value alive.
    @MainActor public struct Session {
        let currentValue: @MainActor () -> Connected.WrappedValue

        let updates: any Publisher<Connected.WrappedValue, Never>

        let setValue: (@MainActor (Connected.WrappedValue) -> Void)?

        let updateConfiguration: @MainActor (ConnectionConfiguration) -> Void

        private init(
            currentValue: @escaping @MainActor () -> Connected.WrappedValue,
            updates: any Publisher<Connected.WrappedValue, Never>,
            storedSetValue: (@MainActor (Connected.WrappedValue) -> Void)?,
            updateConfiguration: @escaping @MainActor (ConnectionConfiguration) -> Void
        ) {
            self.currentValue = currentValue
            self.updates = updates
            self.setValue = storedSetValue
            self.updateConfiguration = updateConfiguration
        }

        public init<Value>(
            currentValue: @escaping @MainActor () -> Value,
            updates: any Publisher<Value, Never>,
            updateConfiguration: @escaping @MainActor (ConnectionConfiguration) -> Void = { _ in }
        ) where Connected == ReadOnlyConnectedValue<Value> {
            self.init(
                currentValue: currentValue,
                updates: updates,
                storedSetValue: nil,
                updateConfiguration: updateConfiguration
            )
        }

        public init<Value>(
            currentValue: @escaping @MainActor () -> Value,
            updates: any Publisher<Value, Never>,
            setValue: @escaping @MainActor (Value) -> Void,
            updateConfiguration: @escaping @MainActor (ConnectionConfiguration) -> Void = { _ in }
        ) where Connected == WritableConnectedValue<Value> {
            self.init(
                currentValue: currentValue,
                updates: updates,
                storedSetValue: setValue,
                updateConfiguration: updateConfiguration
            )
        }
    }

    public typealias Configuration<NewConfiguration> = ConnectionDefinition<NewConfiguration, Connected>

    public typealias Writable = ConnectionDefinition<ConnectionConfiguration, WritableConnectedValue<Connected.WrappedValue>>

    let configurationsEqual: @MainActor (ConnectionConfiguration, ConnectionConfiguration) -> Bool

    let createSession: @MainActor (ConnectionConfiguration) -> Session

    let identityToken = IdentityToken()

    private init(
        configurationsEqual: @escaping @MainActor (ConnectionConfiguration, ConnectionConfiguration) -> Bool,
        createSession: @escaping @MainActor (ConnectionConfiguration) -> Session
    ) {
        self.configurationsEqual = configurationsEqual
        self.createSession = createSession
    }

    public var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor public func configurationsAreEqual(
        _ lhs: ConnectionConfiguration,
        _ rhs: ConnectionConfiguration
    ) -> Bool {
        configurationsEqual(lhs, rhs)
    }

    @MainActor public func makeSession(
        configuration: ConnectionConfiguration
    ) -> Session {
        createSession(configuration)
    }
}

public typealias Connection<Value> = ConnectionDefinition<Void, ReadOnlyConnectedValue<Value>>

extension ConnectionDefinition {
    public init(
        configurationsAreEqual: @escaping @MainActor (ConnectionConfiguration, ConnectionConfiguration) -> Bool,
        createSession: @escaping @MainActor (ConnectionConfiguration) -> Session
    ) {
        self.init(
            configurationsEqual: configurationsAreEqual,
            createSession: createSession
        )
    }
}

extension ConnectionDefinition where ConnectionConfiguration: Equatable {
    public init(
        createSession: @escaping @MainActor (ConnectionConfiguration) -> Session
    ) {
        self.init(
            configurationsAreEqual: { $0 == $1 },
            createSession: createSession
        )
    }
}

extension ConnectionDefinition where ConnectionConfiguration == Void {
    public init(
        createSession: @escaping @MainActor () -> Session
    ) {
        self.init(
            configurationsAreEqual: { _, _ in true },
            createSession: { _ in createSession() }
        )
    }

    public init<Value>(
        currentValue: @escaping @MainActor () -> Value,
        updates: any Publisher<Value, Never>
    ) where Connected == ReadOnlyConnectedValue<Value> {
        self.init {
            Session(
                currentValue: currentValue,
                updates: updates
            )
        }
    }

    public init<Value>(
        currentValue: @escaping @MainActor () -> Value,
        updates: any Publisher<Value, Never>,
        setValue: @escaping @MainActor (Value) -> Void
    ) where Connected == WritableConnectedValue<Value> {
        self.init {
            Session(
                currentValue: currentValue,
                updates: updates,
                setValue: setValue
            )
        }
    }
}

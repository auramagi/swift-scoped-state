//
//  Connection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-08.
//

import Combine
import SwiftUI

final class IdentityToken {}

/// A live connection created for one position in the SwiftUI view tree.
/// Its closures retain any implementation object needed to keep the value alive.
@MainActor public struct ConnectionSession<Configuration, Value> {
    let currentValue: @MainActor () -> Value

    let updates: any Publisher<Value, Never>

    let setValue: (@MainActor (Value) -> Void)?

    let updateConfiguration: @MainActor (Configuration) -> Void

    public init(
        currentValue: @escaping @MainActor () -> Value,
        updates: any Publisher<Value, Never>,
        updateConfiguration: @escaping @MainActor (Configuration) -> Void = { _ in }
    ) {
        self.currentValue = currentValue
        self.updates = updates
        self.setValue = nil
        self.updateConfiguration = updateConfiguration
    }

    init(
        currentValue: @escaping @MainActor () -> Value,
        updates: any Publisher<Value, Never>,
        setValue: @escaping @MainActor (Value) -> Void,
        updateConfiguration: @escaping @MainActor (Configuration) -> Void
    ) {
        self.currentValue = currentValue
        self.updates = updates
        self.setValue = setValue
        self.updateConfiguration = updateConfiguration
    }
}

/// A live writable connection created for one position in the SwiftUI view tree.
/// Its setter is required, so writable connections cannot be constructed
/// without root replacement support.
@MainActor public struct WritableConnectionSession<Configuration, Value> {
    let currentValue: @MainActor () -> Value

    let updates: any Publisher<Value, Never>

    let setValue: @MainActor (Value) -> Void

    let updateConfiguration: @MainActor (Configuration) -> Void

    public init(
        currentValue: @escaping @MainActor () -> Value,
        updates: any Publisher<Value, Never>,
        setValue: @escaping @MainActor (Value) -> Void,
        updateConfiguration: @escaping @MainActor (Configuration) -> Void = { _ in }
    ) {
        self.currentValue = currentValue
        self.updates = updates
        self.setValue = setValue
        self.updateConfiguration = updateConfiguration
    }

    var connectionSession: ConnectionSession<Configuration, Value> {
        ConnectionSession(
            currentValue: currentValue,
            updates: updates,
            setValue: setValue,
            updateConfiguration: updateConfiguration
        )
    }
}

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
    public typealias Configuration<NewConfiguration> = ConnectionDefinition<NewConfiguration, Connected>

    public typealias Writable = ConnectionDefinition<ConnectionConfiguration, WritableConnectedValue<Connected.WrappedValue>>

    let configurationsEqual: @MainActor (ConnectionConfiguration, ConnectionConfiguration) -> Bool

    let createSession: @MainActor (ConnectionConfiguration) -> ConnectionSession<ConnectionConfiguration, Connected.WrappedValue>

    let identityToken = IdentityToken()

    private init(
        configurationsEqual: @escaping @MainActor (ConnectionConfiguration, ConnectionConfiguration) -> Bool,
        createSession: @escaping @MainActor (ConnectionConfiguration) -> ConnectionSession<ConnectionConfiguration, Connected.WrappedValue>
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
    ) -> ConnectionSession<ConnectionConfiguration, Connected.WrappedValue> {
        createSession(configuration)
    }
}

public typealias Connection<Value> = ConnectionDefinition<Void, ReadOnlyConnectedValue<Value>>

extension ConnectionDefinition {
    public init<Value>(
        configurationsAreEqual: @escaping @MainActor (ConnectionConfiguration, ConnectionConfiguration) -> Bool,
        createSession: @escaping @MainActor (ConnectionConfiguration) -> ConnectionSession<ConnectionConfiguration, Value>
    ) where Connected == ReadOnlyConnectedValue<Value> {
        self.init(
            configurationsEqual: configurationsAreEqual,
            createSession: createSession
        )
    }
}

extension ConnectionDefinition where ConnectionConfiguration: Equatable {
    public init<Value>(
        createSession: @escaping @MainActor (ConnectionConfiguration) -> ConnectionSession<ConnectionConfiguration, Value>
    ) where Connected == ReadOnlyConnectedValue<Value> {
        self.init(
            configurationsAreEqual: { $0 == $1 },
            createSession: createSession
        )
    }
}

extension ConnectionDefinition where ConnectionConfiguration == Void {
    public init<Value>(
        createSession: @escaping @MainActor () -> ConnectionSession<Void, Value>
    ) where Connected == ReadOnlyConnectedValue<Value> {
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
            ConnectionSession(
                currentValue: currentValue,
                updates: updates
            )
        }
    }
}

extension ConnectionDefinition {
    public init<Value>(
        configurationsAreEqual: @escaping @MainActor (ConnectionConfiguration, ConnectionConfiguration) -> Bool,
        createSession: @escaping @MainActor (ConnectionConfiguration) -> WritableConnectionSession<ConnectionConfiguration, Value>
    ) where Connected == WritableConnectedValue<Value> {
        self.init(
            configurationsEqual: configurationsAreEqual,
            createSession: { createSession($0).connectionSession }
        )
    }
}

extension ConnectionDefinition where ConnectionConfiguration: Equatable {
    public init<Value>(
        createSession: @escaping @MainActor (ConnectionConfiguration) -> WritableConnectionSession<ConnectionConfiguration, Value>
    ) where Connected == WritableConnectedValue<Value> {
        self.init(
            configurationsAreEqual: { $0 == $1 },
            createSession: createSession
        )
    }
}

extension ConnectionDefinition where ConnectionConfiguration == Void {
    public init<Value>(
        createSession: @escaping @MainActor () -> WritableConnectionSession<Void, Value>
    ) where Connected == WritableConnectedValue<Value> {
        self.init(
            configurationsAreEqual: { _, _ in true },
            createSession: { _ in createSession() }
        )
    }

    public init<Value>(
        currentValue: @escaping @MainActor () -> Value,
        updates: any Publisher<Value, Never>,
        setValue: @escaping @MainActor (Value) -> Void
    ) where Connected == WritableConnectedValue<Value> {
        self.init {
            WritableConnectionSession(
                currentValue: currentValue,
                updates: updates,
                setValue: setValue
            )
        }
    }
}

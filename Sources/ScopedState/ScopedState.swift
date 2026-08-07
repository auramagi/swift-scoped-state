//
//  ContainerScopeModifier.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import Combine
import Observation
import SwiftUI

// MARK: - Connection sources and sessions

final class IdentityToken {}

/// A live connection created for one SwiftUI location.
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

/// A live writable connection created for one SwiftUI location.
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

    @MainActor static func makeProjection(
        readOnly: ScopedStateProjection<WrappedValue>,
        writable: Binding<WrappedValue>
    ) -> Projection
}

public enum ReadOnlyConnectedValue<Value>: ConnectedValue {
    public typealias WrappedValue = Value

    public typealias Projection = ScopedStateProjection<Value>

    @MainActor public static func makeProjection(
        readOnly: ScopedStateProjection<Value>,
        writable: Binding<Value>
    ) -> ScopedStateProjection<Value> {
        readOnly
    }
}

public enum WritableConnectedValue<Value>: ConnectedValue {
    public typealias WrappedValue = Value

    public typealias Projection = Binding<Value>

    @MainActor public static func makeProjection(
        readOnly: ScopedStateProjection<Value>,
        writable: Binding<Value>
    ) -> Binding<Value> {
        writable
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

// MARK: - Universal connection lifecycle

/// The observable value storage used both by connected properties and as the
/// exact scope type stored in SwiftUI's environment.
@MainActor @Observable final class ScopedStateStorage<Value> {
    private var value: Value?

    var requiredValue: Value {
        if let value {
            value
        } else {
            preconditionFailure("Scoped state was read before DynamicProperty.update()")
        }
    }

    func receive(_ value: Value) {
        self.value = value
    }
}

/// The single, fully typed lifecycle owner used for ordinary state and scopes.
/// Its source, configuration, session, and value types remain known after connection.
@MainActor final class ConnectionHost<Configuration, Value> {
    let storage = ScopedStateStorage<Value>()

    private var sourceIdentity: ObjectIdentifier?

    private var configuration: Configuration?

    private var session: ConnectionSession<Configuration, Value>?

    private var subscription: AnyCancellable?

    func connectIfNeeded<Connected: ConnectedValue>(
        to source: ConnectionDefinition<Configuration, Connected>,
        configuration: Configuration
    ) where Connected.WrappedValue == Value {
        let sourceIdentity = source.identity

        guard self.sourceIdentity != sourceIdentity else {
            updateConfigurationIfNeeded(configuration, source: source)
            return
        }

        let session = source.makeSession(configuration: configuration)
        subscription?.cancel()

        self.sourceIdentity = sourceIdentity
        self.configuration = configuration
        self.session = session
        storage.receive(session.currentValue())

        subscription = session.updates
            .eraseToAnyPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard self?.sourceIdentity == sourceIdentity else {
                    return
                }
                self?.storage.receive(value)
            }
    }

    private func updateConfigurationIfNeeded<Connected: ConnectedValue>(
        _ configuration: Configuration,
        source: ConnectionDefinition<Configuration, Connected>
    ) where Connected.WrappedValue == Value {
        guard
            let previousConfiguration = self.configuration,
            !source.configurationsAreEqual(previousConfiguration, configuration),
            let session
        else {
            return
        }

        self.configuration = configuration
        session.updateConfiguration(configuration)
        storage.receive(session.currentValue())
    }

    subscript<Member>(member keyPath: ReferenceWritableKeyPath<Value, Member>) -> Member {
        get {
            storage.requiredValue[keyPath: keyPath]
        }
        set {
            storage.requiredValue[keyPath: keyPath] = newValue
        }
    }
}

extension ConnectionHost {
    var replaceableValue: Value {
        get { storage.requiredValue }
        set { replace(with: newValue) }
    }

    private func replace(with value: Value) {
        guard let session else {
            preconditionFailure("Scoped state was written before DynamicProperty.update()")
        }

        guard let setValue = session.setValue else {
            preconditionFailure("A writable connection session must provide a setter")
        }

        setValue(value)
    }
}

// MARK: - Scoped state projections

@MainActor private protocol ScopedStateProjectionLocation<Value> {
    associatedtype Value

    func memberBinding<Member>(_ keyPath: ReferenceWritableKeyPath<Value, Member>) -> Binding<Member>
}

/// The SwiftUI-owned location from which `ScopedState` derives its projection.
@MainActor private struct ScopedStateLocation<Configuration, Value>: ScopedStateProjectionLocation {
    fileprivate let host: Binding<ConnectionHost<Configuration, Value>>

    func memberBinding<Member>(
        _ keyPath: ReferenceWritableKeyPath<Value, Member>
    ) -> Binding<Member> {
        host[dynamicMember: \ConnectionHost<Configuration, Value>.[member: keyPath]]
    }
}

@MainActor @dynamicMemberLookup public struct ScopedStateProjection<Value> {
    private let location: any ScopedStateProjectionLocation<Value>

    fileprivate init<Location: ScopedStateProjectionLocation<Value>>(location: Location) {
        self.location = location
    }

    public subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Member>) -> Binding<Member> {
        location.memberBinding(keyPath)
    }
}

// MARK: - Scoped state dynamic property

@MainActor @propertyWrapper public struct ScopedState<Scope, Configuration, Connected: ConnectedValue>: @MainActor DynamicProperty {
    @Environment(ScopedStateStorage<Scope>.self) private var scope

    @State private var host = ConnectionHost<Configuration, Connected.WrappedValue>()

    private let keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Connected>>

    private let configuration: Configuration

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Void, Connected>>
    ) where Configuration == Void {
        self.init(keyPath, configuration: ())
    }

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Connected>>,
        configuration: Configuration
    ) {
        self.keyPath = keyPath
        self.configuration = configuration
    }

    public func update() {
        host.connectIfNeeded(
            to: scope.requiredValue[keyPath: keyPath],
            configuration: configuration
        )
    }

    var storage: ScopedStateStorage<Connected.WrappedValue> {
        host.storage
    }

    public var wrappedValue: Connected.WrappedValue {
        host.storage.requiredValue
    }

    public var projectedValue: Connected.Projection {
        Connected.makeProjection(
            readOnly: ScopedStateProjection(location: ScopedStateLocation(host: $host)),
            writable: $host.replaceableValue
        )
    }
}

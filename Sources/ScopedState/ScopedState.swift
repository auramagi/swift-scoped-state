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
        projection.rootBinding
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
    var value: Value?

    var requiredValue: Value {
        if let value {
            value
        } else {
            preconditionFailure("Scoped state was read before DynamicProperty.update()")
        }
    }
}

// MARK: - Scoped state projections

@MainActor fileprivate protocol ScopedStateProjectionSource<WrappedValue> {
    associatedtype WrappedValue

    var rootBinding: Binding<WrappedValue> { get }

    func memberBinding<Member>(
        _ keyPath: ReferenceWritableKeyPath<WrappedValue, Member>
    ) -> Binding<Member>
}

@MainActor @dynamicMemberLookup public struct ScopedStateProjection<Value> {
    private let source: any ScopedStateProjectionSource<Value>

    fileprivate init<Source: ScopedStateProjectionSource<Value>>(source: Source) {
        self.source = source
    }

    fileprivate var rootBinding: Binding<Value> {
        source.rootBinding
    }

    public subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Member>) -> Binding<Member> {
        source.memberBinding(keyPath)
    }
}

// MARK: - Scoped state dynamic property

@MainActor @propertyWrapper public struct ScopedState<Scope, Configuration, Value: ConnectedValue>: @MainActor DynamicProperty {
    @MainActor private final class Coordinator {
        var value = ScopedStateStorage<Value.WrappedValue>()

        var sourceIdentity: ObjectIdentifier?

        var configuration: Configuration?

        var session: ConnectionSession<Configuration, Value.WrappedValue>?

        var subscription: AnyCancellable?

        var replaceableValue: Value.WrappedValue {
            get {
                value.requiredValue
            }
            set {
                guard let session else {
                    preconditionFailure("Scoped state was written before DynamicProperty.update()")
                }

                guard let setValue = session.setValue else {
                    preconditionFailure("A writable connection session must provide a setter")
                }

                setValue(newValue)
            }
        }

        subscript<Member>(member keyPath: ReferenceWritableKeyPath<Value.WrappedValue, Member>) -> Member {
            get {
                value.requiredValue[keyPath: keyPath]
            }
            set {
                value.requiredValue[keyPath: keyPath] = newValue
            }
        }
    }

    @MainActor private struct ProjectionSource: ScopedStateProjectionSource {
        typealias WrappedValue = Value.WrappedValue

        let coordinator: Binding<Coordinator>

        var rootBinding: Binding<WrappedValue> {
            coordinator.replaceableValue
        }

        func memberBinding<Member>(
            _ keyPath: ReferenceWritableKeyPath<WrappedValue, Member>
        ) -> Binding<Member> {
            coordinator[dynamicMember: \Coordinator.[member: keyPath]]
        }
    }

    @Environment(ScopedStateStorage<Scope>.self) private var scope

    @State private var coordinator: Coordinator

    private let keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Value>>

    private let configuration: Configuration

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Void, Value>>
    ) where Configuration == Void {
        self.init(keyPath, configuration: ())
    }

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Value>>,
        configuration: Configuration
    ) {
        self._coordinator = State(initialValue: Coordinator())
        self.keyPath = keyPath
        self.configuration = configuration
    }

    public func update() {
        connectIfNeeded(
            to: scope.requiredValue[keyPath: keyPath],
            configuration: configuration
        )
    }

    var valueStorage: ScopedStateStorage<Value.WrappedValue> {
        coordinator.value
    }

    public var wrappedValue: Value.WrappedValue {
        coordinator.value.requiredValue
    }

    public var projectedValue: Value.Projection {
        let projection = ScopedStateProjection(source: ProjectionSource(coordinator: $coordinator))
        return Value.transformProjection(projection)
    }

    private func connectIfNeeded(
        to source: ConnectionDefinition<Configuration, Value>,
        configuration: Configuration
    ) {
        let sourceIdentity = source.identity

        guard coordinator.sourceIdentity != sourceIdentity else {
            updateConfigurationIfNeeded(configuration, source: source)
            return
        }

        let session = source.makeSession(configuration: configuration)
        coordinator.subscription?.cancel()

        coordinator.sourceIdentity = sourceIdentity
        coordinator.configuration = configuration
        coordinator.session = session
        coordinator.value.value = session.currentValue()

        coordinator.subscription = session.updates
            .eraseToAnyPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak coordinator] value in
                guard coordinator?.sourceIdentity == sourceIdentity else {
                    return
                }
                coordinator?.value.value = value
            }
    }

    private func updateConfigurationIfNeeded(
        _ configuration: Configuration,
        source: ConnectionDefinition<Configuration, Value>
    ) {
        guard
            let previousConfiguration = coordinator.configuration,
            !source.configurationsAreEqual(previousConfiguration, configuration),
            let session = coordinator.session
        else {
            return
        }

        coordinator.configuration = configuration
        session.updateConfiguration(configuration)
        coordinator.value.value = session.currentValue()
    }
}

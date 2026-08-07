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
@MainActor public struct ConnectionSession<Input, Value> {
    let currentValue: @MainActor () -> Value

    let updates: any Publisher<Value, Never>

    let setValue: (@MainActor (Value) -> Void)?

    let updateInput: @MainActor (Input) -> Void

    public init(
        currentValue: @escaping @MainActor () -> Value,
        updates: any Publisher<Value, Never>,
        updateInput: @escaping @MainActor (Input) -> Void = { _ in }
    ) {
        self.currentValue = currentValue
        self.updates = updates
        self.setValue = nil
        self.updateInput = updateInput
    }

    init(
        currentValue: @escaping @MainActor () -> Value,
        updates: any Publisher<Value, Never>,
        setValue: @escaping @MainActor (Value) -> Void,
        updateInput: @escaping @MainActor (Input) -> Void
    ) {
        self.currentValue = currentValue
        self.updates = updates
        self.setValue = setValue
        self.updateInput = updateInput
    }
}

/// A live writable connection created for one SwiftUI location.
/// Its setter is required, so writable connections cannot be constructed
/// without root replacement support.
@MainActor public struct WritableConnectionSession<Input, Value> {
    let currentValue: @MainActor () -> Value

    let updates: any Publisher<Value, Never>

    let setValue: @MainActor (Value) -> Void

    let updateInput: @MainActor (Input) -> Void

    public init(
        currentValue: @escaping @MainActor () -> Value,
        updates: any Publisher<Value, Never>,
        setValue: @escaping @MainActor (Value) -> Void,
        updateInput: @escaping @MainActor (Input) -> Void = { _ in }
    ) {
        self.currentValue = currentValue
        self.updates = updates
        self.setValue = setValue
        self.updateInput = updateInput
    }

    var connectionSession: ConnectionSession<Input, Value> {
        ConnectionSession(
            currentValue: currentValue,
            updates: updates,
            setValue: setValue,
            updateInput: updateInput
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
@MainActor public struct ConnectionDefinition<ConnectionInput, Connected: ConnectedValue> {
    public typealias Input<NewInput> = ConnectionDefinition<NewInput, Connected>

    public typealias Writable = ConnectionDefinition<ConnectionInput, WritableConnectedValue<Connected.WrappedValue>>

    let inputsEqual: @MainActor (ConnectionInput, ConnectionInput) -> Bool

    let createSession: @MainActor (ConnectionInput) -> ConnectionSession<ConnectionInput, Connected.WrappedValue>

    let identityToken = IdentityToken()

    private init(
        inputsEqual: @escaping @MainActor (ConnectionInput, ConnectionInput) -> Bool,
        createSession: @escaping @MainActor (ConnectionInput) -> ConnectionSession<ConnectionInput, Connected.WrappedValue>
    ) {
        self.inputsEqual = inputsEqual
        self.createSession = createSession
    }

    public var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor public func inputsAreEqual(_ lhs: ConnectionInput, _ rhs: ConnectionInput) -> Bool {
        inputsEqual(lhs, rhs)
    }

    @MainActor public func makeSession(input: ConnectionInput) -> ConnectionSession<ConnectionInput, Connected.WrappedValue> {
        createSession(input)
    }
}

public typealias Connection<Value> = ConnectionDefinition<Void, ReadOnlyConnectedValue<Value>>

extension ConnectionDefinition {
    public init<Value>(
        inputsAreEqual: @escaping @MainActor (ConnectionInput, ConnectionInput) -> Bool,
        createSession: @escaping @MainActor (ConnectionInput) -> ConnectionSession<ConnectionInput, Value>
    ) where Connected == ReadOnlyConnectedValue<Value> {
        self.init(
            inputsEqual: inputsAreEqual,
            createSession: createSession
        )
    }
}

extension ConnectionDefinition where ConnectionInput: Equatable {
    public init<Value>(
        createSession: @escaping @MainActor (ConnectionInput) -> ConnectionSession<ConnectionInput, Value>
    ) where Connected == ReadOnlyConnectedValue<Value> {
        self.init(
            inputsAreEqual: { $0 == $1 },
            createSession: createSession
        )
    }
}

extension ConnectionDefinition where ConnectionInput == Void {
    public init<Value>(
        createSession: @escaping @MainActor () -> ConnectionSession<Void, Value>
    ) where Connected == ReadOnlyConnectedValue<Value> {
        self.init(
            inputsAreEqual: { _, _ in true },
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
        inputsAreEqual: @escaping @MainActor (ConnectionInput, ConnectionInput) -> Bool,
        createSession: @escaping @MainActor (ConnectionInput) -> WritableConnectionSession<ConnectionInput, Value>
    ) where Connected == WritableConnectedValue<Value> {
        self.init(
            inputsEqual: inputsAreEqual,
            createSession: { createSession($0).connectionSession }
        )
    }
}

extension ConnectionDefinition where ConnectionInput: Equatable {
    public init<Value>(
        createSession: @escaping @MainActor (ConnectionInput) -> WritableConnectionSession<ConnectionInput, Value>
    ) where Connected == WritableConnectedValue<Value> {
        self.init(
            inputsAreEqual: { $0 == $1 },
            createSession: createSession
        )
    }
}

extension ConnectionDefinition where ConnectionInput == Void {
    public init<Value>(
        createSession: @escaping @MainActor () -> WritableConnectionSession<Void, Value>
    ) where Connected == WritableConnectedValue<Value> {
        self.init(
            inputsAreEqual: { _, _ in true },
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
/// Its source, input, session, and output types remain known after connection.
@MainActor final class ConnectionHost<Input, Value> {
    let storage = ScopedStateStorage<Value>()

    private var sourceIdentity: ObjectIdentifier?

    private var input: Input?

    private var session: ConnectionSession<Input, Value>?

    private var subscription: AnyCancellable?

    func connectIfNeeded<Connected: ConnectedValue>(
        to source: ConnectionDefinition<Input, Connected>,
        input: Input
    ) where Connected.WrappedValue == Value {
        let sourceIdentity = source.identity

        guard self.sourceIdentity != sourceIdentity else {
            updateInputIfNeeded(input, source: source)
            return
        }

        let session = source.makeSession(input: input)
        subscription?.cancel()

        self.sourceIdentity = sourceIdentity
        self.input = input
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

    private func updateInputIfNeeded<Connected: ConnectedValue>(
        _ input: Input,
        source: ConnectionDefinition<Input, Connected>
    ) where Connected.WrappedValue == Value {
        guard
            let previousInput = self.input,
            !source.inputsAreEqual(previousInput, input),
            let session
        else {
            return
        }

        self.input = input
        session.updateInput(input)
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
@MainActor private struct ScopedStateLocation<Input, Value>: ScopedStateProjectionLocation {
    fileprivate let host: Binding<ConnectionHost<Input, Value>>

    func memberBinding<Member>(
        _ keyPath: ReferenceWritableKeyPath<Value, Member>
    ) -> Binding<Member> {
        host[dynamicMember: \ConnectionHost<Input, Value>.[member: keyPath]]
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

@MainActor @propertyWrapper public struct ScopedState<Scope, Input, Connected: ConnectedValue>: @MainActor DynamicProperty {
    @Environment(ScopedStateStorage<Scope>.self) private var scope

    @State private var host = ConnectionHost<Input, Connected.WrappedValue>()

    private let keyPath: KeyPath<Scope, ConnectionDefinition<Input, Connected>>

    private let input: Input

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Void, Connected>>
    ) where Input == Void {
        self.init(keyPath, input: ())
    }

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Input, Connected>>,
        input: Input
    ) {
        self.keyPath = keyPath
        self.input = input
    }

    public func update() {
        host.connectIfNeeded(
            to: scope.requiredValue[keyPath: keyPath],
            input: input
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

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

public enum ConnectionWriteAccess {}

/// The generic implementation underlying the public `Connection<Value>` family.
@MainActor public struct ConnectionDefinition<ConnectionInput, Value, Access> {
    public typealias Input<NewInput> = ConnectionDefinition<NewInput, Value, Access>

    public typealias Writable = ConnectionDefinition<ConnectionInput, Value, ConnectionWriteAccess>

    let inputsEqual: @MainActor (ConnectionInput, ConnectionInput) -> Bool

    let createSession: @MainActor (ConnectionInput) -> ConnectionSession<ConnectionInput, Value>

    let identityToken = IdentityToken()

    private init(
        inputsEqual: @escaping @MainActor (ConnectionInput, ConnectionInput) -> Bool,
        createSession: @escaping @MainActor (ConnectionInput) -> ConnectionSession<ConnectionInput, Value>
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

    @MainActor public func makeSession(input: ConnectionInput) -> ConnectionSession<ConnectionInput, Value> {
        createSession(input)
    }
}

public typealias Connection<Value> = ConnectionDefinition<Void, Value, Void>

extension ConnectionDefinition where Access == Void {
    public init(
        inputsAreEqual: @escaping @MainActor (ConnectionInput, ConnectionInput) -> Bool,
        createSession: @escaping @MainActor (ConnectionInput) -> ConnectionSession<ConnectionInput, Value>
    ) {
        self.init(
            inputsEqual: inputsAreEqual,
            createSession: createSession
        )
    }
}

extension ConnectionDefinition where ConnectionInput: Equatable, Access == Void {
    public init(
        createSession: @escaping @MainActor (ConnectionInput) -> ConnectionSession<ConnectionInput, Value>
    ) {
        self.init(
            inputsAreEqual: { $0 == $1 },
            createSession: createSession
        )
    }
}

extension ConnectionDefinition where ConnectionInput == Void, Access == Void {
    public init(
        createSession: @escaping @MainActor () -> ConnectionSession<Void, Value>
    ) {
        self.init(
            inputsAreEqual: { _, _ in true },
            createSession: { _ in createSession() }
        )
    }

    public init(
        currentValue: @escaping @MainActor () -> Value,
        updates: any Publisher<Value, Never>
    ) {
        self.init {
            ConnectionSession(
                currentValue: currentValue,
                updates: updates
            )
        }
    }
}

extension ConnectionDefinition where Access == ConnectionWriteAccess {
    public init(
        inputsAreEqual: @escaping @MainActor (ConnectionInput, ConnectionInput) -> Bool,
        createSession: @escaping @MainActor (ConnectionInput) -> WritableConnectionSession<ConnectionInput, Value>
    ) {
        self.init(
            inputsEqual: inputsAreEqual,
            createSession: { createSession($0).connectionSession }
        )
    }
}

extension ConnectionDefinition where ConnectionInput: Equatable, Access == ConnectionWriteAccess {
    public init(
        createSession: @escaping @MainActor (ConnectionInput) -> WritableConnectionSession<ConnectionInput, Value>
    ) {
        self.init(
            inputsAreEqual: { $0 == $1 },
            createSession: createSession
        )
    }
}

extension ConnectionDefinition where ConnectionInput == Void, Access == ConnectionWriteAccess {
    public init(
        createSession: @escaping @MainActor () -> WritableConnectionSession<Void, Value>
    ) {
        self.init(
            inputsAreEqual: { _, _ in true },
            createSession: { _ in createSession() }
        )
    }

    public init(
        currentValue: @escaping @MainActor () -> Value,
        updates: any Publisher<Value, Never>,
        setValue: @escaping @MainActor (Value) -> Void
    ) {
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
@MainActor final class ConnectionHost<Input, Value, Access> {
    let storage = ScopedStateStorage<Value>()

    private var sourceIdentity: ObjectIdentifier?

    private var input: Input?

    private var session: ConnectionSession<Input, Value>?

    private var subscription: AnyCancellable?

    func connectIfNeeded(
        to source: ConnectionDefinition<Input, Value, Access>,
        input: Input
    ) {
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

    private func updateInputIfNeeded(
        _ input: Input,
        source: ConnectionDefinition<Input, Value, Access>
    ) {
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

extension ConnectionHost where Access == ConnectionWriteAccess {
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

/// The SwiftUI-owned location from which `ScopedState` derives its projection.
@MainActor struct ScopedStateLocation<Input, Value, Access> {
    fileprivate let host: Binding<ConnectionHost<Input, Value, Access>>

    fileprivate func memberBinding<Member>(
        _ keyPath: ReferenceWritableKeyPath<Value, Member>
    ) -> Binding<Member> {
        host[dynamicMember: \ConnectionHost<Input, Value, Access>.[member: keyPath]]
    }
}

@MainActor @dynamicMemberLookup public struct ScopedStateProjection<Input, Value> {
    fileprivate let location: ScopedStateLocation<Input, Value, Void>

    public subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Member>) -> Binding<Member> {
        location.memberBinding(keyPath)
    }
}

// MARK: - Scoped state dynamic property

@MainActor @propertyWrapper public struct ScopedState<Scope, Input, Value, Access, Projection>: @MainActor DynamicProperty {
    @Environment(ScopedStateStorage<Scope>.self) private var scope

    @State private var host = ConnectionHost<Input, Value, Access>()

    private let keyPath: KeyPath<Scope, ConnectionDefinition<Input, Value, Access>>

    private let input: Input

    // Swift only synthesizes `$property` when `projectedValue` is available on
    // the primary wrapper declaration. Each initializer fixes its projection
    // without coupling connection definitions to SwiftUI projection semantics.
    private let makeProjection: @MainActor (Binding<ConnectionHost<Input, Value, Access>>) -> Projection

    public init(
        _ keyPath: KeyPath<Scope, Connection<Value>>
    ) where
        Input == Void,
        Access == Void,
        Projection == ScopedStateProjection<Void, Value>
    {
        self.init(keyPath, input: ())
    }

    public init(
        _ keyPath: KeyPath<Scope, Connection<Value>.Input<Input>>,
        input: Input
    ) where
        Access == Void,
        Projection == ScopedStateProjection<Input, Value>
    {
        self.keyPath = keyPath
        self.input = input
        self.makeProjection = { host in
            ScopedStateProjection(location: ScopedStateLocation(host: host))
        }
    }

    public init(
        _ keyPath: KeyPath<Scope, Connection<Value>.Writable>
    ) where
        Input == Void,
        Access == ConnectionWriteAccess,
        Projection == Binding<Value>
    {
        self.init(keyPath, input: ())
    }

    public init(
        _ keyPath: KeyPath<Scope, Connection<Value>.Input<Input>.Writable>,
        input: Input
    ) where Access == ConnectionWriteAccess, Projection == Binding<Value> {
        self.keyPath = keyPath
        self.input = input
        self.makeProjection = { host in
            host.replaceableValue
        }
    }

    public func update() {
        host.connectIfNeeded(
            to: scope.requiredValue[keyPath: keyPath],
            input: input
        )
    }

    var storage: ScopedStateStorage<Value> {
        host.storage
    }

    public var wrappedValue: Value {
        host.storage.requiredValue
    }

    public var projectedValue: Projection {
        makeProjection($host)
    }
}

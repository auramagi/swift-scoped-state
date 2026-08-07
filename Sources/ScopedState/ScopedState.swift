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

public protocol ConnectionSource<Input>: SendableMetatype {
    associatedtype Input

    associatedtype Value

    @MainActor var identity: ObjectIdentifier { get }

    @MainActor func inputsAreEqual(_ lhs: Input, _ rhs: Input) -> Bool

    @MainActor func makeSession(input: Input) -> ConnectionSession<Input, Value>
}

private protocol RootWritableConnectionSource: ConnectionSource {}

/// A read-only connection whose session is created for typed input.
@MainActor public struct Connection<Input, Value>: ConnectionSource {
    let inputsEqual: @MainActor (Input, Input) -> Bool

    let createSession: @MainActor (Input) -> ConnectionSession<Input, Value>

    let identityToken = IdentityToken()

    public init(
        inputsAreEqual: @escaping @MainActor (Input, Input) -> Bool,
        createSession: @escaping @MainActor (Input) -> ConnectionSession<Input, Value>
    ) {
        self.inputsEqual = inputsAreEqual
        self.createSession = createSession
    }

    public var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor public func inputsAreEqual(_ lhs: Input, _ rhs: Input) -> Bool {
        inputsEqual(lhs, rhs)
    }

    @MainActor public func makeSession(input: Input) -> ConnectionSession<Input, Value> {
        createSession(input)
    }
}

extension Connection where Input: Equatable {
    public init(
        createSession: @escaping @MainActor (Input) -> ConnectionSession<Input, Value>
    ) {
        self.init(
            inputsAreEqual: { $0 == $1 },
            createSession: createSession
        )
    }
}

extension Connection where Input == Void {
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

/// A writable connection whose session is created for typed input.
@MainActor public struct WritableConnection<Input, Value>: ConnectionSource {
    let inputsEqual: @MainActor (Input, Input) -> Bool

    let createSession: @MainActor (Input) -> WritableConnectionSession<Input, Value>

    let identityToken = IdentityToken()

    public init(
        inputsAreEqual: @escaping @MainActor (Input, Input) -> Bool,
        createSession: @escaping @MainActor (Input) -> WritableConnectionSession<Input, Value>
    ) {
        self.inputsEqual = inputsAreEqual
        self.createSession = createSession
    }

    public var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor public func inputsAreEqual(_ lhs: Input, _ rhs: Input) -> Bool {
        inputsEqual(lhs, rhs)
    }

    @MainActor public func makeSession(input: Input) -> ConnectionSession<Input, Value> {
        createSession(input).connectionSession
    }
}

extension WritableConnection where Input: Equatable {
    public init(
        createSession: @escaping @MainActor (Input) -> WritableConnectionSession<Input, Value>
    ) {
        self.init(
            inputsAreEqual: { $0 == $1 },
            createSession: createSession
        )
    }
}

extension WritableConnection where Input == Void {
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

extension WritableConnection: RootWritableConnectionSource {}

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
@MainActor final class ConnectionHost<Source: ConnectionSource> {
    let storage = ScopedStateStorage<Source.Value>()

    private var sourceIdentity: ObjectIdentifier?

    private var input: Source.Input?

    private var session: ConnectionSession<Source.Input, Source.Value>?

    private var subscription: AnyCancellable?

    func connectIfNeeded(to source: Source, input: Source.Input) {
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

    private func updateInputIfNeeded(_ input: Source.Input, source: Source) {
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

    subscript<Member>(member keyPath: ReferenceWritableKeyPath<Source.Value, Member>) -> Member {
        get {
            storage.requiredValue[keyPath: keyPath]
        }
        set {
            storage.requiredValue[keyPath: keyPath] = newValue
        }
    }
}

extension ConnectionHost where Source: RootWritableConnectionSource {
    var replaceableValue: Source.Value {
        get { storage.requiredValue }
        set { replace(with: newValue) }
    }

    private func replace(with value: Source.Value) {
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
@MainActor struct ScopedStateLocation<Source: ConnectionSource> {
    fileprivate let host: Binding<ConnectionHost<Source>>

    fileprivate func memberBinding<Member>(
        _ keyPath: ReferenceWritableKeyPath<Source.Value, Member>
    ) -> Binding<Member> {
        host[dynamicMember: \ConnectionHost<Source>.[member: keyPath]]
    }
}

@MainActor @dynamicMemberLookup public struct ScopedStateProjection<Input, Value> {
    fileprivate let location: ScopedStateLocation<Connection<Input, Value>>

    public subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Member>) -> Binding<Member> {
        location.memberBinding(keyPath)
    }
}

// MARK: - Scoped state dynamic property

@MainActor @propertyWrapper public struct ScopedState<Scope, Source: ConnectionSource, Projection>: @MainActor DynamicProperty {
    @Environment(ScopedStateStorage<Scope>.self) private var scope

    @State private var host = ConnectionHost<Source>()

    private let keyPath: KeyPath<Scope, Source>

    private let input: Source.Input

    // Swift only synthesizes `$property` when `projectedValue` is available on
    // the primary wrapper declaration. Each initializer fixes its projection
    // without making connection sources depend on SwiftUI projection semantics.
    private let makeProjection: @MainActor (Binding<ConnectionHost<Source>>) -> Projection

    public init<Value>(
        _ keyPath: KeyPath<Scope, Connection<Void, Value>>
    ) where
        Source == Connection<Void, Value>,
        Projection == ScopedStateProjection<Void, Value>
    {
        self.init(keyPath, input: ())
    }

    public init<Input, Value>(
        _ keyPath: KeyPath<Scope, Connection<Input, Value>>,
        input: Input
    ) where
        Source == Connection<Input, Value>,
        Projection == ScopedStateProjection<Input, Value>
    {
        self.keyPath = keyPath
        self.input = input
        self.makeProjection = { host in
            ScopedStateProjection(location: ScopedStateLocation(host: host))
        }
    }

    public init<Value>(
        _ keyPath: KeyPath<Scope, WritableConnection<Void, Value>>
    ) where Source == WritableConnection<Void, Value>, Projection == Binding<Value> {
        self.init(keyPath, input: ())
    }

    public init<Input, Value>(
        _ keyPath: KeyPath<Scope, WritableConnection<Input, Value>>,
        input: Input
    ) where Source == WritableConnection<Input, Value>, Projection == Binding<Value> {
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

    var storage: ScopedStateStorage<Source.Value> {
        host.storage
    }

    public var wrappedValue: Source.Value {
        host.storage.requiredValue
    }

    public var projectedValue: Projection {
        makeProjection($host)
    }
}

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

public enum NoConnectionInput: Equatable {
    case value
}

/// A live connection created for one SwiftUI location.
/// Its closures retain any implementation object needed to keep the value alive.
@MainActor public struct ConnectionSession<Input: Equatable, Value> {
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
@MainActor public struct WritableConnectionSession<Input: Equatable, Value> {
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
    associatedtype Input: Equatable

    associatedtype Value

    @MainActor var identity: ObjectIdentifier { get }

    @MainActor func makeSession(input: Input) -> ConnectionSession<Input, Value>
}

private protocol RootWritableConnectionSource: ConnectionSource {}

/// A read-only connection whose session is created for typed input.
@MainActor public struct Connection<Input: Equatable, Value>: ConnectionSource {
    let createSession: @MainActor (Input) -> ConnectionSession<Input, Value>

    let identityToken = IdentityToken()

    public init(
        createSession: @escaping @MainActor (Input) -> ConnectionSession<Input, Value>
    ) {
        self.createSession = createSession
    }

    public var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor public func makeSession(input: Input) -> ConnectionSession<Input, Value> {
        createSession(input)
    }
}

extension Connection where Input == NoConnectionInput {
    public init(
        currentValue: @escaping @MainActor () -> Value,
        updates: any Publisher<Value, Never>
    ) {
        self.init { _ in
            ConnectionSession(
                currentValue: currentValue,
                updates: updates
            )
        }
    }
}

/// A writable connection whose session is created for typed input.
@MainActor public struct WritableConnection<Input: Equatable, Value>: ConnectionSource {
    let createSession: @MainActor (Input) -> WritableConnectionSession<Input, Value>

    let identityToken = IdentityToken()

    public init(
        createSession: @escaping @MainActor (Input) -> WritableConnectionSession<Input, Value>
    ) {
        self.createSession = createSession
    }

    public var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor public func makeSession(input: Input) -> ConnectionSession<Input, Value> {
        createSession(input).connectionSession
    }
}

extension WritableConnection where Input == NoConnectionInput {
    public init(
        currentValue: @escaping @MainActor () -> Value,
        updates: any Publisher<Value, Never>,
        setValue: @escaping @MainActor (Value) -> Void
    ) {
        self.init { _ in
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
            updateInputIfNeeded(input)
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

    private func updateInputIfNeeded(_ input: Source.Input) {
        guard self.input != input, let session else {
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

// MARK: - Scoped state keys and projections

public protocol ConnectionKey {
    associatedtype Scope

    associatedtype Source: ConnectionSource<NoConnectionInput>

    associatedtype Projection

    var keyPath: KeyPath<Scope, Source> { get }

    @MainActor func projection(for location: ScopedStateLocation<Source>) -> Projection
}

/// The SwiftUI-owned location from which a connection key derives its
/// projected value.
@MainActor public struct ScopedStateLocation<Source: ConnectionSource<NoConnectionInput>> {
    fileprivate let host: Binding<ConnectionHost<Source>>

    fileprivate func memberBinding<Member>(
        _ keyPath: ReferenceWritableKeyPath<Source.Value, Member>
    ) -> Binding<Member> {
        host[dynamicMember: \ConnectionHost<Source>.[member: keyPath]]
    }
}

public struct ReadOnlyConnectionKey<Scope, Value>: ConnectionKey {
    public typealias Source = Connection<NoConnectionInput, Value>

    public let keyPath: KeyPath<Scope, Connection<NoConnectionInput, Value>>

    @MainActor public func projection(
        for location: ScopedStateLocation<Connection<NoConnectionInput, Value>>
    ) -> ScopedStateProjection<Value> {
        ScopedStateProjection(location: location)
    }
}

public struct WritableConnectionKey<Scope, Value>: ConnectionKey {
    public typealias Source = WritableConnection<NoConnectionInput, Value>

    public let keyPath: KeyPath<Scope, WritableConnection<NoConnectionInput, Value>>

    @MainActor public func projection(
        for location: ScopedStateLocation<WritableConnection<NoConnectionInput, Value>>
    ) -> Binding<Value> {
        location.host.replaceableValue
    }
}

@MainActor @dynamicMemberLookup public struct ScopedStateProjection<Value> {
    fileprivate let location: ScopedStateLocation<Connection<NoConnectionInput, Value>>

    public subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Member>) -> Binding<Member> {
        location.memberBinding(keyPath)
    }
}

// MARK: - Scoped state dynamic property

@MainActor @propertyWrapper public struct ScopedState<Key: ConnectionKey>: @MainActor DynamicProperty {
    @Environment private var scope: ScopedStateStorage<Key.Scope>

    @State private var host = ConnectionHost<Key.Source>()

    private let key: Key

    public init<Scope, Value>(
        _ keyPath: KeyPath<Scope, Connection<NoConnectionInput, Value>>
    ) where Key == ReadOnlyConnectionKey<Scope, Value> {
        self.key = ReadOnlyConnectionKey(keyPath: keyPath)
        self._scope = Environment(ScopedStateStorage<Scope>.self)
    }

    public init<Scope, Value>(
        _ keyPath: KeyPath<Scope, WritableConnection<NoConnectionInput, Value>>
    ) where Key == WritableConnectionKey<Scope, Value> {
        self.key = WritableConnectionKey(keyPath: keyPath)
        self._scope = Environment(ScopedStateStorage<Scope>.self)
    }

    public func update() {
        host.connectIfNeeded(
            to: scope.requiredValue[keyPath: key.keyPath],
            input: .value
        )
    }

    public var wrappedValue: Key.Source.Value {
        host.storage.requiredValue
    }

    public var projectedValue: Key.Projection {
        key.projection(for: ScopedStateLocation(host: $host))
    }
}

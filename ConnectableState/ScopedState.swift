import Combine
import Observation
import SwiftUI

// MARK: - Connection sources and sessions

final class ConnectionIdentity {}

enum NoConnectionInput: Equatable {
    case value
}

/// A live connection created for one SwiftUI location.
/// Its closures retain any implementation object needed to keep the value alive.
@MainActor struct ConnectionSession<Input: Equatable, Value> {
    let currentValue: @MainActor () -> Value

    let updates: any Publisher<Value, Never>

    private(set) var setValue: (@MainActor (Value) -> Void)? = nil

    private(set) var updateInput: @MainActor (Input) -> Void = { _ in }
}

protocol ConnectionSource: SendableMetatype {
    associatedtype Input: Equatable

    associatedtype Value

    @MainActor var identity: ObjectIdentifier { get }

    @MainActor func makeSession(input: Input) -> ConnectionSession<Input, Value>
}

/// A read-only connection which needs no external input.
@MainActor struct Connection<Value>: ConnectionSource {
    typealias Input = NoConnectionInput

    let currentValue: @MainActor () -> Value

    let updates: any Publisher<Value, Never>

    let identityToken = ConnectionIdentity()

    var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor func makeSession(input: NoConnectionInput) -> ConnectionSession<NoConnectionInput, Value> {
        ConnectionSession(
            currentValue: currentValue,
            updates: updates
        )
    }
}

/// A replaceable connection which needs no external input.
@MainActor struct WritableConnection<Value>: ConnectionSource {
    typealias Input = NoConnectionInput

    let currentValue: @MainActor () -> Value

    let updates: any Publisher<Value, Never>

    let setValue: @MainActor (Value) -> Void

    let identityToken = ConnectionIdentity()

    var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor func makeSession(input: NoConnectionInput) -> ConnectionSession<NoConnectionInput, Value> {
        ConnectionSession(
            currentValue: currentValue,
            updates: updates,
            setValue: setValue
        )
    }
}

/// An input-bearing connection recipe. The session it creates owns the resulting
/// state until the SwiftUI location holding the session disappears.
struct ConnectionFactory<Input: Equatable, Value>: ConnectionSource {
    let identityToken = ConnectionIdentity()

    let createSession: @MainActor (Input) -> ConnectionSession<Input, Value>

    var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor func makeSession(input: Input) -> ConnectionSession<Input, Value> {
        createSession(input)
    }
}

// MARK: - Universal connection lifecycle

/// The observable value storage used both by connected properties and as the
/// exact scope type stored in SwiftUI's environment.
@MainActor @Observable final class ScopedStateStorage<Value> {
    private(set) var value: Value?

    private(set) var generation = 0

    var requiredValue: Value {
        guard let value else {
            preconditionFailure("Scoped state was read before DynamicProperty.update()")
        }
        return value
    }

    fileprivate func receive(_ value: Value) {
        self.value = value
        generation &+= 1
    }
}

/// The single, fully typed lifecycle owner used for ordinary state and scopes.
/// Its source, input, session, and output types remain known after connection.
@MainActor private final class ConnectionHost<Source: ConnectionSource> {
    let storage = ScopedStateStorage<Source.Value>()

    var connectedValue: Source.Value {
        get { storage.requiredValue }
        set { write(newValue) }
    }

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

    private func write(_ value: Source.Value) {
        guard let setValue = session?.setValue else {
            preconditionFailure("Scoped state was written before DynamicProperty.update()")
        }

        setValue(value)
    }
}

// MARK: - Typed scope injection

@MainActor @propertyWrapper private struct ResolvedContainerScope<Container: AnyObject, Scope>: DynamicProperty {
    @MainActor private struct Storage {
        let scope = ScopedStateStorage<Scope>()

        var container: Container?

        var keyPath: KeyPath<Container, Scope>?
    }

    @State private var storage = Storage()

    let container: Container

    let keyPath: KeyPath<Container, Scope>

    func update() {
        guard storage.container !== container || storage.keyPath != keyPath else {
            return
        }

        storage.scope.receive(container[keyPath: keyPath])
        storage.container = container
        storage.keyPath = keyPath
    }

    var wrappedValue: ScopedStateStorage<Scope> {
        storage.scope
    }
}

/// Adapts an externally owned container to the scope type stored in the
/// environment. The concrete container type does not escape this modifier.
@MainActor private struct ContainerScopeModifier<Container: AnyObject, Scope>: ViewModifier {
    @ResolvedContainerScope<Container, Scope> private var scope: ScopedStateStorage<Scope>

    init(container: Container, scope keyPath: KeyPath<Container, Scope>) {
        self._scope = ResolvedContainerScope(container: container, keyPath: keyPath)
    }

    func body(content: Content) -> some View {
        content
            .environment(scope)
    }
}

extension View {
    /// Establishes a scope from an externally owned container.
    @MainActor func container<Container: AnyObject, Scope>(
        _ container: Container,
        scope: KeyPath<Container, Scope>
    ) -> some View {
        modifier(ContainerScopeModifier(container: container, scope: scope))
    }
}

// MARK: - Derived scopes

@MainActor @propertyWrapper private struct ResolvedScope<ParentScope, Input: Equatable, Scope>: DynamicProperty {
    @Environment private var parentScope: ScopedStateStorage<ParentScope>

    @State private var host = ConnectionHost<ConnectionFactory<Input, Scope>>()

    private let factory: KeyPath<ParentScope, ConnectionFactory<Input, Scope>>

    private let input: Input

    init(
        factory: KeyPath<ParentScope, ConnectionFactory<Input, Scope>>,
        input: Input
    ) {
        self.factory = factory
        self.input = input
        self._parentScope = Environment(ScopedStateStorage<ParentScope>.self)
    }

    func update() {
        _ = parentScope.generation
        host.connectIfNeeded(
            to: parentScope.requiredValue[keyPath: factory],
            input: input
        )
    }

    var wrappedValue: ScopedStateStorage<Scope> {
        _ = parentScope.generation
        return host.storage
    }
}

@MainActor private struct ScopeModifier<ParentScope, Input: Equatable, Scope>: ViewModifier {
    @ResolvedScope<ParentScope, Input, Scope> private var scope: ScopedStateStorage<Scope>

    init(
        factory: KeyPath<ParentScope, ConnectionFactory<Input, Scope>>,
        input: Input
    ) {
        self._scope = ResolvedScope(factory: factory, input: input)
    }

    func body(content: Content) -> some View {
        content.environment(scope)
    }
}

extension View {
    /// Connects an input-bearing scope at this SwiftUI location. The live session
    /// retains any state or container created by the factory until the location
    /// disappears.
    @MainActor func scope<ParentScope, Input: Equatable, Scope>(
        _ factory: KeyPath<ParentScope, ConnectionFactory<Input, Scope>>,
        input: Input
    ) -> some View {
        modifier(ScopeModifier(factory: factory, input: input))
    }
}

// MARK: - Scoped state keys and projections

protocol ConnectionKey {
    associatedtype Scope

    associatedtype Source: ConnectionSource where Source.Input == NoConnectionInput

    associatedtype Projection

    var keyPath: KeyPath<Scope, Source> { get }

    @MainActor func projection(for value: Binding<Source.Value>) -> Projection
}

struct ReadOnlyConnectionKey<Scope, Value>: ConnectionKey {
    typealias Source = Connection<Value>

    let keyPath: KeyPath<Scope, Connection<Value>>

    @MainActor func projection(for value: Binding<Value>) -> ReadOnlyConnectionProjection<Value> {
        ReadOnlyConnectionProjection(value: value)
    }
}

struct WritableConnectionKey<Scope, Value>: ConnectionKey {
    typealias Source = WritableConnection<Value>

    let keyPath: KeyPath<Scope, WritableConnection<Value>>

    @MainActor func projection(for value: Binding<Value>) -> Binding<Value> {
        value
    }
}

@MainActor @dynamicMemberLookup struct ReadOnlyConnectionProjection<Value> {
    fileprivate let value: Binding<Value>

    subscript<Member>(dynamicMember keyPath: KeyPath<Value, Member>) -> Member {
        value.wrappedValue[keyPath: keyPath]
    }
}

extension ReadOnlyConnectionProjection where Value: AnyObject {
    subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Member>) -> Binding<Member> {
        value[dynamicMember: keyPath]
    }
}

// MARK: - Scoped state dynamic property

@MainActor @propertyWrapper struct ScopedState<Key: ConnectionKey>: DynamicProperty {
    @Environment private var scope: ScopedStateStorage<Key.Scope>

    @State private var host = ConnectionHost<Key.Source>()

    private let key: Key

    init<Scope, Value>(
        _ keyPath: KeyPath<Scope, Connection<Value>>
    ) where Key == ReadOnlyConnectionKey<Scope, Value> {
        self.key = ReadOnlyConnectionKey(keyPath: keyPath)
        self._scope = Environment(ScopedStateStorage<Scope>.self)
    }

    init<Scope, Value>(
        _ keyPath: KeyPath<Scope, WritableConnection<Value>>
    ) where Key == WritableConnectionKey<Scope, Value> {
        self.key = WritableConnectionKey(keyPath: keyPath)
        self._scope = Environment(ScopedStateStorage<Scope>.self)
    }

    func update() {
        _ = scope.generation
        host.connectIfNeeded(
            to: scope.requiredValue[keyPath: key.keyPath],
            input: .value
        )
    }

    var wrappedValue: Key.Source.Value {
        _ = scope.generation
        return host.storage.requiredValue
    }

    var projectedValue: Key.Projection {
        _ = scope.generation
        return key.projection(for: $host.connectedValue)
    }
}

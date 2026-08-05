import Combine
import Observation
import SwiftUI

// MARK: - Connection sources and sessions

private final class ConnectedStateConnectionIdentity {}

enum ConnectedStateNoInput: Equatable {
    case value
}

/// A live connection created for one SwiftUI location.
/// Its closures retain any implementation object needed to keep the value alive.
@MainActor
struct ConnectedStateSession<Input: Equatable, Value> {
    fileprivate let currentValue: @MainActor () -> Value
    fileprivate let updates: AnyPublisher<Value, Never>
    fileprivate let setValue: (@MainActor (Value) -> Void)?
    fileprivate let updateInput: @MainActor (Input) -> Void

    init(
        currentValue: @escaping @MainActor () -> Value,
        updates: AnyPublisher<Value, Never>,
        setValue: (@MainActor (Value) -> Void)? = nil,
        updateInput: @escaping @MainActor (Input) -> Void = { _ in }
    ) {
        self.currentValue = currentValue
        self.updates = updates
        self.setValue = setValue
        self.updateInput = updateInput
    }
}

protocol ConnectedStateSourceProtocol: SendableMetatype {
    associatedtype Input: Equatable
    associatedtype Value

    var identity: ObjectIdentifier { get }

    @MainActor
    func makeSession(input: Input) -> ConnectedStateSession<Input, Value>
}

/// A read-only connection which needs no external input.
struct ConnectedStateConnection<Value>: ConnectedStateSourceProtocol {
    typealias Input = ConnectedStateNoInput

    @MainActor private let getCurrentValue: @MainActor () -> Value
    @MainActor private let updates: AnyPublisher<Value, Never>
    private let identityToken = ConnectedStateConnectionIdentity()

    @MainActor
    init(
        currentValue: @escaping @MainActor () -> Value,
        updates: AnyPublisher<Value, Never>
    ) {
        self.getCurrentValue = currentValue
        self.updates = updates
    }

    var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor
    func makeSession(
        input: ConnectedStateNoInput
    ) -> ConnectedStateSession<ConnectedStateNoInput, Value> {
        ConnectedStateSession(
            currentValue: getCurrentValue,
            updates: updates
        )
    }
}

/// A replaceable connection which needs no external input.
struct WritableConnectedStateConnection<Value>: ConnectedStateSourceProtocol {
    typealias Input = ConnectedStateNoInput

    @MainActor private let getCurrentValue: @MainActor () -> Value
    @MainActor private let updates: AnyPublisher<Value, Never>
    @MainActor private let setValue: @MainActor (Value) -> Void
    private let identityToken = ConnectedStateConnectionIdentity()

    @MainActor
    init(
        currentValue: @escaping @MainActor () -> Value,
        updates: AnyPublisher<Value, Never>,
        setValue: @escaping @MainActor (Value) -> Void
    ) {
        self.getCurrentValue = currentValue
        self.updates = updates
        self.setValue = setValue
    }

    var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor
    func makeSession(
        input: ConnectedStateNoInput
    ) -> ConnectedStateSession<ConnectedStateNoInput, Value> {
        ConnectedStateSession(
            currentValue: getCurrentValue,
            updates: updates,
            setValue: setValue
        )
    }
}

/// An input-bearing connection recipe. The session it creates owns the resulting
/// state until the SwiftUI location holding the session disappears.
struct ConnectedStateFactory<Input: Equatable, Value>:
    ConnectedStateSourceProtocol
{
    private let identityToken = ConnectedStateConnectionIdentity()
    private let connect: @MainActor (Input) -> ConnectedStateSession<Input, Value>

    @MainActor
    init(
        _ connect: @escaping @MainActor (Input) -> ConnectedStateSession<Input, Value>
    ) {
        self.connect = connect
    }

    var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor
    func makeSession(input: Input) -> ConnectedStateSession<Input, Value> {
        connect(input)
    }
}

// MARK: - Universal connection lifecycle

/// The observable endpoint used both by connected properties and as the exact
/// scope type stored in SwiftUI's environment.
@MainActor @Observable
final class ConnectionNode<Value> {
    private(set) var value: Value?
    private(set) var generation = 0

    @ObservationIgnored private var setValue: (@MainActor (Value) -> Void)?

    var requiredValue: Value {
        guard let value else {
            preconditionFailure("Connected state was read before DynamicProperty.update()")
        }
        return value
    }

    func send(_ value: Value) {
        guard let setValue else {
            preconditionFailure("Connected state was written before DynamicProperty.update()")
        }
        setValue(value)
    }

    fileprivate func use(setValue: (@MainActor (Value) -> Void)?) {
        self.setValue = setValue
    }

    fileprivate func receive(_ value: Value) {
        self.value = value
        generation &+= 1
    }
}

/// The single, fully typed lifecycle owner used for ordinary state and scopes.
/// Its source, input, session, and output types remain known after connection.
@MainActor
private final class ConnectionHost<Source: ConnectedStateSourceProtocol> {
    let node = ConnectionNode<Source.Value>()

    private var sourceIdentity: ObjectIdentifier?
    private var input: Source.Input?
    private var session: ConnectedStateSession<Source.Input, Source.Value>?
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
        node.use(setValue: session.setValue)
        node.receive(session.currentValue())

        subscription = session.updates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard self?.sourceIdentity == sourceIdentity else {
                    return
                }
                self?.node.receive(value)
            }
    }

    private func updateInputIfNeeded(_ input: Source.Input) {
        guard self.input != input, let session else {
            return
        }

        self.input = input
        session.updateInput(input)
        node.receive(session.currentValue())
    }
}

// MARK: - Typed scope injection

@MainActor @propertyWrapper
private struct ResolvedConnection<Source: ConnectedStateSourceProtocol>: DynamicProperty {
    @State private var host = ConnectionHost<Source>()

    private let source: Source
    private let input: Source.Input

    init(source: Source, input: Source.Input) {
        self.source = source
        self.input = input
    }

    mutating func update() {
        host.connectIfNeeded(to: source, input: input)
    }

    var wrappedValue: ConnectionNode<Source.Value> {
        host.node
    }
}

/// The modifier is generic over the concrete scope type, never the container
/// implementation which produced its connection.
@MainActor
private struct ConnectedStateScopeModifier<Scope>: ViewModifier {
    @ResolvedConnection<ConnectedStateConnection<Scope>>
    private var scope: ConnectionNode<Scope>

    init(_ connection: ConnectedStateConnection<Scope>) {
        self._scope = ResolvedConnection(
            source: connection,
            input: .value
        )
    }

    func body(content: Content) -> some View {
        content.environment(scope)
    }
}

extension View {
    /// Injects one statically known scope. The concrete object producing the scope
    /// is hidden behind `ConnectedStateConnection<Scope>`.
    @MainActor
    func inject<Scope>(
        _ scope: ConnectedStateConnection<Scope>
    ) -> some View {
        modifier(ConnectedStateScopeModifier(scope))
    }
}

// MARK: - Connected child scopes

@MainActor @propertyWrapper
private struct ResolvedConnectedScope<
    ParentScope,
    Input: Equatable,
    Scope
>: DynamicProperty {
    @Environment private var parentScope: ConnectionNode<ParentScope>
    @State private var host = ConnectionHost<ConnectedStateFactory<Input, Scope>>()

    private let factory: KeyPath<
        ParentScope,
        ConnectedStateFactory<Input, Scope>
    >
    private let input: Input

    init(
        factory: KeyPath<ParentScope, ConnectedStateFactory<Input, Scope>>,
        input: Input
    ) {
        self.factory = factory
        self.input = input
        self._parentScope = Environment(ConnectionNode<ParentScope>.self)
    }

    mutating func update() {
        _ = parentScope.generation
        host.connectIfNeeded(
            to: parentScope.requiredValue[keyPath: factory],
            input: input
        )
    }

    var wrappedValue: ConnectionNode<Scope> {
        _ = parentScope.generation
        return host.node
    }
}

@MainActor
private struct ConnectedScopeModifier<
    ParentScope,
    Input: Equatable,
    Scope
>: ViewModifier {
    @ResolvedConnectedScope<ParentScope, Input, Scope>
    private var scope: ConnectionNode<Scope>

    init(
        factory: KeyPath<ParentScope, ConnectedStateFactory<Input, Scope>>,
        input: Input
    ) {
        self._scope = ResolvedConnectedScope(factory: factory, input: input)
    }

    func body(content: Content) -> some View {
        content.environment(scope)
    }
}

extension View {
    /// Connects an input-bearing scope at this SwiftUI location. The live session
    /// retains any state or container created by the factory until the location
    /// disappears.
    @MainActor
    func scope<
        ParentScope,
        Input: Equatable,
        Scope
    >(
        _ factory: KeyPath<ParentScope, ConnectedStateFactory<Input, Scope>>,
        input: Input
    ) -> some View {
        modifier(ConnectedScopeModifier(factory: factory, input: input))
    }
}

// MARK: - Connected state keys and projections

protocol ConnectedStateKeyProtocol {
    associatedtype Scope
    associatedtype Connection: ConnectedStateSourceProtocol
        where Connection.Input == ConnectedStateNoInput
    associatedtype Projection

    var keyPath: KeyPath<Scope, Connection> { get }

    @MainActor
    func projection(for node: ConnectionNode<Connection.Value>) -> Projection
}

struct ReadOnlyConnectedStateKey<Scope, Value>:
    ConnectedStateKeyProtocol
{
    typealias Connection = ConnectedStateConnection<Value>

    let keyPath: KeyPath<Scope, ConnectedStateConnection<Value>>

    @MainActor
    func projection(
        for node: ConnectionNode<Value>
    ) -> ReadOnlyConnectedStateProjection<Value> {
        ReadOnlyConnectedStateProjection {
            node.requiredValue
        }
    }
}

struct WritableConnectedStateKey<Scope, Value>:
    ConnectedStateKeyProtocol
{
    typealias Connection = WritableConnectedStateConnection<Value>

    let keyPath: KeyPath<Scope, WritableConnectedStateConnection<Value>>

    @MainActor
    func projection(for node: ConnectionNode<Value>) -> Binding<Value> {
        Binding(
            get: { node.requiredValue },
            set: { node.send($0) }
        )
    }
}

@MainActor @dynamicMemberLookup
struct ReadOnlyConnectedStateProjection<Value> {
    private let getValue: @MainActor () -> Value

    fileprivate init(getValue: @escaping @MainActor () -> Value) {
        self.getValue = getValue
    }

    subscript<Member>(
        dynamicMember keyPath: KeyPath<Value, Member>
    ) -> Member {
        getValue()[keyPath: keyPath]
    }
}

extension ReadOnlyConnectedStateProjection where Value: AnyObject {
    subscript<Member>(
        dynamicMember keyPath: ReferenceWritableKeyPath<Value, Member>
    ) -> Binding<Member> {
        Binding(
            get: {
                getValue()[keyPath: keyPath]
            },
            set: { newValue in
                let value = getValue()
                value[keyPath: keyPath] = newValue
            }
        )
    }
}

// MARK: - Connected state dynamic property

@MainActor @propertyWrapper
struct ConnectedState<Key: ConnectedStateKeyProtocol>: DynamicProperty {
    @Environment private var scope: ConnectionNode<Key.Scope>
    @State private var host = ConnectionHost<Key.Connection>()

    private let key: Key

    init<Scope, Value>(
        _ keyPath: KeyPath<Scope, ConnectedStateConnection<Value>>
    ) where Key == ReadOnlyConnectedStateKey<Scope, Value> {
        self.key = ReadOnlyConnectedStateKey(keyPath: keyPath)
        self._scope = Environment(ConnectionNode<Scope>.self)
    }

    init<Scope, Value>(
        _ keyPath: KeyPath<Scope, WritableConnectedStateConnection<Value>>
    ) where Key == WritableConnectedStateKey<Scope, Value> {
        self.key = WritableConnectedStateKey(keyPath: keyPath)
        self._scope = Environment(ConnectionNode<Scope>.self)
    }

    mutating func update() {
        _ = scope.generation
        host.connectIfNeeded(
            to: scope.requiredValue[keyPath: key.keyPath],
            input: .value
        )
    }

    var wrappedValue: Key.Connection.Value {
        _ = scope.generation
        return host.node.requiredValue
    }

    var projectedValue: Key.Projection {
        _ = scope.generation
        return key.projection(for: host.node)
    }
}

import Combine
import Observation
import SwiftUI

// MARK: - Typed scope connections

nonisolated protocol ConnectedStateScope {}

private nonisolated final class ConnectedStateConnectionIdentity {}

nonisolated protocol ConnectedStateConnectionProtocol {
    associatedtype Value

    nonisolated var identity: ObjectIdentifier { get }
    @MainActor var currentValue: Value { get }
    @MainActor var updates: AnyPublisher<Value, Never> { get }
}

nonisolated protocol WritableConnectedStateConnectionProtocol:
    ConnectedStateConnectionProtocol
{
    @MainActor func set(_ value: Value)
}

nonisolated struct ConnectedStateConnection<Value>: ConnectedStateConnectionProtocol {
    @MainActor let updates: AnyPublisher<Value, Never>

    private let identityToken: ConnectedStateConnectionIdentity
    private let getCurrentValue: @MainActor () -> Value

    @MainActor init(
        currentValue: @escaping @MainActor () -> Value,
        updates: AnyPublisher<Value, Never>
    ) {
        self.identityToken = ConnectedStateConnectionIdentity()
        self.getCurrentValue = currentValue
        self.updates = updates
    }

    nonisolated var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor var currentValue: Value {
        getCurrentValue()
    }
}

nonisolated struct WritableConnectedStateConnection<Value>:
    WritableConnectedStateConnectionProtocol
{
    @MainActor let updates: AnyPublisher<Value, Never>

    private let identityToken: ConnectedStateConnectionIdentity
    private let getCurrentValue: @MainActor () -> Value
    private let setValue: @MainActor (Value) -> Void

    @MainActor init(
        currentValue: @escaping @MainActor () -> Value,
        updates: AnyPublisher<Value, Never>,
        setValue: @escaping @MainActor (Value) -> Void
    ) {
        self.identityToken = ConnectedStateConnectionIdentity()
        self.getCurrentValue = currentValue
        self.updates = updates
        self.setValue = setValue
    }

    nonisolated var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    @MainActor var currentValue: Value {
        getCurrentValue()
    }

    @MainActor func set(_ value: Value) {
        setValue(value)
    }
}

// MARK: - SwiftUI scope injection

@MainActor @Observable
final class InjectedConnectedStateScope<Scope: ConnectedStateScope> {
    @ObservationIgnored private(set) var value: Scope
    @ObservationIgnored private var ownerIdentity: ObjectIdentifier?

    private(set) var generation = 0

    init<Owner: AnyObject>(
        owner: Owner,
        scope keyPath: KeyPath<Owner, Scope>
    ) {
        self.value = owner[keyPath: keyPath]
        self.ownerIdentity = ObjectIdentifier(owner)
    }

    init(value: Scope) {
        self.value = value
        self.ownerIdentity = nil
    }

    func use<Owner: AnyObject>(
        _ owner: Owner,
        scope keyPath: KeyPath<Owner, Scope>
    ) {
        use(owner[keyPath: keyPath], ownerIdentity: ObjectIdentifier(owner))
    }

    func use(_ value: Scope, ownerIdentity: ObjectIdentifier) {
        guard self.ownerIdentity != ownerIdentity else {
            return
        }

        self.value = value
        self.ownerIdentity = ownerIdentity
        generation &+= 1
    }
}

@MainActor @propertyWrapper
private struct ScopeInjection<Owner: AnyObject, Scope: ConnectedStateScope>: DynamicProperty {
    @State private var injectedScope: InjectedConnectedStateScope<Scope>

    private let owner: Owner
    private let keyPath: KeyPath<Owner, Scope>

    init(
        owner: Owner,
        scope keyPath: KeyPath<Owner, Scope>
    ) {
        self.owner = owner
        self.keyPath = keyPath
        self._injectedScope = State(
            initialValue: InjectedConnectedStateScope(owner: owner, scope: keyPath)
        )
    }

    mutating func update() {
        injectedScope.use(owner, scope: keyPath)
    }

    var wrappedValue: InjectedConnectedStateScope<Scope> {
        injectedScope
    }
}

@MainActor
private struct ConnectedStateScopeModifier<Owner: AnyObject, Scope: ConnectedStateScope>:
    ViewModifier
{
    @ScopeInjection<Owner, Scope> private var scope: InjectedConnectedStateScope<Scope>

    init(
        owner: Owner,
        scope keyPath: KeyPath<Owner, Scope>
    ) {
        self._scope = ScopeInjection(owner: owner, scope: keyPath)
    }

    func body(content: Content) -> some View {
        content.environment(scope)
    }
}

extension View {
    @MainActor
    func inject<Owner: AnyObject, Scope: ConnectedStateScope>(
        _ owner: Owner,
        _ scope: KeyPath<Owner, Scope>
    ) -> some View {
        modifier(ConnectedStateScopeModifier(owner: owner, scope: scope))
    }
}

// MARK: - Declarative container bodies

@MainActor @Observable
private final class ConnectedStateContainerContext {
    private(set) var ownerIdentity: ObjectIdentifier

    init<Owner: AnyObject>(owner: Owner) {
        self.ownerIdentity = ObjectIdentifier(owner)
    }

    func use<Owner: AnyObject>(_ owner: Owner) {
        let identity = ObjectIdentifier(owner)
        guard identity != ownerIdentity else {
            return
        }

        ownerIdentity = identity
    }
}

@MainActor @propertyWrapper
private struct ContainerContext<Owner: AnyObject>: DynamicProperty {
    @State private var context: ConnectedStateContainerContext

    private let owner: Owner

    init(owner: Owner) {
        self.owner = owner
        self._context = State(
            initialValue: ConnectedStateContainerContext(owner: owner)
        )
    }

    mutating func update() {
        context.use(owner)
    }

    var wrappedValue: ConnectedStateContainerContext {
        context
    }
}

@MainActor @propertyWrapper
private struct ContainerProvidedScope<Scope: ConnectedStateScope>: DynamicProperty {
    @Environment private var context: ConnectedStateContainerContext
    @State private var injectedScope: InjectedConnectedStateScope<Scope>

    private let value: Scope

    init(value: Scope) {
        self.value = value
        self._context = Environment(ConnectedStateContainerContext.self)
        self._injectedScope = State(
            initialValue: InjectedConnectedStateScope(value: value)
        )
    }

    mutating func update() {
        injectedScope.use(value, ownerIdentity: context.ownerIdentity)
    }

    var wrappedValue: InjectedConnectedStateScope<Scope> {
        injectedScope
    }
}

@MainActor
private struct ConnectedStateScopeProvision<Scope: ConnectedStateScope>: ViewModifier {
    @ContainerProvidedScope<Scope>
    private var scope: InjectedConnectedStateScope<Scope>

    init(_ scope: Scope) {
        self._scope = ContainerProvidedScope(value: scope)
    }

    func body(content: Content) -> some View {
        content.environment(scope)
    }
}

@MainActor
fileprivate struct AnyConnectedStateScopeDefinition {
    private let install: @MainActor (AnyView) -> AnyView

    init<Scope: ConnectedStateScope>(_ scope: Scope) {
        self.install = { content in
            AnyView(content.modifier(ConnectedStateScopeProvision(scope)))
        }
    }

    func install(into content: AnyView) -> AnyView {
        install(content)
    }
}

/// An ordered installation plan for the scopes provided by one container.
/// Keep the scope types and their order stable while the container instance lives.
@MainActor
struct ConnectedStateContainerDefinition {
    fileprivate let scopes: [AnyConnectedStateScopeDefinition]

    fileprivate init(scopes: [AnyConnectedStateScopeDefinition]) {
        self.scopes = scopes
    }

    fileprivate func install(into content: AnyView) -> AnyView {
        scopes.reduce(content) { content, scope in
            scope.install(into: content)
        }
    }

}

@resultBuilder
enum ConnectedStateContainerBuilder {
    @MainActor
    static func buildExpression<Scope: ConnectedStateScope>(
        _ scope: Scope
    ) -> ConnectedStateContainerDefinition {
        ConnectedStateContainerDefinition(
            scopes: [AnyConnectedStateScopeDefinition(scope)]
        )
    }

    @MainActor
    static func buildBlock(
        _ components: ConnectedStateContainerDefinition...
    ) -> ConnectedStateContainerDefinition {
        ConnectedStateContainerDefinition(
            scopes: components.flatMap(\.scopes)
        )
    }
}

/// A reference-type container that declaratively provides one or more concrete scopes.
@MainActor
protocol ConnectedStateContainer: AnyObject {
    @ConnectedStateContainerBuilder
    var body: ConnectedStateContainerDefinition { get }
}

@MainActor
private struct ConnectedStateContainerDefinitionModifier<Owner: AnyObject>: ViewModifier {
    @ContainerContext<Owner>
    private var context: ConnectedStateContainerContext

    private let definition: ConnectedStateContainerDefinition

    init(owner: Owner, definition: ConnectedStateContainerDefinition) {
        self._context = ContainerContext(owner: owner)
        self.definition = definition
    }

    func body(content: Content) -> some View {
        definition
            .install(into: AnyView(content))
            .environment(context)
    }
}

extension View {
    /// Installs every scope declared by `container.body` into this subtree.
    @MainActor
    func inject<Container: ConnectedStateContainer>(
        _ container: Container
    ) -> some View {
        modifier(
            ConnectedStateContainerDefinitionModifier(
                owner: container,
                definition: container.body
            )
        )
    }
}

// MARK: - SwiftUI-owned child containers

private nonisolated final class ConnectedStateContainerFactoryIdentity {}

/// A container whose lifetime is owned by a SwiftUI scope location.
@MainActor
protocol InputConnectedStateContainer<Input>: ConnectedStateContainer {
    associatedtype Input: Equatable

    @MainActor func update(input: Input)
}

@MainActor
private final class ScopedContainerInstance<Input> {
    let definition: ConnectedStateContainerDefinition

    private let updateInput: @MainActor (Input) -> Void

    init(
        definition: ConnectedStateContainerDefinition,
        updateInput: @escaping @MainActor (Input) -> Void
    ) {
        self.definition = definition
        self.updateInput = updateInput
    }

    func update(input: Input) {
        updateInput(input)
    }
}

/// An input-typed child-container recipe exposed by a parent scope.
/// The parent owns this recipe, while SwiftUI owns every container created from it.
@MainActor
struct ConnectedStateContainerFactory<Input: Equatable> {
    private let identityToken = ConnectedStateContainerFactoryIdentity()
    private let makeInstance: @MainActor (Input) -> ScopedContainerInstance<Input>

    init<Container: InputConnectedStateContainer>(
        _ makeContainer: @escaping @MainActor (Input) -> Container
    ) where Container.Input == Input {
        self.makeInstance = { input in
            let container = makeContainer(input)
            return ScopedContainerInstance<Input>(
                definition: container.body,
                updateInput: { input in
                    container.update(input: input)
                }
            )
        }
    }

    var identity: ObjectIdentifier {
        ObjectIdentifier(identityToken)
    }

    fileprivate func make(input: Input) -> ScopedContainerInstance<Input> {
        makeInstance(input)
    }
}

@MainActor
private final class ScopedContainerStorage<Input> {
    private var factoryIdentity: ObjectIdentifier?
    private var input: Input?
    private var instance: ScopedContainerInstance<Input>?

    func use(
        _ factory: ConnectedStateContainerFactory<Input>,
        input: Input
    ) where Input: Equatable {
        guard factoryIdentity == factory.identity else {
            instance = factory.make(input: input)
            self.factoryIdentity = factory.identity
            self.input = input
            return
        }

        guard self.input != input else {
            return
        }

        instance?.update(input: input)
        self.input = input
    }

    var resolvedInstance: ScopedContainerInstance<Input> {
        guard let instance else {
            preconditionFailure("A scoped container was accessed before DynamicProperty.update()")
        }

        return instance
    }
}

@MainActor
@propertyWrapper
private struct ResolvedScopedContainer<
    ParentScope: ConnectedStateScope,
    Input: Equatable
>: DynamicProperty {
    @Environment private var parentScope: InjectedConnectedStateScope<ParentScope>
    @State private var storage = ScopedContainerStorage<Input>()

    private let factory: KeyPath<
        ParentScope,
        ConnectedStateContainerFactory<Input>
    >
    private let input: Input

    init(
        factory: KeyPath<ParentScope, ConnectedStateContainerFactory<Input>>,
        input: Input
    ) {
        self.factory = factory
        self.input = input
        self._parentScope = Environment(InjectedConnectedStateScope<ParentScope>.self)
    }

    mutating func update() {
        storage.use(parentScope.value[keyPath: factory], input: input)
    }

    var wrappedValue: ScopedContainerInstance<Input> {
        storage.resolvedInstance
    }
}

@MainActor
private struct ScopedContainerModifier<
    ParentScope: ConnectedStateScope,
    Input: Equatable
>: ViewModifier {
    @ResolvedScopedContainer<ParentScope, Input>
    private var container: ScopedContainerInstance<Input>

    init(
        factory: KeyPath<ParentScope, ConnectedStateContainerFactory<Input>>,
        input: Input
    ) {
        self._container = ResolvedScopedContainer(factory: factory, input: input)
    }

    func body(content: Content) -> some View {
        content.modifier(
            ConnectedStateContainerDefinitionModifier(
                owner: container,
                definition: container.definition
            )
        )
    }
}

extension View {
    /// Creates one child container for this SwiftUI location, updates it when `input`
    /// changes, and releases it when the location leaves the view tree.
    @MainActor
    func scope<
        ParentScope: ConnectedStateScope,
        Input: Equatable
    >(
        _ factory: KeyPath<ParentScope, ConnectedStateContainerFactory<Input>>,
        input: Input
    ) -> some View {
        modifier(ScopedContainerModifier(factory: factory, input: input))
    }
}

// MARK: - Connected state key paths

nonisolated protocol ConnectedStateKeyProtocol {
    associatedtype Scope: ConnectedStateScope
    associatedtype Connection: ConnectedStateConnectionProtocol
    associatedtype Projection

    var keyPath: KeyPath<Scope, Connection> { get }

    @MainActor func setValue(
        for connection: Connection
    ) -> (@MainActor (Connection.Value) -> Void)?

    @MainActor func projection(
        for node: ConnectionNode<Connection.Value>
    ) -> Projection
}

nonisolated struct ReadOnlyConnectedStateKey<Scope: ConnectedStateScope, Value>:
    ConnectedStateKeyProtocol
{
    typealias Connection = ConnectedStateConnection<Value>

    let keyPath: KeyPath<Scope, ConnectedStateConnection<Value>>

    @MainActor func setValue(
        for connection: Connection
    ) -> (@MainActor (Value) -> Void)? {
        nil
    }

    @MainActor func projection(
        for node: ConnectionNode<Value>
    ) -> ReadOnlyConnectedStateProjection<Value> {
        ReadOnlyConnectedStateProjection {
            node.requiredValue
        }
    }
}

nonisolated struct WritableConnectedStateKey<Scope: ConnectedStateScope, Value>:
    ConnectedStateKeyProtocol
{
    typealias Connection = WritableConnectedStateConnection<Value>

    let keyPath: KeyPath<Scope, WritableConnectedStateConnection<Value>>

    @MainActor func setValue(
        for connection: Connection
    ) -> (@MainActor (Value) -> Void)? {
        { connection.set($0) }
    }

    @MainActor func projection(for node: ConnectionNode<Value>) -> Binding<Value> {
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

@MainActor @Observable
final class ConnectionNode<Value> {
    private(set) var value: Value?

    @ObservationIgnored private var scopeIdentity: ObjectIdentifier?
    @ObservationIgnored private var scopeGeneration: Int?
    @ObservationIgnored private var connectionIdentity: ObjectIdentifier?
    @ObservationIgnored private var setValue: (@MainActor (Value) -> Void)?
    @ObservationIgnored private var subscription: AnyCancellable?

    func connectIfNeeded<Key: ConnectedStateKeyProtocol>(
        to scope: InjectedConnectedStateScope<Key.Scope>,
        using key: Key
    ) where Key.Connection.Value == Value {
        let scopeIdentity = ObjectIdentifier(scope)
        let scopeGeneration = scope.generation
        let connection = scope.value[keyPath: key.keyPath]
        let connectionIdentity = connection.identity
        guard
            self.scopeIdentity != scopeIdentity
                || self.scopeGeneration != scopeGeneration
                || self.connectionIdentity != connectionIdentity
        else {
            return
        }

        subscription?.cancel()

        self.scopeIdentity = scopeIdentity
        self.scopeGeneration = scopeGeneration
        self.connectionIdentity = connectionIdentity
        self.setValue = key.setValue(for: connection)
        self.value = connection.currentValue
        self.subscription = connection.updates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard
                    self?.scopeIdentity == scopeIdentity,
                    self?.scopeGeneration == scopeGeneration,
                    self?.connectionIdentity == connectionIdentity
                else {
                    return
                }

                self?.value = value
            }
    }

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
}

@MainActor @propertyWrapper
struct ConnectedState<Key: ConnectedStateKeyProtocol>: DynamicProperty {
    @Environment private var scope: InjectedConnectedStateScope<Key.Scope>
    @State private var node = ConnectionNode<Key.Connection.Value>()

    private let key: Key

    init<Scope: ConnectedStateScope, Value>(
        _ keyPath: KeyPath<Scope, ConnectedStateConnection<Value>>
    ) where Key == ReadOnlyConnectedStateKey<Scope, Value> {
        self.key = ReadOnlyConnectedStateKey(keyPath: keyPath)
        self._scope = Environment(InjectedConnectedStateScope<Scope>.self)
    }

    init<Scope: ConnectedStateScope, Value>(
        _ keyPath: KeyPath<Scope, WritableConnectedStateConnection<Value>>
    ) where Key == WritableConnectedStateKey<Scope, Value> {
        self.key = WritableConnectedStateKey(keyPath: keyPath)
        self._scope = Environment(InjectedConnectedStateScope<Scope>.self)
    }

    mutating func update() {
        node.connectIfNeeded(to: scope, using: key)
    }

    var wrappedValue: Key.Connection.Value {
        node.requiredValue
    }

    var projectedValue: Key.Projection {
        key.projection(for: node)
    }
}

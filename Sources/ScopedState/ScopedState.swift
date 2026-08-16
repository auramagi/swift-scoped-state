//
//  ScopedState.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

/// A SwiftUI property wrapper for state connected through an environment scope.
///
/// Select a connection with a static key path. The wrapper establishes the
/// connection as part of SwiftUI's state lifecycle and exposes its current
/// value to the view.
///
/// ```swift
/// @MainActor struct SettingsScope {
///     let isEnabled: WritableConnection<Bool>
/// }
///
/// struct SettingsView: View {
///     @ScopedState(\SettingsScope.isEnabled) private var isEnabled
///
///     var body: some View {
///         Toggle("Enabled", isOn: $isEnabled)
///     }
/// }
/// ```
///
/// Provide the scope above the consuming view with
/// ``SwiftUICore/View/container(_:scope:)`` or derive it from a parent scope
/// with ``SwiftUICore/View/scope(_:)``.
@MainActor @propertyWrapper public struct ScopedState<Scope, Configuration: Equatable, Value, Projection: ValueProjection>: @MainActor DynamicProperty where Value == Projection.Value {
    typealias Session = ConnectionSession<Configuration, Value>

    typealias Source = Coordinator.Source

    @MainActor struct ValueBehavior {
        let areEquivalent: (_ lhs: Value, _ rhs: Value) -> Bool

        let makeObservation: ((_ value: Value, _ invalidate: @escaping @MainActor () -> Void) -> CancellationToken)?
    }

    @MainActor final class Coordinator {
        nonisolated init(storage: ScopedStateStorage<Value>) {
            self.storage = storage
        }

        @MainActor struct Source {
            let keyPath: AnyKeyPath

            let makeSession: (Scope, Configuration) -> Session
        }

        @MainActor struct Context {
            struct ConnectionIdentity: Equatable {
                let scopeStorage: ScopedStateStorage<Scope>

                let generation: UInt

                let keyPath: AnyKeyPath

                static func == (lhs: ConnectionIdentity, rhs: ConnectionIdentity) -> Bool {
                    lhs.scopeStorage === rhs.scopeStorage
                    && lhs.generation == rhs.generation
                    && lhs.keyPath == rhs.keyPath
                }
            }

            let identity: ConnectionIdentity

            let valueBehavior: ValueBehavior

            let session: Session

            var sessionObservation: CancellationToken?

            var valueObservation: CancellationToken?

            var configuration: Configuration
        }

        let storage: ScopedStateStorage<Value>

        private var context: Context?

        var value: Value {
            get {
                storage.requiredValue
            }
            set {
                guard let context else {
                    preconditionFailure("Scoped state was written before DynamicProperty.update()")
                }

                // SwiftUI derived bindings reassign their root even after a
                // nonmutating member write. Only a writable projection should
                // forward that replacement to the connected implementation.
                if Projection.forwardsRootReplacement {
                    guard let setValue = context.session.setValue else {
                        preconditionFailure("A writable scoped state requires a writable connection")
                    }

                    setValue(newValue)
                } else {
                    applyValue(newValue, notifyingObservers: true, valueBehavior: context.valueBehavior)
                }
            }
        }

        private func makeYield(valueBehavior: ValueBehavior) -> Session.Yield {
            { [weak self] update in
                guard let self else { return }

                switch update {
                case let .value(value):
                    applyValue(value, notifyingObservers: true, valueBehavior: valueBehavior)

                case .invalidate:
                    storage.invalidate()
                }
            }
        }

        private func applyValue(
            _ value: Value,
            notifyingObservers: Bool,
            valueBehavior: ValueBehavior
        ) {
            let valueChanged = !storage.valueEquals(value, by: valueBehavior.areEquivalent)

            if valueChanged {
                storage.setValue(value, notifyingObservers: notifyingObservers)
            }

            guard let makeObservation = valueBehavior.makeObservation, valueChanged || context?.valueObservation == nil else {
                return
            }

            context?.valueObservation?.cancel()
            context?.valueObservation = makeObservation(value) { [storage] in
                storage.invalidate()
            }
        }

        func update(
            scopeStorage: ScopedStateStorage<Scope>,
            source: Source,
            configuration: Configuration,
            valueBehavior: ValueBehavior
        ) {
            let identity = Context.ConnectionIdentity(
                scopeStorage: scopeStorage,
                generation: scopeStorage.generation,
                keyPath: source.keyPath
            )

            if context?.identity != identity {
                let session = source.makeSession(scopeStorage.requiredValue, configuration)

                context?.sessionObservation?.cancel()
                let activation = session.activate(
                    makeYield(valueBehavior: valueBehavior)
                )
                context = Context(
                    identity: identity,
                    valueBehavior: valueBehavior,
                    session: session,
                    sessionObservation: activation.observation,
                    valueObservation: nil,
                    configuration: configuration
                )
                applyValue(activation.initialValue, notifyingObservers: false, valueBehavior: valueBehavior)
            } else if let context, context.configuration != configuration {
                context.sessionObservation?.cancel()
                context.session.reconfigure(configuration)
                let activation = context.session.activate(
                    makeYield(valueBehavior: context.valueBehavior)
                )
                self.context?.sessionObservation = activation.observation
                self.context?.configuration = configuration
                applyValue(activation.initialValue, notifyingObservers: false, valueBehavior: valueBehavior)
            } else if let context, let value = context.session.refresh() {
                applyValue(value, notifyingObservers: false, valueBehavior: context.valueBehavior)
            }
        }
    }

    @State private var coordinator = Coordinator(storage: ScopedStateStorage())

    @Environment(ScopedStateStorage<Scope>.self) private var scope

    private let source: Source

    private let configuration: Configuration

    private let valueBehavior: ValueBehavior

    init(
        keyPath: AnyKeyPath,
        configuration: Configuration,
        valueBehavior: ValueBehavior,
        makeSession: @escaping (Scope, Configuration) -> Session
    ) {
        self.source = Source(keyPath: keyPath, makeSession: makeSession)
        self.configuration = configuration
        self.valueBehavior = valueBehavior
    }

    init(
        _ keyPath: KeyPath<Scope, WritableConfiguredConnection<Value, Configuration>>,
        configuration: Configuration,
        valueBehavior: ValueBehavior
    ) {
        self.init(
            keyPath: keyPath,
            configuration: configuration,
            valueBehavior: valueBehavior,
            makeSession: { $0[keyPath: keyPath].makeSession($1) }
        )
    }

    init(
        _ keyPath: KeyPath<Scope, ConfiguredConnection<Value, Configuration>>,
        configuration: Configuration,
        valueBehavior: ValueBehavior
    ) {
        self.init(
            keyPath: keyPath,
            configuration: configuration,
            valueBehavior: valueBehavior,
            makeSession: { $0[keyPath: keyPath].makeSession($1) }
        )
    }

    /// Creates writable scoped state from a configured writable connection.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the connection in its scope.
    ///   - configuration: The configuration used to establish the connection.
    public init(
        _ keyPath: KeyPath<Scope, WritableConfiguredConnection<Value, Configuration>>,
        configuration: Configuration
    ) where Projection == ReadWriteValueProjection<Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .default)
    }

    /// Creates writable scoped state from a configured writable connection,
    /// coalescing equivalent values.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the connection in its scope.
    ///   - configuration: The configuration used to establish the connection.
    public init(
        _ keyPath: KeyPath<Scope, WritableConfiguredConnection<Value, Configuration>>,
        configuration: Configuration
    ) where Projection == ReadWriteValueProjection<Value>, Value: Equatable {
        self.init(keyPath, configuration: configuration, valueBehavior: .equatable)
    }

    /// Creates writable scoped state from an unconfigured writable connection.
    ///
    /// - Parameter keyPath: The key path to the connection in its scope.
    public init(
        _ keyPath: KeyPath<Scope, WritableConnection<Value>>
    ) where Configuration == EmptyConfiguration, Projection == ReadWriteValueProjection<Value> {
        self.init(keyPath, configuration: .init())
    }

    /// Creates writable scoped state from an unconfigured writable connection,
    /// coalescing equivalent values.
    ///
    /// - Parameter keyPath: The key path to the connection in its scope.
    public init(
        _ keyPath: KeyPath<Scope, WritableConnection<Value>>
    ) where Configuration == EmptyConfiguration, Projection == ReadWriteValueProjection<Value>, Value: Equatable {
        self.init(keyPath, configuration: .init())
    }

    /// Creates read-only scoped state from a configured connection.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the connection in its scope.
    ///   - configuration: The configuration used to establish the connection.
    public init(
        _ keyPath: KeyPath<Scope, ConfiguredConnection<Value, Configuration>>,
        configuration: Configuration
    ) where Projection == ReadOnlyValueProjection<Value> {
        self.init(keyPath, configuration: configuration, valueBehavior: .default)
    }

    /// Creates read-only scoped state from a configured connection, coalescing
    /// equivalent values.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the connection in its scope.
    ///   - configuration: The configuration used to establish the connection.
    public init(
        _ keyPath: KeyPath<Scope, ConfiguredConnection<Value, Configuration>>,
        configuration: Configuration
    ) where Projection == ReadOnlyValueProjection<Value>, Value: Equatable {
        self.init(keyPath, configuration: configuration, valueBehavior: .equatable)
    }

    /// Creates read-only scoped state from an unconfigured connection.
    ///
    /// - Parameter keyPath: The key path to the connection in its scope.
    public init(
        _ keyPath: KeyPath<Scope, Connection<Value>>
    ) where Configuration == EmptyConfiguration, Projection == ReadOnlyValueProjection<Value> {
        self.init(keyPath, configuration: .init())
    }

    /// Creates read-only scoped state from an unconfigured connection,
    /// coalescing equivalent values.
    ///
    /// - Parameter keyPath: The key path to the connection in its scope.
    public init(
        _ keyPath: KeyPath<Scope, Connection<Value>>
    ) where Configuration == EmptyConfiguration, Projection == ReadOnlyValueProjection<Value>, Value: Equatable {
        self.init(keyPath, configuration: .init())
    }

    /// Updates the active connection from the current SwiftUI environment.
    ///
    /// SwiftUI calls this method before evaluating a view's body. Don't call it
    /// directly.
    public func update() {
        coordinator.update(
            scopeStorage: scope,
            source: source,
            configuration: configuration,
            valueBehavior: valueBehavior
        )
    }

    var storage: ScopedStateStorage<Value> {
        coordinator.storage
    }

    /// The current value delivered by the connection.
    public var wrappedValue: Value {
        coordinator.storage.requiredValue
    }

    /// The projection associated with the connection's read/write capability.
    ///
    /// Writable connections expose a `Binding<Value>`. Read-only object
    /// connections expose ``ScopedStateProjection`` for bindings to writable
    /// members without allowing replacement of the root object.
    public var projectedValue: Projection.ProjectedValue {
        Projection.transformProjection(
            ScopedStateProjection(base: $coordinator.value)
        )
    }
}

private extension ScopedState.ValueBehavior {
    static var `default`: Self {
        Self(
            areEquivalent: { _, _ in false },
            makeObservation: nil
        )
    }
}

private extension ScopedState.ValueBehavior where Value: Equatable {
    static var equatable: Self {
        Self(
            areEquivalent: { $0 == $1 },
            makeObservation: nil
        )
    }
}

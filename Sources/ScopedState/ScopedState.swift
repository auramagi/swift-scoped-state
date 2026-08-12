//
//  ScopedState.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

@MainActor @propertyWrapper public struct ScopedState<Scope, Configuration, Connected: ConnectedValue>: @MainActor DynamicProperty {
    private typealias Connection = GenericConnection<Configuration, Connected>

    @MainActor struct ValueBehavior {
        let areEquivalent: (_ lhs: Connected.WrappedValue, _ rhs: Connected.WrappedValue) -> Bool

        let makeObservation: ((_ value: Connected.WrappedValue, _ invalidate: @escaping @MainActor () -> Void) -> CancellationToken)?
    }

    @MainActor private final class Coordinator {
        @MainActor struct Context {
            struct ConnectionIdentity: Equatable {
                let scopeStorage: ScopedStateStorage<Scope>

                let generation: UInt

                let keyPath: KeyPath<Scope, Connection>

                static func == (lhs: ConnectionIdentity, rhs: ConnectionIdentity) -> Bool {
                    lhs.scopeStorage === rhs.scopeStorage
                    && lhs.generation == rhs.generation
                    && lhs.keyPath == rhs.keyPath
                }
            }

            let identity: ConnectionIdentity

            let connection: Connection

            let valueBehavior: ValueBehavior

            let session: Connection.Session

            var sessionObservation: CancellationToken?

            var valueObservation: CancellationToken?

            var configuration: Configuration
        }

        let storage = ScopedStateStorage<Connected.WrappedValue>()

        private var context: Context?

        var value: Connected.WrappedValue {
            get {
                storage.requiredValue
            }
            set {
                guard let context else {
                    preconditionFailure("Scoped state was written before DynamicProperty.update()")
                }

                if let setValue = context.session.setValue {
                    setValue(newValue)
                } else {
                    applyValue(newValue, notifyingObservers: true, valueBehavior: context.valueBehavior)
                }
            }
        }

        private func makeYield(valueBehavior: ValueBehavior) -> Connection.Session.Yield {
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
            _ value: Connected.WrappedValue,
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
            keyPath: KeyPath<Scope, Connection>,
            configuration: Configuration,
            valueBehavior: ValueBehavior
        ) {
            let identity = Context.ConnectionIdentity(
                scopeStorage: scopeStorage,
                generation: scopeStorage.generation,
                keyPath: keyPath
            )

            if context?.identity != identity {
                let connection = identity.scopeStorage.requiredValue[keyPath: identity.keyPath]
                let session = connection.makeSession(configuration)

                context?.sessionObservation?.cancel()
                let activation = session.activate(
                    makeYield(valueBehavior: valueBehavior)
                )
                context = Context(
                    identity: identity,
                    connection: connection,
                    valueBehavior: valueBehavior,
                    session: session,
                    sessionObservation: activation.observation,
                    valueObservation: nil,
                    configuration: configuration
                )
                applyValue(activation.initialValue, notifyingObservers: false, valueBehavior: valueBehavior)
            } else if let context, !context.connection.configurationsEqual(context.configuration, configuration) {
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

    @State private var coordinator = Coordinator()

    @Environment(ScopedStateStorage<Scope>.self) private var scope

    private let keyPath: KeyPath<Scope, Connection>

    private let configuration: Configuration

    private let valueBehavior: ValueBehavior

    init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>,
        configuration: Configuration,
        valueBehavior: ValueBehavior
    ) {
        self.keyPath = keyPath
        self.configuration = configuration
        self.valueBehavior = valueBehavior
    }

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>,
        configuration: Configuration
    ) {
        self.init(keyPath, configuration: configuration, valueBehavior: .default)
    }

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>,
        configuration: Configuration
    ) where Connected.WrappedValue: Equatable {
        self.init(keyPath, configuration: configuration, valueBehavior: .equatable)
    }

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>
    ) where Configuration == Void {
        self.init(keyPath, configuration: (), valueBehavior: .default)
    }

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>
    ) where Configuration == Void, Connected.WrappedValue: Equatable {
        self.init(keyPath, configuration: (), valueBehavior: .equatable)
    }

    public func update() {
        coordinator.update(
            scopeStorage: scope,
            keyPath: keyPath,
            configuration: configuration,
            valueBehavior: valueBehavior
        )
    }

    var storage: ScopedStateStorage<Connected.WrappedValue> {
        coordinator.storage
    }

    public var wrappedValue: Connected.WrappedValue {
        coordinator.storage.requiredValue
    }

    public var projectedValue: Connected.Projection {
        Connected.transformProjection(
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

private extension ScopedState.ValueBehavior where Connected.WrappedValue: Equatable {
    static var equatable: Self {
        Self(
            areEquivalent: { $0 == $1 },
            makeObservation: nil
        )
    }
}

@MainActor @dynamicMemberLookup public struct ScopedStateProjection<Base> {
    let base: Binding<Base>

    public subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<Base, Value>) -> Binding<Value> {
        base[dynamicMember: keyPath]
    }
}

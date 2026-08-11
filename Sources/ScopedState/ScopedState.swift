//
//  ScopedState.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

@MainActor @propertyWrapper public struct ScopedState<Scope, Configuration, Connected: ConnectedValue>: @MainActor DynamicProperty {
    private typealias Connection = GenericConnection<Configuration, Connected>

    typealias ValuesEqual = (
        Connected.WrappedValue,
        Connected.WrappedValue
    ) -> Bool

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

            let session: Connection.Session

            var cancellation: CancellationToken?

            let valuesEqual: ValuesEqual

            var configuration: Configuration
        }

        let storage = ScopedStateStorage<Connected.WrappedValue>()

        private var context: Context?

        var value: Connected.WrappedValue {
            get { storage.requiredValue }
            set {
                guard let context else {
                    preconditionFailure("Scoped state was written before DynamicProperty.update()")
                }

                if let setValue = context.session.setValue {
                    setValue(newValue)
                } else {
                    storage.setValue(
                        newValue,
                        notifyingObservers: true,
                        valuesEqual: context.valuesEqual
                    )
                }
            }
        }

        private func makeYield(valuesEqual: @escaping ValuesEqual) -> Connection.Session.Yield {
            { [storage] update in
                switch update {
                case let .value(value):
                    storage.setValue(
                        value,
                        notifyingObservers: true,
                        valuesEqual: valuesEqual
                    )
                case .invalidate:
                    storage.invalidate()
                }
            }
        }

        private func install(
            _ value: Connected.WrappedValue,
            valuesEqual: ValuesEqual
        ) {
            storage.setValue(
                value,
                notifyingObservers: false,
                valuesEqual: valuesEqual
            )
        }

        func update(
            scopeStorage: ScopedStateStorage<Scope>,
            keyPath: KeyPath<Scope, Connection>,
            configuration: Configuration,
            valuesEqual: @escaping ValuesEqual
        ) {
            let identity = Context.ConnectionIdentity(
                scopeStorage: scopeStorage,
                generation: scopeStorage.generation,
                keyPath: keyPath
            )

            if context?.identity != identity {
                let connection = identity.scopeStorage.requiredValue[keyPath: identity.keyPath]
                let session = connection.makeSession(configuration)

                context?.cancellation?.cancel()
                let activation = session.activate(
                    makeYield(valuesEqual: valuesEqual)
                )
                context = Context(
                    identity: identity,
                    connection: connection,
                    session: session,
                    cancellation: activation.cancellation,
                    valuesEqual: valuesEqual,
                    configuration: configuration
                )
                install(
                    activation.initialValue,
                    valuesEqual: valuesEqual
                )
            } else if let context, !context.connection.configurationsEqual(context.configuration, configuration) {
                context.cancellation?.cancel()
                context.session.reconfigure(configuration)
                let activation = context.session.activate(
                    makeYield(valuesEqual: context.valuesEqual)
                )
                self.context?.cancellation = activation.cancellation
                self.context?.configuration = configuration
                install(
                    activation.initialValue,
                    valuesEqual: context.valuesEqual
                )
            } else if let context, let value = context.session.refresh() {
                install(
                    value,
                    valuesEqual: context.valuesEqual
                )
            }
        }
    }

    @State private var coordinator = Coordinator()

    @Environment(ScopedStateStorage<Scope>.self) private var scope

    private let keyPath: KeyPath<Scope, Connection>

    private let configuration: Configuration

    private let valuesEqual: ValuesEqual

    init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>,
        configuration: Configuration,
        valuesEqual: @escaping ValuesEqual
    ) {
        self.keyPath = keyPath
        self.configuration = configuration
        self.valuesEqual = valuesEqual
    }

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>,
        configuration: Configuration
    ) {
        self.init(
            keyPath,
            configuration: configuration,
            valuesEqual: { _, _ in false }
        )
    }

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>,
        configuration: Configuration
    ) where Connected.WrappedValue: Equatable {
        self.init(
            keyPath,
            configuration: configuration,
            valuesEqual: { $0 == $1 }
        )
    }

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>
    ) where Configuration == Void {
        self.init(
            keyPath,
            configuration: (),
            valuesEqual: { _, _ in false }
        )
    }

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>
    ) where Configuration == Void, Connected.WrappedValue: Equatable {
        self.init(
            keyPath,
            configuration: (),
            valuesEqual: { $0 == $1 }
        )
    }

    public func update() {
        coordinator.update(
            scopeStorage: scope,
            keyPath: keyPath,
            configuration: configuration,
            valuesEqual: valuesEqual
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

@MainActor @dynamicMemberLookup public struct ScopedStateProjection<Value> {
    let base: Binding<Value>

    public subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Member>) -> Binding<Member> {
        base[dynamicMember: keyPath]
    }
}

//
//  ScopedState.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import SwiftUI

@MainActor @propertyWrapper public struct ScopedState<Scope, Configuration, Connected: ConnectedValue>: @MainActor DynamicProperty {
    private typealias Connection = GenericConnection<Configuration, Connected>

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

            var configuration: Configuration
        }

        let storage = ScopedStateStorage<Connected.WrappedValue>()

        private var context: Context?

        var value: Connected.WrappedValue {
            get { storage.requiredValue }
            set {
                guard let session = context?.session else {
                    preconditionFailure("Scoped state was written before DynamicProperty.update()")
                }

                if let setValue = session.setValue {
                    setValue(newValue)
                } else {
                    storage.value = newValue
                }
            }
        }

        func update(
            scopeStorage: ScopedStateStorage<Scope>,
            keyPath: KeyPath<Scope, Connection>,
            configuration: Configuration
        ) {
            let identity = Context.ConnectionIdentity(
                scopeStorage: scopeStorage,
                generation: scopeStorage.generation,
                keyPath: keyPath
            )
            let yield: Connection.Session.YieldValue = { [storage] in storage.value = $0 }

            if context?.identity != identity {
                let connection = identity.scopeStorage.requiredValue[keyPath: identity.keyPath]
                let session = connection.makeSession(configuration)

                context?.session.deactivate()
                context = Context(
                    identity: identity,
                    connection: connection,
                    session: session,
                    configuration: configuration
                )
                session.activate(yield)
            } else if let context, !context.connection.configurationsEqual(context.configuration, configuration) {
                context.session.reconfigure(configuration, yield)
                self.context?.configuration = configuration
            } else {
                context?.session.update(yield)
            }
        }

        isolated deinit {
            context?.session.deactivate()
        }
    }

    @State private var coordinator = Coordinator()

    @Environment(ScopedStateStorage<Scope>.self) private var scope

    private let keyPath: KeyPath<Scope, Connection>

    private let configuration: Configuration

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>,
        configuration: Configuration
    ) {
        self.keyPath = keyPath
        self.configuration = configuration
    }

    public init(
        _ keyPath: KeyPath<Scope, GenericConnection<Configuration, Connected>>
    ) where Configuration == Void {
        self.init(keyPath, configuration: ())
    }

    public func update() {
        coordinator.update(scopeStorage: scope, keyPath: keyPath, configuration: configuration)
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

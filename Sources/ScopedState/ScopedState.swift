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
        @MainActor struct Session {
            struct Context: Equatable {
                let scopeStorage: ScopedStateStorage<Scope>

                let generation: UInt

                let keyPath: KeyPath<Scope, Connection>

                static func == (lhs: Context, rhs: Context) -> Bool {
                    lhs.scopeStorage === rhs.scopeStorage
                    && lhs.generation == rhs.generation
                    && lhs.keyPath == rhs.keyPath
                }
            }

            let context: Context

            let connection: Connection

            let channel: Connection.Channel

            var configuration: Configuration

            var cancelObservation: Connection.Channel.Cancel
        }

        let storage = ScopedStateStorage<Connected.WrappedValue>()

        private var session: Session?

        var value: Connected.WrappedValue {
            get { storage.requiredValue }
            set {
                guard let channel = session?.channel else {
                    preconditionFailure("Scoped state was written before DynamicProperty.update()")
                }

                if let setValue = channel.setValue {
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
            let context = Session.Context(
                scopeStorage: scopeStorage,
                generation: scopeStorage.generation,
                keyPath: keyPath
            )

            if session?.context != context {
                let connection = context.scopeStorage.requiredValue[keyPath: context.keyPath]
                let channel = connection.makeChannel(configuration)

                session?.cancelObservation()
                let cancelObservation = channel.observe { [storage] value in
                    storage.value = value
                }
                session = Session(
                    context: context,
                    connection: connection,
                    channel: channel,
                    configuration: configuration,
                    cancelObservation: cancelObservation
                )
                storage.value = channel.currentValue()
            } else if let session, !session.connection.configurationsEqual(session.configuration, configuration) {
                session.cancelObservation()
                session.channel.updateConfiguration(configuration)
                let cancelObservation = session.channel.observe { [storage] value in
                    storage.value = value
                }
                self.session?.configuration = configuration
                self.session?.cancelObservation = cancelObservation
                storage.value = session.channel.currentValue()
            }
        }

        isolated deinit {
            session?.cancelObservation()
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

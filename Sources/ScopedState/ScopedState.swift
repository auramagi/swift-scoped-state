//
//  ScopedState.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import Combine
import SwiftUI

@MainActor @propertyWrapper public struct ScopedState<Scope, Configuration, Connected: ConnectedValue>: @MainActor DynamicProperty {
    private typealias Connection = ConnectionDefinition<Configuration, Connected>

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

            let handle: Connection.Handle

            var configuration: Configuration

            var subscription: AnyCancellable? = nil
        }

        let storage = ScopedStateStorage<Connected.WrappedValue>()

        private var session: Session?

        var value: Connected.WrappedValue {
            get { storage.requiredValue }
            set {
                guard let handle = session?.handle else {
                    preconditionFailure("Scoped state was written before DynamicProperty.update()")
                }

                if let setValue = handle.setValue {
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

            guard session?.context != context else {
                updateConfigurationIfNeeded(configuration)
                return
            }

            let connection = context.scopeStorage.requiredValue[keyPath: context.keyPath]
            let handle = connection.makeHandle(configuration)

            session?.subscription?.cancel()
            session = Session(
                context: context,
                connection: connection,
                handle: handle,
                configuration: configuration
            )

            storage.value = handle.currentValue()

            session?.subscription = handle.updates
                .eraseToAnyPublisher()
                .receive(on: DispatchQueue.main)
                .map(Optional.some)
                .assign(to: \.value, on: storage)
        }

        private func updateConfigurationIfNeeded(_ configuration: Configuration) {
            guard let session, !session.connection.configurationsEqual(session.configuration, configuration) else {
                return
            }

            self.session?.configuration = configuration
            session.handle.updateConfiguration(configuration)
            storage.value = session.handle.currentValue()
        }
    }

    @State private var coordinator = Coordinator()

    @Environment(ScopedStateStorage<Scope>.self) private var scope

    private let keyPath: KeyPath<Scope, Connection>

    private let configuration: Configuration

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Connected>>,
        configuration: Configuration
    ) {
        self.keyPath = keyPath
        self.configuration = configuration
    }

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Connected>>
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

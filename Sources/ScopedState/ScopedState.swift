//
//  ScopedState.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import Combine
import SwiftUI

@MainActor @propertyWrapper public struct ScopedState<Scope, Configuration, Connected: ConnectedValue>: @MainActor DynamicProperty {
    @MainActor private final class Coordinator {
        typealias Definition = ConnectionDefinition<Configuration, Connected>

        private struct SourceIdentity: Equatable {
            let storage: ScopedStateStorage<Scope>

            let generation: UInt

            let keyPath: KeyPath<Scope, Definition>

            static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.storage === rhs.storage
                    && lhs.generation == rhs.generation
                    && lhs.keyPath == rhs.keyPath
            }
        }

        private struct ActiveConnection {
            let source: SourceIdentity

            let definition: Definition

            var configuration: Configuration

            let session: Definition.Session

            var subscription: AnyCancellable?
        }

        let storage = ScopedStateStorage<Connected.WrappedValue>()

        private var active: ActiveConnection?

        var value: Connected.WrappedValue {
            get { storage.requiredValue }
            set {
                guard let session = active?.session else {
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
            keyPath: KeyPath<Scope, Definition>,
            configuration: Configuration
        ) {
            let source = SourceIdentity(
                storage: scopeStorage,
                generation: scopeStorage.generation,
                keyPath: keyPath
            )

            guard active?.source != source else {
                updateConfigurationIfNeeded(configuration)
                return
            }

            let definition = scopeStorage.requiredValue[keyPath: keyPath]
            let session = definition.makeSession(configuration: configuration)

            active?.subscription?.cancel()
            active = ActiveConnection(
                source: source,
                definition: definition,
                configuration: configuration,
                session: session,
                subscription: nil
            )

            storage.value = session.currentValue()

            active?.subscription = session.updates
                .eraseToAnyPublisher()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] value in
                    guard self?.active?.source == source else { return }

                    self?.storage.value = value
                }
        }

        private func updateConfigurationIfNeeded(_ configuration: Configuration) {
            guard
                let active,
                !active.definition.configurationsAreEqual(
                    active.configuration,
                    configuration
                )
            else { return }

            self.active?.configuration = configuration
            active.session.updateConfiguration(configuration)
            storage.value = active.session.currentValue()
        }
    }

    @Environment(ScopedStateStorage<Scope>.self) private var scope

    @State private var coordinator: Coordinator

    private let keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Connected>>

    private let configuration: Configuration

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Connected>>,
        configuration: Configuration
    ) {
        self._coordinator = State(initialValue: Coordinator())
        self.keyPath = keyPath
        self.configuration = configuration
    }

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Connected>>
    ) where Configuration == Void {
        self.init(keyPath, configuration: ())
    }

    public func update() {
        coordinator.update(
            scopeStorage: scope,
            keyPath: keyPath,
            configuration: configuration
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

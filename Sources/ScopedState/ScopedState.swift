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
        let storage = ScopedStateStorage<Connected.WrappedValue>()

        private var definitionIdentity: ObjectIdentifier?

        private var configuration: Configuration?

        private var session: ConnectionDefinition<Configuration, Connected>.Session?

        private var subscription: AnyCancellable?

        private var setValue: @MainActor (Connected.WrappedValue) -> Void = { _ in
            preconditionFailure("Scoped state was written before DynamicProperty.update()")
        }

        func update(
            definition: ConnectionDefinition<Configuration, Connected>,
            configuration: Configuration
        ) {
            let definitionIdentity = definition.identity

            guard self.definitionIdentity != definitionIdentity else {
                updateConfigurationIfNeeded(configuration, definition: definition)
                return
            }

            let session = definition.makeSession(configuration: configuration)
            subscription?.cancel()

            self.definitionIdentity = definitionIdentity
            self.configuration = configuration
            self.session = session
            if let setValue = session.setValue {
                self.setValue = setValue
            } else {
                let storage = storage
                self.setValue = { value in
                    storage.value = value
                }
            }
            storage.value = session.currentValue()

            subscription = session.updates
                .eraseToAnyPublisher()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] value in
                    guard self?.definitionIdentity == definitionIdentity else {
                        return
                    }
                    self?.storage.value = value
                }
        }

        var value: Connected.WrappedValue {
            get { storage.requiredValue }
            set { setValue(newValue) }
        }

        private func updateConfigurationIfNeeded(
            _ configuration: Configuration,
            definition: ConnectionDefinition<Configuration, Connected>
        ) {
            guard
                let previousConfiguration = self.configuration,
                !definition.configurationsAreEqual(previousConfiguration, configuration),
                let session
            else { return }

            self.configuration = configuration
            session.updateConfiguration(configuration)
            storage.value = session.currentValue()
        }
    }

    @Environment(ScopedStateStorage<Scope>.self) private var scope

    @State private var coordinator: Coordinator

    private let keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Connected>>

    private let configuration: Configuration

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Connected>>
    ) where Configuration == Void {
        self.init(keyPath, configuration: ())
    }

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Connected>>,
        configuration: Configuration
    ) {
        self._coordinator = State(initialValue: Coordinator())
        self.keyPath = keyPath
        self.configuration = configuration
    }

    public func update() {
        coordinator.update(
            definition: scope.requiredValue[keyPath: keyPath],
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
        let projection = ScopedStateProjection(base: $coordinator.value)
        return Connected.transformProjection(projection)
    }
}

@MainActor @dynamicMemberLookup public struct ScopedStateProjection<Value> {
    let base: Binding<Value>

    public subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Member>) -> Binding<Member> {
        base[dynamicMember: keyPath]
    }
}

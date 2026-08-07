//
//  ScopedState.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-07.
//

import Combine
import SwiftUI

@MainActor @propertyWrapper public struct ScopedState<Scope, Configuration, Value: ConnectedValue>: @MainActor DynamicProperty {
    @MainActor private final class Coordinator {
        let storage = ScopedStateStorage<Value.WrappedValue>()

        private var sourceIdentity: ObjectIdentifier?

        private var configuration: Configuration?

        private var session: ConnectionSession<Configuration, Value.WrappedValue>?

        private var subscription: AnyCancellable?

        private var setValue: @MainActor (Value.WrappedValue) -> Void = { _ in
            preconditionFailure("Scoped state was written before DynamicProperty.update()")
        }

        func update(
            source: ConnectionDefinition<Configuration, Value>,
            configuration: Configuration
        ) {
            let sourceIdentity = source.identity

            guard self.sourceIdentity != sourceIdentity else {
                updateConfigurationIfNeeded(configuration, source: source)
                return
            }

            let session = source.makeSession(configuration: configuration)
            subscription?.cancel()

            self.sourceIdentity = sourceIdentity
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
                    guard self?.sourceIdentity == sourceIdentity else {
                        return
                    }
                    self?.storage.value = value
                }
        }

        var value: Value.WrappedValue {
            get {
                storage.requiredValue
            }
            set {
                setValue(newValue)
            }
        }

        private func updateConfigurationIfNeeded(
            _ configuration: Configuration,
            source: ConnectionDefinition<Configuration, Value>
        ) {
            guard
                let previousConfiguration = self.configuration,
                !source.configurationsAreEqual(previousConfiguration, configuration),
                let session
            else {
                return
            }

            self.configuration = configuration
            session.updateConfiguration(configuration)
            storage.value = session.currentValue()
        }
    }

    @Environment(ScopedStateStorage<Scope>.self) private var scope

    @State private var coordinator: Coordinator

    private let keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Value>>

    private let configuration: Configuration

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Void, Value>>
    ) where Configuration == Void {
        self.init(keyPath, configuration: ())
    }

    public init(
        _ keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Value>>,
        configuration: Configuration
    ) {
        self._coordinator = State(initialValue: Coordinator())
        self.keyPath = keyPath
        self.configuration = configuration
    }

    public func update() {
        coordinator.update(
            source: scope.requiredValue[keyPath: keyPath],
            configuration: configuration
        )
    }

    var valueStorage: ScopedStateStorage<Value.WrappedValue> {
        coordinator.storage
    }

    public var wrappedValue: Value.WrappedValue {
        coordinator.storage.requiredValue
    }

    public var projectedValue: Value.Projection {
        let projection = ScopedStateProjection(binding: $coordinator.value)
        return Value.transformProjection(projection)
    }
}

@MainActor @dynamicMemberLookup public struct ScopedStateProjection<Value> {
    let binding: Binding<Value>

    public subscript<Member>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Member>) -> Binding<Member> {
        binding[dynamicMember: keyPath]
    }
}

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

        @MainActor struct Session {
            typealias Definition = ConnectionDefinition<Configuration, Connected>

            struct Context {
                let scopeStorage: ScopedStateStorage<Scope>

                let generation: UInt

                let keyPath: KeyPath<Scope, Definition>

                var configuration: Configuration

                func matches(_ other: Self) -> Bool {
                    scopeStorage === other.scopeStorage
                    && generation == other.generation
                    && keyPath == other.keyPath
                }
            }

            var context: Context

            let definition: Definition

            let handle: Definition.Handle

            var subscription: AnyCancellable?
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

        func update(context: Session.Context) {
            guard session?.context.matches(context) != true else {
                updateConfigurationIfNeeded(context.configuration)
                return
            }

            let definition = context.scopeStorage.requiredValue[keyPath: context.keyPath]
            let handle = definition.makeHandle(context.configuration)

            session?.subscription?.cancel()
            session = Session(
                context: context,
                definition: definition,
                handle: handle,
                subscription: nil
            )

            storage.value = handle.currentValue()

            session?.subscription = handle.updates
                .eraseToAnyPublisher()
                .receive(on: DispatchQueue.main)
                .map(Optional.some)
                .assign(to: \.value, on: storage)
        }

        private func updateConfigurationIfNeeded(_ configuration: Configuration) {
            guard
                let session,
                !session.definition.configurationsEqual(
                    session.context.configuration,
                    configuration
                )
            else { return }

            self.session?.context.configuration = configuration
            session.handle.updateConfiguration(configuration)
            storage.value = session.handle.currentValue()
        }
    }

    @State private var coordinator = Coordinator()

    @Environment(ScopedStateStorage<Scope>.self) private var scope

    private let keyPath: KeyPath<Scope, ConnectionDefinition<Configuration, Connected>>

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
        coordinator.update(
            context: .init(
                scopeStorage: scope,
                generation: scope.generation,
                keyPath: keyPath,
                configuration: configuration
            )
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

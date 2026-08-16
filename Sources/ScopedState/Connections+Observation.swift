//
//  Connections+Observation.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-10.
//

import Observation

@MainActor private final class ObservationActivation<Value> {
    let currentValue: () -> Value

    let invalidate: () -> Void

    var isActive = true

    var isStale = false

    init(
        currentValue: @escaping () -> Value,
        invalidate: @escaping () -> Void
    ) {
        self.currentValue = currentValue
        self.invalidate = invalidate
    }

    func read() -> Value {
        withObservationTracking {
            currentValue()
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isActive, !self.isStale else {
                    return
                }
                self.isStale = true
                self.invalidate()
            }
        }
    }

    func refresh() -> Value? {
        guard isActive, isStale else {
            return nil
        }
        isStale = false
        return read()
    }

    func cancel() {
        isActive = false
    }
}

extension ConnectionDefinition where Self == Connections {
    /// Creates a read-only connection to values tracked by Observation.
    ///
    /// Changes to tracked properties must be made on the main actor.
    public static func observation<WrappedValue>(
        _ currentValue: @escaping () -> WrappedValue
    ) -> some ConnectionDefinition<EmptyConfiguration, WrappedValue> {
        ReadOnlyConnectionDefinition { _ in
            var activeObservation: ObservationActivation<WrappedValue>?

            return .init { yield in
                let observation = ObservationActivation(
                    currentValue: currentValue,
                    invalidate: { yield(.invalidate) }
                )
                activeObservation = observation
                return (
                    initialValue: observation.read(),
                    observation: CancellationToken {
                        observation.cancel()
                    }
                )
            } refresh: {
                activeObservation?.refresh()
            }
        }
    }

    /// Creates a read-only connection to an observable property.
    public static func observation<Root: Observable, WrappedValue>(
        _ root: Root,
        _ keyPath: KeyPath<Root, WrappedValue>
    ) -> some ConnectionDefinition<EmptyConfiguration, WrappedValue> {
        .observation { root[keyPath: keyPath] }
    }

    /// Creates a writable connection to an observable property.
    public static func observation<Root: Observable, WrappedValue>(
        _ root: Root,
        _ keyPath: ReferenceWritableKeyPath<Root, WrappedValue>
    ) -> some WritableConnectionDefinition<EmptyConfiguration, WrappedValue> {
        let connection = Connections.observation(root, keyPath as KeyPath<Root, WrappedValue>)
        return connection.set { root[keyPath: keyPath] = $0 }
    }
}

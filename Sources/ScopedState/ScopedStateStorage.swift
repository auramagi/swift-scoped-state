//
//  ScopedStateStorage.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-08.
//

import Observation

/// The observable value storage used both by connected properties and as the
/// exact scope type stored in SwiftUI's environment.
@MainActor @Observable final class ScopedStateStorage<Value> {
    @ObservationIgnored
    private var state: (value: Value?, generation: UInt) = (nil, 0)

    var value: Value? {
        access(keyPath: \.state)
        return state.value
    }

    func valueEquals(_ other: Value, by areEquivalent: (Value, Value) -> Bool) -> Bool {
        if let value = state.value {
            areEquivalent(value, other)
        } else {
            false
        }
    }

    func setValue(_ newValue: Value, notifyingObservers: Bool) {
        if notifyingObservers {
            withMutation(keyPath: \.state) {
                state = (newValue, state.generation &+ 1)
            }
        } else {
            state = (newValue, state.generation &+ 1)
        }
    }

    /// Notifies readers to refresh without replacing the stored value or
    /// changing its generation.
    func invalidate() {
        withMutation(keyPath: \.state) {}
    }

    var requiredValue: Value {
        if let value {
            value
        } else {
            preconditionFailure("Scoped state was read before DynamicProperty.update()")
        }
    }

    var generation: UInt {
        access(keyPath: \.state)
        return state.generation
    }
}

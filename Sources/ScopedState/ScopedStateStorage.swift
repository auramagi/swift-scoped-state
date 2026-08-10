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

    func setValue(
        _ value: Value,
        notifyingObservers: Bool,
        valuesEqual: @MainActor (Value, Value) -> Bool
    ) {
        if let currentValue = state.value, valuesEqual(currentValue, value) {
            return
        }

        if notifyingObservers {
            withMutation(keyPath: \.state) {
                state = (value, state.generation &+ 1)
            }
        } else {
            state = (value, state.generation &+ 1)
        }
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

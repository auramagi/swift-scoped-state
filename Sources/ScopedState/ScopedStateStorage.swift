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
    private var state: (value: Value?, generation: UInt) = (nil, 0)

    var value: Value? {
        get { state.value }
        set { state = (newValue, state.generation &+ 1) }
    }

    var requiredValue: Value {
        if let value = state.value {
            value
        } else {
            preconditionFailure("Scoped state was read before DynamicProperty.update()")
        }
    }

    var generation: UInt {
        state.generation
    }
}

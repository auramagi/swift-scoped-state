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
    var value: Value?

    var requiredValue: Value {
        if let value {
            value
        } else {
            preconditionFailure("Scoped state was read before DynamicProperty.update()")
        }
    }
}

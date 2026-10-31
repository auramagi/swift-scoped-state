//
//  ScopeSnapshot.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-10-31.
//

import Observation

/// An immutable scope revision published through the environment.
/// Consumers read the captured value, not the observable backing storage.
final class ScopeSnapshot<Scope>: Observable, Equatable {
    @MainActor final class Cache {
        private var snapshot: ScopeSnapshot?

        func snapshot(from storage: ScopedStateStorage<Scope>) -> ScopeSnapshot {
            // Track invalidation even when the published revision is unchanged.
            let generation = storage.generation
            if let snapshot, snapshot.storage === storage, snapshot.generation == generation {
                return snapshot
            }
            let snapshot = ScopeSnapshot(storage)
            self.snapshot = snapshot
            return snapshot
        }
    }

    private let storage: ScopedStateStorage<Scope>

    private let generation: UInt

    let value: Scope

    @MainActor private init(_ storage: ScopedStateStorage<Scope>) {
        self.storage = storage
        self.generation = storage.generation
        self.value = storage.requiredValue
    }

    static func == (lhs: ScopeSnapshot, rhs: ScopeSnapshot) -> Bool {
        lhs === rhs
    }
}

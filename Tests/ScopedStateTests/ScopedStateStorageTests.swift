//
//  ScopedStateStorageTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-09.
//

import Observation
import os
import Testing
@testable import ScopedState

@Suite("Scoped state storage")
@MainActor struct ScopedStateStorageTests {
    @Test
    func storesValuesAndTracksEveryInstallationAndDelivery() {
        let storage = ScopedStateStorage<Int>()

        #expect(storage.value == nil)
        #expect(storage.generation == 0)

        storage.setValue(
            1,
            notifyingObservers: false
        )
        #expect(storage.requiredValue == 1)
        #expect(storage.generation == 1)

        storage.setValue(
            1,
            notifyingObservers: false
        )
        #expect(storage.requiredValue == 1)
        #expect(storage.generation == 2)

        storage.setValue(
            2,
            notifyingObservers: true
        )
        #expect(storage.requiredValue == 2)
        #expect(storage.generation == 3)
    }

    @Test
    func installationsAreSilentAndDeliveriesNotify() {
        let storage = ScopedStateStorage<Int>()
        storage.setValue(
            1,
            notifyingObservers: false
        )

        let notificationCount = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = storage.value
        } onChange: {
            notificationCount.withLock { $0 += 1 }
        }

        storage.setValue(
            2,
            notifyingObservers: false
        )
        #expect(storage.requiredValue == 2)
        #expect(notificationCount.withLock { $0 } == 0)

        storage.setValue(
            3,
            notifyingObservers: true
        )
        #expect(storage.requiredValue == 3)
        #expect(storage.generation == 3)
        #expect(notificationCount.withLock { $0 } == 1)
    }

    @Test
    func invalidationNotifiesWithoutReplacingTheValue() {
        let storage = ScopedStateStorage<Int>()
        storage.setValue(
            1,
            notifyingObservers: false
        )

        let notificationCount = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = storage.value
        } onChange: {
            notificationCount.withLock { $0 += 1 }
        }

        storage.invalidate()

        #expect(storage.requiredValue == 1)
        #expect(storage.generation == 1)
        #expect(notificationCount.withLock { $0 } == 1)
    }

    @Test
    func comparesItsValueUsingTheProvidedEquality() {
        struct Value {
            let identity: Int

            let revision: Int
        }

        let storage = ScopedStateStorage<Value>()

        #expect(!storage.valueEquals(
            Value(identity: 1, revision: 1),
            by: { $0.identity == $1.identity }
        ))

        storage.setValue(
            Value(identity: 1, revision: 1),
            notifyingObservers: false
        )

        #expect(storage.valueEquals(
            Value(identity: 1, revision: 2),
            by: { $0.identity == $1.identity }
        ))
        #expect(!storage.valueEquals(
            Value(identity: 2, revision: 1),
            by: { $0.identity == $1.identity }
        ))
        #expect(storage.generation == 1)
    }

    #if os(macOS)
    @Test
    func readingRequiredValueBeforeAssignmentFails() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                _ = ScopedStateStorage<Int>().requiredValue
            }
        }
    }
    #endif
}

//
//  ScopedStateStorageTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-09.
//

import Testing
@testable import ScopedState

@Suite("Scoped state storage")
@MainActor struct ScopedStateStorageTests {
    @Test
    func storesValuesAndTracksEveryAssignment() {
        let storage = ScopedStateStorage<Int>()

        #expect(storage.value == nil)
        #expect(storage.generation == 0)

        storage.value = 1
        #expect(storage.requiredValue == 1)
        #expect(storage.generation == 1)

        storage.value = 1
        #expect(storage.requiredValue == 1)
        #expect(storage.generation == 2)

        storage.value = nil
        #expect(storage.value == nil)
        #expect(storage.generation == 3)
    }
}

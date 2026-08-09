//
//  ConnectionCoreTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-09.
//

import Testing
@testable import ScopedState

@Suite("Core connections")
@MainActor struct ConnectionCoreTests {
    @Test
    func constantProvidesAnUnobservedInitialValue() {
        let connection: Connection<Int> = .constant(42)
        let channel = connection.makeChannel(())

        #expect(connection.configurationsEqual((), ()))
        #expect(channel.setValue == nil)
        #expect(channel.observe == nil)

        guard case let .initial(value) = channel.valueSource else {
            Issue.record("A constant connection should provide an initial value")
            return
        }
        #expect(value == 42)
    }
}

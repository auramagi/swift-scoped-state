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
    func writeRoutingIsAvailableToEverySession() {
        var writtenValues: [Int] = []
        let connection = Connection<Int>.constant(0).set {
            writtenValues.append($0)
        }
        let firstSession = connection.makeSession(())
        let secondSession = connection.makeSession(())

        firstSession.setValue?(1)
        secondSession.setValue?(2)

        #expect(writtenValues == [1, 2])
    }

    @Test
    func constantProvidesAnUnobservedInitialValue() {
        let connection: Connection<Int> = .constant(42)
        let session = connection.makeSession(())

        #expect(connection.configurationsEqual((), ()))
        #expect(session.setValue == nil)

        #expect(session.activate { _ in }.initialValue == 42)
        #expect(session.refresh() == nil)
    }

    @Test
    func constantCanComposeMappingAndWriteRouting() {
        var writtenValues: [String] = []
        let connection: Connection<String>.Writable = .constant(42)
            .map(String.init)
            .set { writtenValues.append($0) }
        let session = connection.makeSession(())

        let activation = session.activate { _ in }
        session.setValue?("replacement")

        #expect(activation.initialValue == "42")
        #expect(writtenValues == ["replacement"])
    }
}

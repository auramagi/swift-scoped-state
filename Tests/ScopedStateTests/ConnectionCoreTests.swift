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
    func unconfiguredConnectionCanDefineItsSessionInline() {
        var writtenValues: [Int] = []
        let connection = Connection<Int> { _ in
            1
        }.set {
            writtenValues.append($0)
        }
        let session = connection.makeSession(())

        let currentValue = session.activate { _ in }
        session.setValue?(2)

        #expect(currentValue == 1)
        #expect(writtenValues == [2])
    }

    @Test
    func inlineOperationStateIsIndependentBetweenSessions() {
        final class Counter {
            var value = 0
        }

        let connection = Connection<Int> { [counter = Counter()] _ in
            counter.value += 1
            return counter.value
        }
        let firstSession = connection.makeSession(())
        let secondSession = connection.makeSession(())

        #expect(firstSession.activate { _ in } == 1)
        #expect(firstSession.activate { _ in } == 2)
        #expect(secondSession.activate { _ in } == 1)
    }

    @Test
    func writeRoutingIsAvailableToEverySession() {
        var writtenValues: [Int] = []
        let connection = Connection<Int> { _ in
            0
        }.set {
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

        #expect(session.activate { _ in } == 42)
        #expect(session.update() == nil)

        session.deactivate()
    }

    @Test
    func constantCanComposeMappingAndWriteRouting() {
        var writtenValues: [String] = []
        let connection: Connection<String>.Writable = .constant(42)
            .map(String.init)
            .set { writtenValues.append($0) }
        let session = connection.makeSession(())

        let currentValue = session.activate { _ in }
        session.setValue?("replacement")

        #expect(currentValue == "42")
        #expect(writtenValues == ["replacement"])
    }
}

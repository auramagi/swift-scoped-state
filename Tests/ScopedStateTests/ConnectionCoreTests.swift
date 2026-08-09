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
        let connection = Connection<Int> { yield in
            yield(1)
        }.set {
            writtenValues.append($0)
        }
        let session = connection.makeSession(())

        var receivedValues: [Int] = []
        session.activate { receivedValues.append($0) }
        session.setValue?(2)

        #expect(receivedValues == [1])
        #expect(writtenValues == [2])
    }

    @Test
    func inlineOperationStateIsIndependentBetweenSessions() {
        final class Counter {
            var value = 0
        }

        let connection = Connection<Int> { [counter = Counter()] yield in
            counter.value += 1
            yield(counter.value)
        }
        let firstSession = connection.makeSession(())
        let secondSession = connection.makeSession(())

        var firstValues: [Int] = []
        var secondValues: [Int] = []
        firstSession.activate { firstValues.append($0) }
        firstSession.activate { firstValues.append($0) }
        secondSession.activate { secondValues.append($0) }

        #expect(firstValues == [1, 2])
        #expect(secondValues == [1])
    }

    @Test
    func writeRoutingIsAvailableToEverySession() {
        var writtenValues: [Int] = []
        let connection = Connection<Int> { _ in
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

        var receivedValues: [Int] = []
        let yield: Connection<Int>.Session.YieldValue = { receivedValues.append($0) }
        session.activate(yield)
        #expect(receivedValues == [42])

        session.update(yield)
        #expect(receivedValues == [42])

        session.deactivate()
    }

    @Test
    func constantCanComposeMappingAndWriteRouting() {
        var writtenValues: [String] = []
        let connection: Connection<String>.Writable = .constant(42)
            .map(String.init)
            .set { writtenValues.append($0) }
        let session = connection.makeSession(())

        var receivedValues: [String] = []
        session.activate { receivedValues.append($0) }
        session.setValue?("replacement")

        #expect(receivedValues == ["42"])
        #expect(writtenValues == ["replacement"])
    }
}

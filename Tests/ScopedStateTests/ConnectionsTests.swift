//
//  ConnectionsTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-09.
//

import Testing
@testable import ScopedState

@Suite("Connections")
@MainActor struct ConnectionsTests {
    @Test
    func configuredConnectionCreatesSession() {
        let connection: ConfiguredConnection<Int, String> = .readOnly { configuration in
            ConnectionSession<String, Int> { _ in
                (initialValue: configuration.count, observation: nil)
            } reconfigure: { _ in
            }
        }

        let session = connection.makeSession("value")
        #expect(session.activate { _ in }.initialValue == 5)
    }

    @Test
    func configuredWritableConnectionCreatesSessionSpecificSetters() {
        var writes: [(configuration: String, value: Int)] = []
        let connection: WritableConfiguredConnection<Int, String> = .readWrite { configuration in
            ConnectionSession<String, Int>(
                activate: { _ in
                    (initialValue: 0, observation: nil)
                },
                reconfigure: { _ in },
                setValue: { writes.append((configuration, $0)) }
            )
        }

        connection.makeSession("first").setValue?(1)
        connection.makeSession("second").setValue?(2)

        #expect(writes.count == 2)
        #expect(writes[0] == ("first", 1))
        #expect(writes[1] == ("second", 2))
    }

    @Test
    func constantProvidesAnUnobservedInitialValue() {
        let connection: Connection<Int> = .constant(42)
        let session = connection.makeSession(.init())

        #expect(session.setValue == nil)

        #expect(session.activate { _ in }.initialValue == 42)
        #expect(session.refresh() == nil)
    }

    @Test
    func initialProvidesIndependentWritableLocalValues() throws {
        let connection: WritableConnection<Int> = .initial(1)
        let firstSession = connection.makeSession(.init())
        let secondSession = connection.makeSession(.init())
        var firstValues: [Int] = []
        var secondValues: [Int] = []

        let firstActivation = firstSession.activate {
            if case let .value(value) = $0 {
                firstValues.append(value)
            }
        }
        let secondActivation = secondSession.activate {
            if case let .value(value) = $0 {
                secondValues.append(value)
            }
        }

        let setFirstValue = try #require(firstSession.setValue)
        setFirstValue(2)

        #expect(firstActivation.initialValue == 1)
        #expect(secondActivation.initialValue == 1)
        #expect(firstActivation.observation == nil)
        #expect(secondActivation.observation == nil)
        #expect(firstSession.refresh() == nil)
        #expect(secondSession.refresh() == nil)
        #expect(firstValues == [2])
        #expect(secondValues.isEmpty)
    }
}

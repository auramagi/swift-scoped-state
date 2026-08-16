//
//  ConnectionTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-09.
//

import Testing
@testable import ScopedState

@Suite("Connection")
@MainActor struct ConnectionTests {
    @Test
    func configuredConnectionCreatesSession() {
        typealias ConfiguredConnection = Connection<Int>.Configuration<String>

        let connection = ConfiguredConnection { configuration in
            ConfiguredConnection.Session { _ in
                (initialValue: configuration.count, observation: nil)
            } reconfigure: { _ in
            }
        }

        let session = connection.makeSession("value")
        #expect(session.activate { _ in }.initialValue == 5)
    }

    @Test
    func configuredWritableConnectionCreatesSessionSpecificSetters() {
        typealias ConfiguredConnection = Connection<Int>.Configuration<String>.Writable

        var writes: [(configuration: String, value: Int)] = []
        let connection = ConfiguredConnection { configuration in
            ConfiguredConnection.Session(
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
}

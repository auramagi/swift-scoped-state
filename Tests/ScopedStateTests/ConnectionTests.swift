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
    func equatableConfigurationUsesValueEquality() {
        typealias ConfiguredConnection = Connection<Int>.Configuration<String>

        let connection = ConfiguredConnection { configuration in
            ConfiguredConnection.Session { _ in
                (initialValue: configuration.count, cancellation: nil)
            } reconfigure: { _ in
            }
        }

        #expect(connection.configurationsEqual("same", "same"))
        #expect(!connection.configurationsEqual("short", "longer"))
        let session = connection.makeSession("value")
        #expect(session.activate { _ in }.initialValue == 5)
    }

    @Test
    func customConfigurationEqualityAndUpdatesAreForwarded() {
        typealias ConfiguredConnection = Connection<Int>.Configuration<String>

        var comparisons: [(String, String)] = []
        var updatedConfigurations: [String] = []
        let connection = ConfiguredConnection(
            makeSession: { _ in
                ConfiguredConnection.Session { _ in
                    (initialValue: 0, cancellation: nil)
                } reconfigure: { configuration in
                    updatedConfigurations.append(configuration)
                }
            },
            configurationsEqual: { lhs, rhs in
                comparisons.append((lhs, rhs))
                return lhs.lowercased() == rhs.lowercased()
            }
        )

        #expect(connection.configurationsEqual("VALUE", "value"))
        #expect(comparisons.count == 1)
        #expect(comparisons[0].0 == "VALUE")
        #expect(comparisons[0].1 == "value")

        let session = connection.makeSession("initial")
        session.reconfigure("updated")
        #expect(updatedConfigurations == ["updated"])
    }

    @Test
    func configuredWritableConnectionCreatesSessionSpecificSetters() {
        typealias ConfiguredConnection = Connection<Int>.Configuration<String>.Writable

        var writes: [(configuration: String, value: Int)] = []
        let connection = ConfiguredConnection { configuration in
            ConfiguredConnection.Session(
                activate: { _ in
                    (initialValue: 0, cancellation: nil)
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

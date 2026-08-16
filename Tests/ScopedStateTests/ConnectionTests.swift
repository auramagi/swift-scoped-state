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
    func configuredWritableConnectionSubstitutesForReadOnlyConnection() {
        var writtenValues: [Int] = []
        let writable: WritableConfiguredConnection<Int, String> = .readWrite { configuration in
            ConnectionSession(
                activate: { _ in
                    (initialValue: configuration.count, observation: nil)
                },
                reconfigure: { _ in },
                setValue: { writtenValues.append($0) }
            )
        }
        let readOnly: ConfiguredConnection<Int, String> = writable
        let session = readOnly.makeSession("value")

        session.setValue?(42)

        #expect(writtenValues == [42])
        #expect(session.activate { _ in }.initialValue == 5)
    }

    @Test
    func writeRoutingIsAvailableToEverySession() {
        var writtenValues: [Int] = []
        let connection: WritableConnection<Int> = .constant(0).set {
            writtenValues.append($0)
        }
        let firstSession = connection.makeSession(.init())
        let secondSession = connection.makeSession(.init())

        firstSession.setValue?(1)
        secondSession.setValue?(2)

        #expect(writtenValues == [1, 2])
    }

    @Test
    func constantCanComposeMappingAndWriteRouting() {
        var writtenValues: [String] = []
        let connection: WritableConnection<String> = .constant(42)
            .map(String.init)
            .set { writtenValues.append($0) }
        let session = connection.makeSession(.init())

        let activation = session.activate { _ in }
        session.setValue?("replacement")

        #expect(activation.initialValue == "42")
        #expect(writtenValues == ["replacement"])
    }

    @Test
    func mapTransformsLifecycleValuesAndPreservesConfiguration() {
        typealias SourceConnection = ConfiguredConnection<Int, String>

        var cancellationCount = 0
        let source: SourceConnection = .readOnly { configuration in
            ConnectionSession<String, Int> { _ in
                (
                    initialValue: configuration.count,
                    observation: CancellationToken {
                        cancellationCount += 1
                    }
                )
            } refresh: {
                2
            } reconfigure: { _ in
            }
        }
        let mapped = source.map { "value=\($0)" }
        let session = mapped.makeSession("initial")

        let initialActivation = session.activate { _ in }
        #expect(initialActivation.initialValue == "value=7")
        #expect(session.refresh() == "value=2")
        initialActivation.observation?.cancel()
        session.reconfigure("updated")
        let updatedActivation = session.activate { _ in }
        #expect(updatedActivation.initialValue == "value=7")
        updatedActivation.observation?.cancel()

        #expect(cancellationCount == 2)
    }
}

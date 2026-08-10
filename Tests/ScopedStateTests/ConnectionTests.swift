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
    func readOnlySessionPerformsLifecycleOperations() {
        typealias Session = Connection<Int>.Session

        var events: [String] = []
        let session = Session { _ in
            events.append("activate")
            return .init(
                initialValue: 1,
                cancellation: CancellationToken {
                    events.append("cancel")
                }
            )
        } update: {
            events.append("update")
            return nil
        } reconfigure: { _ in
            events.append("reconfigure")
        }

        #expect(session.setValue == nil)

        let activation = session.activate { _ in }
        #expect(activation.initialValue == 1)
        #expect(session.update() == nil)
        session.reconfigure(())
        activation.cancellation?.cancel()

        #expect(events == ["activate", "update", "reconfigure", "cancel"])
    }

    @Test
    func writableSessionForwardsWrites() {
        typealias Session = Connection<Int>.Writable.Session

        var writtenValues: [Int] = []
        let session = Session { _ in
            .init(initialValue: 0)
        } setValue: {
            writtenValues.append($0)
        }

        guard let setValue = session.setValue else {
            Issue.record("A writable session should expose its setter")
            return
        }

        setValue(2)
        setValue(3)
        #expect(writtenValues == [2, 3])
    }

    @Test
    func equatableConfigurationUsesValueEquality() {
        typealias ConfiguredConnection = Connection<Int>.Configuration<String>

        let connection = ConfiguredConnection { configuration in
            ConfiguredConnection.Session { _ in
                .init(initialValue: configuration.count)
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
                    .init(initialValue: 0)
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
    func currentValueConveniencesManageObservationLifecycle() {
        var currentValue = 1
        var writtenValues: [Int] = []
        var observationCount = 0
        var cancellationCount = 0

        let readOnly = Connection<Int> {
            .init(
                currentValue: { currentValue },
                observe: { _ in
                    observationCount += 1
                    return observationCount
                },
                cancel: { _ in cancellationCount += 1 }
            )
        }
        let writable = readOnly.set {
            writtenValues.append($0)
        }

        let readOnlySession = readOnly.makeSession(())
        let writableSession = writable.makeSession(())
        #expect(readOnlySession.setValue == nil)

        guard let setValue = writableSession.setValue else {
            Issue.record("The writable convenience should expose its setter")
            return
        }

        var readOnlyValues: [Int] = []
        var writableValues: [Int] = []
        let readOnlyActivation = readOnlySession.activate { readOnlyValues.append($0) }
        let writableActivation = writableSession.activate { writableValues.append($0) }
        readOnlyValues.append(readOnlyActivation.initialValue)
        writableValues.append(writableActivation.initialValue)

        #expect(readOnlyValues == [1])
        #expect(writableValues == [1])
        #expect(observationCount == 2)

        currentValue = 2
        #expect(readOnlySession.update() == nil)
        #expect(writableSession.update() == nil)
        #expect(readOnlyValues == [1])
        #expect(writableValues == [1])

        setValue(3)
        #expect(writtenValues == [3])

        readOnlyActivation.cancellation?.cancel()
        writableActivation.cancellation?.cancel()
        #expect(cancellationCount == 2)
    }

    @Test
    func activationOwnsObservationLifetime() {
        var cancellationCount = 0
        let connection = Connection<Int> {
            .init(
                currentValue: { 1 },
                observe: { _ in () },
                cancel: { _ in cancellationCount += 1 }
            )
        }
        let session = connection.makeSession(())
        var activation: Connection<Int>.Session.Activation? = session.activate { _ in }

        #expect(activation?.initialValue == 1)
        #expect(cancellationCount == 0)

        activation = nil

        #expect(cancellationCount == 1)
        #expect(session.update() == nil)
    }

    @Test
    func synchronousObservationValuesDoNotBecomeDeliveries() {
        let connection = Connection<Int> {
            .init(
                currentValue: { 2 },
                observe: { yield in
                    yield(1)
                },
                cancel: { _ in }
            )
        }
        let session = connection.makeSession(())
        var deliveredValues: [Int] = []

        let activation = session.activate { deliveredValues.append($0) }

        #expect(activation.initialValue == 2)
        #expect(deliveredValues.isEmpty)
    }

    @Test
    func mapTransformsLifecycleValuesAndPreservesConfigurationSemantics() {
        typealias SourceConnection = Connection<Int>.Configuration<String>

        var cancellationCount = 0
        let source = SourceConnection(
            makeSession: { configuration in
                SourceConnection.Session { _ in
                    .init(
                        initialValue: configuration.count,
                        cancellation: CancellationToken {
                            cancellationCount += 1
                        }
                    )
                } update: {
                    2
                } reconfigure: { _ in
                }
            },
            configurationsEqual: { $0.lowercased() == $1.lowercased() }
        )
        let mapped = source.map { "value=\($0)" }
        let session = mapped.makeSession("initial")

        #expect(mapped.configurationsEqual("VALUE", "value"))
        let initialActivation = session.activate { _ in }
        #expect(initialActivation.initialValue == "value=7")
        #expect(session.update() == "value=2")
        initialActivation.cancellation?.cancel()
        session.reconfigure("updated")
        let updatedActivation = session.activate { _ in }
        #expect(updatedActivation.initialValue == "value=7")
        updatedActivation.cancellation?.cancel()

        #expect(cancellationCount == 2)
    }

    @Test
    func configuredCurrentValueConvenienceReconnectsAfterConfigurationUpdates() {
        typealias ConfiguredSession = Connection<Int>.Configuration<String>.Session

        var currentValue = 1
        var updatedConfigurations: [String] = []
        var observationCount = 0
        var cancellationCount = 0
        let session = ConfiguredSession(
            currentValue: { currentValue },
            observe: { _ in
                observationCount += 1
                return observationCount
            },
            cancel: { _ in cancellationCount += 1 },
            reconfigure: { updatedConfigurations.append($0) }
        )

        let initialActivation = session.activate { _ in }

        currentValue = 2
        initialActivation.cancellation?.cancel()
        session.reconfigure("updated")
        let updatedActivation = session.activate { _ in }

        #expect(initialActivation.initialValue == 1)
        #expect(updatedActivation.initialValue == 2)
        #expect(updatedConfigurations == ["updated"])
        #expect(observationCount == 2)
        #expect(cancellationCount == 1)

        updatedActivation.cancellation?.cancel()
        #expect(cancellationCount == 2)
    }
}

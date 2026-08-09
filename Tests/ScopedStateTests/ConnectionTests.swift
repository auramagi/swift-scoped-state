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
        let session = Session { yield in
            events.append("activate")
            yield(1)
        } update: { _ in
            events.append("update")
        } reconfigure: { _, _ in
            events.append("reconfigure")
        } deactivate: {
            events.append("deactivate")
        }

        #expect(session.setValue == nil)

        var receivedValues: [Int] = []
        let yield: Session.YieldValue = { receivedValues.append($0) }
        session.activate(yield)
        session.update(yield)
        session.reconfigure((), yield)
        session.deactivate()

        #expect(receivedValues == [1])
        #expect(events == ["activate", "update", "reconfigure", "deactivate"])
    }

    @Test
    func writableSessionForwardsWrites() {
        typealias Session = Connection<Int>.Writable.Session

        var writtenValues: [Int] = []
        let session = Session { _ in
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
            ConfiguredConnection.Session { yield in
                yield(configuration.count)
            } reconfigure: { _, _ in
            }
        }

        #expect(connection.configurationsEqual("same", "same"))
        #expect(!connection.configurationsEqual("short", "longer"))

        let session = connection.makeSession("value")
        var receivedValues: [Int] = []
        session.activate { receivedValues.append($0) }
        #expect(receivedValues == [5])
    }

    @Test
    func customConfigurationEqualityAndUpdatesAreForwarded() {
        typealias ConfiguredConnection = Connection<Int>.Configuration<String>

        var comparisons: [(String, String)] = []
        var updatedConfigurations: [String] = []
        let connection = ConfiguredConnection(
            makeSession: { _ in
                ConfiguredConnection.Session { _ in
                } reconfigure: { configuration, _ in
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
        session.reconfigure("updated") { _ in }
        #expect(updatedConfigurations == ["updated"])
    }

    @Test
    func currentValueConveniencesManageObservationLifecycle() {
        var currentValue = 1
        var writtenValues: [Int] = []
        var observationCount = 0
        var cancellationCount = 0

        let readOnly = Connection<Int>(
            currentValue: { currentValue },
            observe: { _ in
                observationCount += 1
                return observationCount
            },
            cancel: { _ in cancellationCount += 1 }
        )
        let writable = Connection<Int>(
            currentValue: { currentValue },
            observe: { _ in
                observationCount += 1
                return observationCount
            },
            cancel: { _ in cancellationCount += 1 }
        ).set {
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
        let yieldReadOnly: Connection<Int>.Session.YieldValue = { readOnlyValues.append($0) }
        let yieldWritable: Connection<Int>.Writable.Session.YieldValue = { writableValues.append($0) }
        readOnlySession.activate(yieldReadOnly)
        writableSession.activate(yieldWritable)

        #expect(readOnlyValues == [1])
        #expect(writableValues == [1])
        #expect(observationCount == 2)

        currentValue = 2
        readOnlySession.update(yieldReadOnly)
        writableSession.update(yieldWritable)
        #expect(readOnlyValues == [1])
        #expect(writableValues == [1])

        setValue(3)
        #expect(writtenValues == [3])

        readOnlySession.deactivate()
        writableSession.deactivate()
        #expect(cancellationCount == 2)
    }

    @Test
    func mapTransformsLifecycleValuesAndPreservesConfigurationSemantics() {
        typealias SourceConnection = Connection<Int>.Configuration<String>

        var deactivationCount = 0
        let source = SourceConnection(
            makeSession: { configuration in
                SourceConnection.Session { yield in
                    yield(configuration.count)
                } update: { yield in
                    yield(2)
                } reconfigure: { configuration, yield in
                    yield(configuration.count)
                } deactivate: {
                    deactivationCount += 1
                }
            },
            configurationsEqual: { $0.lowercased() == $1.lowercased() }
        )
        let mapped = source.map { "value=\($0)" }
        let session = mapped.makeSession("initial")

        #expect(mapped.configurationsEqual("VALUE", "value"))

        var receivedValues: [String] = []
        let yield: Connection<String>.Configuration<String>.Session.YieldValue = {
            receivedValues.append($0)
        }
        session.activate(yield)
        session.update(yield)
        session.reconfigure("updated", yield)
        session.deactivate()

        #expect(receivedValues == ["value=7", "value=2", "value=7"])
        #expect(deactivationCount == 1)
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

        var receivedValues: [Int] = []
        let yield: ConfiguredSession.YieldValue = { receivedValues.append($0) }
        session.activate(yield)

        currentValue = 2
        session.reconfigure("updated", yield)

        #expect(receivedValues == [1, 2])
        #expect(updatedConfigurations == ["updated"])
        #expect(observationCount == 2)
        #expect(cancellationCount == 1)

        session.deactivate()
        #expect(cancellationCount == 2)
    }
}

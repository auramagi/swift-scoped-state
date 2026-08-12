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
    func initialProvidesIndependentWritableLocalValues() throws {
        let connection: Connection<Int>.Writable = .initial(1)
        let firstSession = connection.makeSession(())
        let secondSession = connection.makeSession(())
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
        #expect(firstActivation.cancellation == nil)
        #expect(secondActivation.cancellation == nil)
        #expect(firstSession.refresh() == nil)
        #expect(secondSession.refresh() == nil)
        #expect(firstValues == [2])
        #expect(secondValues.isEmpty)
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
        let readOnlyActivation = readOnlySession.activate {
            if case let .value(value) = $0 {
                readOnlyValues.append(value)
            }
        }
        let writableActivation = writableSession.activate {
            if case let .value(value) = $0 {
                writableValues.append(value)
            }
        }
        readOnlyValues.append(readOnlyActivation.initialValue)
        writableValues.append(writableActivation.initialValue)

        #expect(readOnlyValues == [1])
        #expect(writableValues == [1])
        #expect(observationCount == 2)

        currentValue = 2
        #expect(readOnlySession.refresh() == nil)
        #expect(writableSession.refresh() == nil)
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
        #expect(session.refresh() == nil)
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

        let activation = session.activate {
            if case let .value(value) = $0 {
                deliveredValues.append(value)
            }
        }

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
                    (
                        initialValue: configuration.count,
                        cancellation: CancellationToken {
                            cancellationCount += 1
                        }
                    )
                } refresh: {
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
        #expect(session.refresh() == "value=2")
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

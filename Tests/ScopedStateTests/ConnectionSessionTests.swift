//
//  ConnectionSessionTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-10.
//

import Testing
@testable import ScopedState

@Suite("Connection session")
@MainActor struct ConnectionSessionTests {
    @Test
    func readOnlySessionPerformsLifecycleOperations() {
        typealias Session = ConnectionSession<EmptyConfiguration, Int>

        var events: [String] = []
        let session = Session { _ in
            events.append("activate")
            return (
                initialValue: 1,
                observation: CancellationToken {
                    events.append("cancel")
                }
            )
        } refresh: {
            events.append("refresh")
            return nil
        } reconfigure: { _ in
            events.append("reconfigure")
        }

        #expect(session.setValue == nil)

        let activation = session.activate { _ in }
        #expect(activation.initialValue == 1)
        #expect(session.refresh() == nil)
        session.reconfigure(.init())
        activation.observation?.cancel()

        #expect(events == ["activate", "refresh", "reconfigure", "cancel"])
    }

    @Test
    func writableSessionForwardsWrites() {
        typealias Session = ConnectionSession<EmptyConfiguration, Int>

        var writtenValues: [Int] = []
        let session = Session { _ in
            (initialValue: 0, observation: nil)
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
    func currentValueConveniencesManageObservationLifecycle() {
        var currentValue = 1
        var writtenValues: [Int] = []
        var observationCount = 0
        var cancellationCount = 0

        let readOnly: Connection<Int> = .readOnly {
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

        let readOnlySession = readOnly.makeSession(.init())
        let writableSession = writable.makeSession(.init())
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

        readOnlyActivation.observation?.cancel()
        writableActivation.observation?.cancel()
        #expect(cancellationCount == 2)
    }

    @Test
    func activationOwnsObservationLifetime() {
        var cancellationCount = 0
        let connection: Connection<Int> = .readOnly {
            .init(
                currentValue: { 1 },
                observe: { _ in () },
                cancel: { _ in cancellationCount += 1 }
            )
        }
        let session = connection.makeSession(.init())
        var activation: ConnectionSession<EmptyConfiguration, Int>.Activation? = session.activate { _ in }

        #expect(activation?.initialValue == 1)
        #expect(cancellationCount == 0)

        activation = nil

        #expect(cancellationCount == 1)
        #expect(session.refresh() == nil)
    }

    @Test
    func synchronousObservationValuesDoNotBecomeDeliveries() {
        let connection: Connection<Int> = .readOnly {
            .init(
                currentValue: { 2 },
                observe: { yield in
                    yield(1)
                },
                cancel: { _ in }
            )
        }
        let session = connection.makeSession(.init())
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
    func configuredCurrentValueConvenienceReconnectsAfterConfigurationUpdates() {
        typealias ConfiguredSession = ConnectionSession<String, Int>

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
        initialActivation.observation?.cancel()
        session.reconfigure("updated")
        let updatedActivation = session.activate { _ in }

        #expect(initialActivation.initialValue == 1)
        #expect(updatedActivation.initialValue == 2)
        #expect(updatedConfigurations == ["updated"])
        #expect(observationCount == 2)
        #expect(cancellationCount == 1)

        updatedActivation.observation?.cancel()
        #expect(cancellationCount == 2)
    }
}

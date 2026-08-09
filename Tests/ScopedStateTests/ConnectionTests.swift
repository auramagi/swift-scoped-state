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
    func readOnlyChannelPerformsLifecycleOperations() {
        typealias Channel = Connection<Int>.Channel

        var events: [String] = []
        let channel = Channel { yield in
            events.append("activate")
            yield(1)
        } update: { _ in
            events.append("update")
        } reconfigure: { _, _ in
            events.append("reconfigure")
        } deactivate: {
            events.append("deactivate")
        }

        #expect(channel.setValue == nil)

        var receivedValues: [Int] = []
        let yield: Channel.YieldValue = { receivedValues.append($0) }
        channel.activate(yield)
        channel.update(yield)
        channel.reconfigure((), yield)
        channel.deactivate()

        #expect(receivedValues == [1])
        #expect(events == ["activate", "update", "reconfigure", "deactivate"])
    }

    @Test
    func writableChannelForwardsWrites() {
        typealias Channel = Connection<Int>.Writable.Channel

        var writtenValues: [Int] = []
        let channel = Channel { _ in
        } setValue: {
            writtenValues.append($0)
        }

        guard let setValue = channel.setValue else {
            Issue.record("A writable channel should expose its setter")
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
            ConfiguredConnection.Channel { yield in
                yield(configuration.count)
            } reconfigure: { _, _ in
            }
        }

        #expect(connection.configurationsEqual("same", "same"))
        #expect(!connection.configurationsEqual("short", "longer"))

        let channel = connection.makeChannel("value")
        var receivedValues: [Int] = []
        channel.activate { receivedValues.append($0) }
        #expect(receivedValues == [5])
    }

    @Test
    func customConfigurationEqualityAndUpdatesAreForwarded() {
        typealias ConfiguredConnection = Connection<Int>.Configuration<String>

        var comparisons: [(String, String)] = []
        var updatedConfigurations: [String] = []
        let connection = ConfiguredConnection(
            makeChannel: { _ in
                ConfiguredConnection.Channel { _ in
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

        let channel = connection.makeChannel("initial")
        channel.reconfigure("updated") { _ in }
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
        let writable = Connection<Int>.Writable(
            currentValue: { currentValue },
            setValue: { writtenValues.append($0) },
            observe: { _ in
                observationCount += 1
                return observationCount
            },
            cancel: { _ in cancellationCount += 1 }
        )

        let readOnlyChannel = readOnly.makeChannel(())
        let writableChannel = writable.makeChannel(())
        #expect(readOnlyChannel.setValue == nil)

        guard let setValue = writableChannel.setValue else {
            Issue.record("The writable convenience should expose its setter")
            return
        }

        var readOnlyValues: [Int] = []
        var writableValues: [Int] = []
        let yieldReadOnly: Connection<Int>.Channel.YieldValue = { readOnlyValues.append($0) }
        let yieldWritable: Connection<Int>.Writable.Channel.YieldValue = { writableValues.append($0) }
        readOnlyChannel.activate(yieldReadOnly)
        writableChannel.activate(yieldWritable)

        #expect(readOnlyValues == [1])
        #expect(writableValues == [1])
        #expect(observationCount == 2)

        currentValue = 2
        readOnlyChannel.update(yieldReadOnly)
        writableChannel.update(yieldWritable)
        #expect(readOnlyValues == [1])
        #expect(writableValues == [1])

        setValue(3)
        #expect(writtenValues == [3])

        readOnlyChannel.deactivate()
        writableChannel.deactivate()
        #expect(cancellationCount == 2)
    }

    @Test
    func configuredCurrentValueConvenienceReconnectsAfterConfigurationUpdates() {
        typealias ConfiguredChannel = Connection<Int>.Configuration<String>.Channel

        var currentValue = 1
        var updatedConfigurations: [String] = []
        var observationCount = 0
        var cancellationCount = 0
        let channel = ConfiguredChannel(
            currentValue: { currentValue },
            observe: { _ in
                observationCount += 1
                return observationCount
            },
            cancel: { _ in cancellationCount += 1 },
            reconfigure: { updatedConfigurations.append($0) }
        )

        var receivedValues: [Int] = []
        let yield: ConfiguredChannel.YieldValue = { receivedValues.append($0) }
        channel.activate(yield)

        currentValue = 2
        channel.reconfigure("updated", yield)

        #expect(receivedValues == [1, 2])
        #expect(updatedConfigurations == ["updated"])
        #expect(observationCount == 2)
        #expect(cancellationCount == 1)

        channel.deactivate()
        #expect(cancellationCount == 2)
    }
}

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
    func readOnlyChannelErasesObservationCancellation() {
        typealias Channel = Connection<Int>.Channel

        var cancellationCount = 0
        let channel = Channel(
            valueSource: .initial(1),
            observe: { _ in "observation" },
            cancel: { observation in
                #expect(observation == "observation")
                cancellationCount += 1
            }
        )

        #expect(channel.setValue == nil)

        guard let cancellationToken = channel.observe?({ _ in }) else {
            Issue.record("The channel should expose its observation")
            return
        }

        cancellationToken.cancel()
        cancellationToken.cancel()
        #expect(cancellationCount == 1)
    }

    @Test
    func writableChannelForwardsWrites() {
        typealias Channel = Connection<Int>.Writable.Channel

        var writtenValues: [Int] = []
        let channel = Channel(
            valueSource: .initial(1),
            setValue: { writtenValues.append($0) },
            observe: { _ in () },
            cancel: { _ in }
        )

        guard let setValue = channel.setValue else {
            Issue.record("A writable channel should expose its setter")
            return
        }

        setValue(2)
        setValue(3)
        #expect(writtenValues == [2, 3])
    }

    @Test
    func cancellationTokenCancelsOnDeinitialization() {
        typealias CancellationToken = Connection<Int>.Channel.CancellationToken

        var cancellationCount = 0
        var cancellationToken: CancellationToken? = CancellationToken {
            cancellationCount += 1
        }

        #expect(cancellationToken != nil)
        cancellationToken = nil
        #expect(cancellationCount == 1)
    }

    @Test
    func currentValueSourceReadsTheLatestValueLazily() {
        var value = 1
        let source = Connection<Int>.Channel.ValueSource.current { value }

        guard case let .current(currentValue) = source else {
            Issue.record("The source should retain its current-value getter")
            return
        }

        #expect(currentValue() == 1)
        value = 2
        #expect(currentValue() == 2)
    }

    @Test
    func equatableConfigurationUsesValueEquality() {
        typealias ConfiguredConnection = Connection<Int>.Configuration<String>

        let connection = ConfiguredConnection { configuration in
            ConfiguredConnection.Channel(
                valueSource: .initial(configuration.count),
                setValue: nil,
                observe: nil,
                updateConfiguration: { _ in }
            )
        }

        #expect(connection.configurationsEqual("same", "same"))
        #expect(!connection.configurationsEqual("short", "longer"))

        let channel = connection.makeChannel("value")
        guard case let .initial(value) = channel.valueSource else {
            Issue.record("The configured connection should create the expected channel")
            return
        }
        #expect(value == 5)
    }

    @Test
    func customConfigurationEqualityAndUpdatesAreForwarded() {
        typealias ConfiguredConnection = Connection<Int>.Configuration<String>

        var comparisons: [(String, String)] = []
        var updatedConfigurations: [String] = []
        let connection = ConfiguredConnection(
            makeChannel: { _ in
                ConfiguredConnection.Channel(
                    valueSource: .initial(0),
                    setValue: nil,
                    observe: nil,
                    updateConfiguration: { updatedConfigurations.append($0) }
                )
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
        channel.updateConfiguration("updated")
        #expect(updatedConfigurations == ["updated"])
    }

    @Test
    func currentValueConveniencesCreateReadOnlyAndWritableChannels() {
        var currentValue = 1
        var writtenValues: [Int] = []

        let readOnly = Connection<Int>(
            currentValue: { currentValue },
            observe: { _ in () },
            cancel: { _ in }
        )
        let writable = Connection<Int>.Writable(
            currentValue: { currentValue },
            setValue: { writtenValues.append($0) },
            observe: { _ in () },
            cancel: { _ in }
        )

        let readOnlyChannel = readOnly.makeChannel(())
        let writableChannel = writable.makeChannel(())
        #expect(readOnlyChannel.setValue == nil)

        guard case let .current(readReadOnlyValue) = readOnlyChannel.valueSource,
              case let .current(readWritableValue) = writableChannel.valueSource,
              let setValue = writableChannel.setValue else {
            Issue.record("The convenience initializers should create current-value channels")
            return
        }

        #expect(readReadOnlyValue() == 1)
        currentValue = 2
        #expect(readReadOnlyValue() == 2)
        #expect(readWritableValue() == 2)

        setValue(3)
        #expect(writtenValues == [3])
    }
}

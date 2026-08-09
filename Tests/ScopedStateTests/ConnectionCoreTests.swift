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
    func unconfiguredConnectionCanDefineItsChannelInline() {
        var writtenValues: [Int] = []
        let connection = Connection<Int>.Writable { yield in
            yield(1)
        } setValue: {
            writtenValues.append($0)
        }
        let channel = connection.makeChannel(())

        var receivedValues: [Int] = []
        channel.activate { receivedValues.append($0) }
        channel.setValue?(2)

        #expect(receivedValues == [1])
        #expect(writtenValues == [2])
    }

    @Test
    func inlineChannelStateIsIndependentForEverySession() {
        final class Counter {
            var value = 0
        }

        let connection = Connection<Int> { [counter = Counter()] yield in
            counter.value += 1
            yield(counter.value)
        }
        let firstChannel = connection.makeChannel(())
        let secondChannel = connection.makeChannel(())

        var firstValues: [Int] = []
        var secondValues: [Int] = []
        firstChannel.activate { firstValues.append($0) }
        firstChannel.activate { firstValues.append($0) }
        secondChannel.activate { secondValues.append($0) }

        #expect(firstValues == [1, 2])
        #expect(secondValues == [1])
    }

    @Test
    func inlineWritableChannelStateIsIndependentForEverySession() {
        final class Counter {
            var value = 0
        }

        var counters: [Counter] = []
        func makeCounter() -> Counter {
            let counter = Counter()
            counters.append(counter)
            return counter
        }

        let connection = Connection<Int>.Writable { _ in
        } setValue: { [counter = makeCounter()] value in
            counter.value += value
        }
        let firstChannel = connection.makeChannel(())
        let secondChannel = connection.makeChannel(())

        firstChannel.setValue?(1)
        firstChannel.setValue?(1)
        secondChannel.setValue?(1)

        #expect(counters.count == 2)
        #expect(counters.map(\.value) == [2, 1])
    }

    @Test
    func constantProvidesAnUnobservedInitialValue() {
        let connection: Connection<Int> = .constant(42)
        let channel = connection.makeChannel(())

        #expect(connection.configurationsEqual((), ()))
        #expect(channel.setValue == nil)

        var receivedValues: [Int] = []
        let yield: Connection<Int>.Channel.YieldValue = { receivedValues.append($0) }
        channel.activate(yield)
        #expect(receivedValues == [42])

        channel.update(yield)
        #expect(receivedValues == [42])

        channel.deactivate()
    }
}

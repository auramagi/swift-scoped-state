//
//  ConnectionConcurrencyTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-10.
//

import Testing
@testable import ScopedState

@Suite("Concurrency connections")
@MainActor struct ConnectionConcurrencyTests {
    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func sequenceProvidesInitialAndSubsequentValuesAndCancelsOnDeactivation() async {
        let (updates, updatesContinuation) = AsyncStream.makeStream(of: Int.self)
        let (termination, terminationContinuation) = AsyncStream.makeStream(of: Void.self)
        updatesContinuation.onTermination = { _ in
            terminationContinuation.yield()
            terminationContinuation.finish()
        }

        let connection: Connection<Int> = .async(
            updates,
            initialValue: 1
        )
        let session = connection.makeSession(())
        let (receivedValues, receivedValuesContinuation) = AsyncStream.makeStream(of: Int.self)
        var receivedValuesIterator = receivedValues.makeAsyncIterator()

        session.activate { receivedValuesContinuation.yield($0) }
        #expect(await receivedValuesIterator.next() == 1)

        updatesContinuation.yield(2)
        #expect(await receivedValuesIterator.next() == 2)

        var terminationIterator = termination.makeAsyncIterator()
        await Task.yield()
        session.deactivate()
        #expect(await terminationIterator.next() != nil)
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func sequenceCanUseACurrentValueGetterAndMapUpdates() async {
        let (updates, updatesContinuation) = AsyncStream.makeStream(of: Int.self)
        final class CurrentValue {
            var value = 1
        }

        let currentValue = CurrentValue()
        let connection: Connection<String> = .async(
            updates,
            currentValue: { "current=\(currentValue.value)" },
            map: { "update=\($0)" }
        )
        let session = connection.makeSession(())
        let (receivedValues, receivedValuesContinuation) = AsyncStream.makeStream(of: String.self)
        var receivedValuesIterator = receivedValues.makeAsyncIterator()

        currentValue.value = 2
        session.activate { receivedValuesContinuation.yield($0) }
        #expect(await receivedValuesIterator.next() == "current=2")

        updatesContinuation.yield(3)
        #expect(await receivedValuesIterator.next() == "update=3")
        session.deactivate()
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func writableSequenceForwardsWritesToSetter() async {
        let (updates, updatesContinuation) = AsyncStream.makeStream(of: Int.self)
        var writtenValues: [Int] = []
        let connection: Connection<Int>.Writable = .async(
            updates,
            initialValue: 1,
            set: { writtenValues.append($0) }
        )
        let session = connection.makeSession(())
        let (receivedValues, receivedValuesContinuation) = AsyncStream.makeStream(of: Int.self)
        var receivedValuesIterator = receivedValues.makeAsyncIterator()

        session.activate { receivedValuesContinuation.yield($0) }
        #expect(await receivedValuesIterator.next() == 1)

        session.setValue?(2)
        #expect(writtenValues == [2])

        updatesContinuation.yield(3)
        #expect(await receivedValuesIterator.next() == 3)
        session.deactivate()
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func sequenceExpressionIsReevaluatedWheneverObservationStarts() {
        final class Source {
            var observationCount = 0

            var values: AsyncStream<Int> {
                observationCount += 1
                return AsyncStream { _ in }
            }
        }

        let source = Source()
        let connection: Connection<Int> = .async(
            source.values,
            initialValue: 1
        )
        let session = connection.makeSession(())

        session.activate { _ in }
        #expect(source.observationCount == 1)

        session.activate { _ in }
        #expect(source.observationCount == 2)
        session.deactivate()
    }
}

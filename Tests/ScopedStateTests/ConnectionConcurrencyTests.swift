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
    func sequenceProvidesInitialAndSubsequentValuesAndCancelsWithItsActivation() async {
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

        let activation = session.activate {
            if case let .value(value) = $0 {
                receivedValuesContinuation.yield(value)
            }
        }
        receivedValuesContinuation.yield(activation.initialValue)
        #expect(await receivedValuesIterator.next() == 1)

        updatesContinuation.yield(2)
        #expect(await receivedValuesIterator.next() == 2)

        var terminationIterator = termination.makeAsyncIterator()
        await Task.yield()
        activation.observation?.cancel()
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
            currentValue: { currentValue.value }
        ).map { "value=\($0)" }
        let session = connection.makeSession(())
        let (receivedValues, receivedValuesContinuation) = AsyncStream.makeStream(of: String.self)
        var receivedValuesIterator = receivedValues.makeAsyncIterator()

        currentValue.value = 2
        let activation = session.activate {
            if case let .value(value) = $0 {
                receivedValuesContinuation.yield(value)
            }
        }
        receivedValuesContinuation.yield(activation.initialValue)
        #expect(await receivedValuesIterator.next() == "value=2")

        updatesContinuation.yield(3)
        #expect(await receivedValuesIterator.next() == "value=3")
        activation.observation?.cancel()
    }

    @Test
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func writableSequenceForwardsWritesToSetter() async {
        let (updates, updatesContinuation) = AsyncStream.makeStream(of: Int.self)
        var writtenValues: [Int] = []
        let connection: Connection<Int>.Writable = .async(
            updates,
            initialValue: 1
        ).set {
            writtenValues.append($0)
        }
        let session = connection.makeSession(())
        let (receivedValues, receivedValuesContinuation) = AsyncStream.makeStream(of: Int.self)
        var receivedValuesIterator = receivedValues.makeAsyncIterator()

        let activation = session.activate {
            if case let .value(value) = $0 {
                receivedValuesContinuation.yield(value)
            }
        }
        receivedValuesContinuation.yield(activation.initialValue)
        #expect(await receivedValuesIterator.next() == 1)

        session.setValue?(2)
        #expect(writtenValues == [2])

        updatesContinuation.yield(3)
        #expect(await receivedValuesIterator.next() == 3)
        activation.observation?.cancel()
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

        let firstActivation = session.activate { _ in }
        #expect(source.observationCount == 1)

        firstActivation.observation?.cancel()
        let secondActivation = session.activate { _ in }
        #expect(source.observationCount == 2)
        secondActivation.observation?.cancel()
    }
}

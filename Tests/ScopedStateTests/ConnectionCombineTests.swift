//
//  ConnectionCombineTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-09.
//

import Combine
import Testing
@testable import ScopedState

@Suite("Combine connections")
@MainActor struct ConnectionCombineTests {
    @Test
    func readOnlySubjectProvidesCurrentAndSubsequentValues() {
        let subject = CurrentValueSubject<Int, Never>(1)
        let connection: Connection<Int> = .subject(subject)
        let channel = connection.makeChannel(())

        #expect(channel.setValue == nil)
        guard case let .current(currentValue) = channel.valueSource,
              let observe = channel.observe else {
            Issue.record("A subject should create an observed current-value channel")
            return
        }
        #expect(currentValue() == 1)

        var receivedValues: [Int] = []
        let cancellationToken = observe { receivedValues.append($0) }
        #expect(receivedValues == [1])

        subject.send(2)
        #expect(receivedValues == [1, 2])

        cancellationToken.cancel()
        subject.send(3)
        #expect(receivedValues == [1, 2])
    }

    @Test
    func writableSubjectUsesSubjectSendByDefault() {
        let subject = CurrentValueSubject<Int, Never>(1)
        let connection: Connection<Int>.Writable = .subject(subject)
        let channel = connection.makeChannel(())

        guard let setValue = channel.setValue else {
            Issue.record("A writable subject connection should expose a setter")
            return
        }

        setValue(2)
        #expect(subject.value == 2)
    }

    @Test
    func writableSubjectCanOverrideItsSetter() {
        let subject = CurrentValueSubject<Int, Never>(1)
        var writtenValues: [Int] = []
        let connection: Connection<Int>.Writable = .subject(
            subject,
            set: { writtenValues.append($0) }
        )
        let channel = connection.makeChannel(())

        guard let setValue = channel.setValue else {
            Issue.record("A writable subject connection should expose its custom setter")
            return
        }

        setValue(2)
        #expect(writtenValues == [2])
        #expect(subject.value == 1)
    }

    @Test
    func mappedSubjectMapsCurrentAndSubsequentValues() {
        let subject = CurrentValueSubject<Int, Never>(2)
        let connection: Connection<String> = .subject(
            subject,
            map: { "value=\($0)" }
        )
        let channel = connection.makeChannel(())

        guard case let .current(currentValue) = channel.valueSource,
              let observe = channel.observe else {
            Issue.record("A mapped subject should create an observed current-value channel")
            return
        }
        #expect(currentValue() == "value=2")

        var receivedValues: [String] = []
        let cancellationToken = observe { receivedValues.append($0) }
        subject.send(3)
        #expect(receivedValues == ["value=2", "value=3"])
        cancellationToken.cancel()
    }

    @Test
    func mappedWritableSubjectForwardsMappedWritesToCustomSetter() {
        let subject = CurrentValueSubject<Int, Never>(2)
        var writtenValues: [String] = []
        let connection: Connection<String>.Writable = .subject(
            subject,
            map: { "value=\($0)" },
            set: { writtenValues.append($0) }
        )
        let channel = connection.makeChannel(())

        guard let setValue = channel.setValue else {
            Issue.record("A mapped writable subject should expose its custom setter")
            return
        }

        setValue("replacement")
        #expect(writtenValues == ["replacement"])
        #expect(subject.value == 2)
    }

    @Test
    func publisherUsesInitialValueAndDeliversUpdates() {
        let publisher = PassthroughSubject<Int, Never>()
        let connection: Connection<Int> = .publisher(
            publisher,
            initialValue: 1
        )
        let channel = connection.makeChannel(())

        guard case let .initial(initialValue) = channel.valueSource,
              let observe = channel.observe else {
            Issue.record("A seeded publisher should create an observed initial-value channel")
            return
        }
        #expect(initialValue == 1)

        var receivedValues: [Int] = []
        var cancellationToken: Connection<Int>.Channel.CancellationToken? = observe {
            receivedValues.append($0)
        }
        #expect(cancellationToken != nil)

        publisher.send(2)
        #expect(receivedValues == [2])

        cancellationToken = nil
        publisher.send(3)
        #expect(receivedValues == [2])
    }

    @Test
    func writablePublisherForwardsWritesToSetter() {
        let publisher = PassthroughSubject<Int, Never>()
        var writtenValues: [Int] = []
        let connection: Connection<Int>.Writable = .publisher(
            publisher,
            initialValue: 1,
            set: { writtenValues.append($0) }
        )
        let channel = connection.makeChannel(())

        guard let setValue = channel.setValue else {
            Issue.record("A writable publisher should expose its setter")
            return
        }

        setValue(2)
        #expect(writtenValues == [2])
    }

    @Test
    func publisherCanUseASynchronousCurrentValueGetter() {
        let publisher = PassthroughSubject<Int, Never>()
        var current = 1
        let connection: Connection<Int> = .publisher(
            publisher,
            currentValue: { current }
        )
        let channel = connection.makeChannel(())

        guard case let .current(currentValue) = channel.valueSource,
              let observe = channel.observe else {
            Issue.record("A current-value publisher should retain its getter and observation")
            return
        }

        #expect(currentValue() == 1)
        current = 2
        #expect(currentValue() == 2)

        var receivedValues: [Int] = []
        let cancellationToken = observe { receivedValues.append($0) }
        publisher.send(3)
        #expect(receivedValues == [3])
        cancellationToken.cancel()
    }

    @Test
    func writableCurrentValuePublisherForwardsWrites() {
        let publisher = PassthroughSubject<Int, Never>()
        var writtenValues: [Int] = []
        let connection: Connection<Int>.Writable = .publisher(
            publisher,
            currentValue: { 1 },
            set: { writtenValues.append($0) }
        )
        let channel = connection.makeChannel(())

        guard let setValue = channel.setValue else {
            Issue.record("A writable current-value publisher should expose its setter")
            return
        }

        setValue(2)
        #expect(writtenValues == [2])
    }
}

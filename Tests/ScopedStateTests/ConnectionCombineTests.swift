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
        let session = connection.makeSession(())

        #expect(session.setValue == nil)

        var deliveredValues: [Int] = []
        let activation = session.activate { deliveredValues.append($0) }
        #expect(activation.initialValue == 1)
        #expect(deliveredValues.isEmpty)

        subject.send(2)
        #expect(deliveredValues == [2])

        activation.cancellation?.cancel()
        subject.send(3)
        #expect(deliveredValues == [2])
    }

    @Test
    func writableSubjectInfersSubjectSend() {
        let subject = CurrentValueSubject<Int, Never>(1)
        let connection: Connection<Int>.Writable = .subject(subject)
        let session = connection.makeSession(())

        let setValue = session.setValue
        #expect(setValue != nil)

        var receivedValues: [Int] = []
        let activation = session.activate { receivedValues.append($0) }
        receivedValues.append(activation.initialValue)

        setValue?(2)
        #expect(subject.value == 2)
        #expect(receivedValues == [1, 2])
        activation.cancellation?.cancel()
    }

    @Test
    func subjectCanUseACustomSetter() {
        let subject = CurrentValueSubject<Int, Never>(1)
        var writtenValues: [Int] = []
        let connection: Connection<Int>.Writable = .subject(subject).set {
            writtenValues.append($0)
        }
        let session = connection.makeSession(())

        let setValue = session.setValue
        #expect(setValue != nil)

        var receivedValues: [Int] = []
        let activation = session.activate { receivedValues.append($0) }
        receivedValues.append(activation.initialValue)

        setValue?(2)
        #expect(writtenValues == [2])
        #expect(subject.value == 1)
        #expect(receivedValues == [1])
        activation.cancellation?.cancel()
    }

    @Test
    func mappedSubjectMapsCurrentAndSubsequentValues() {
        let subject = CurrentValueSubject<Int, Never>(2)
        let connection: Connection<String> = .subject(subject).map {
            "value=\($0)"
        }
        let session = connection.makeSession(())

        var receivedValues: [String] = []
        let activation = session.activate { receivedValues.append($0) }
        receivedValues.append(activation.initialValue)
        subject.send(3)
        #expect(receivedValues == ["value=2", "value=3"])
        activation.cancellation?.cancel()
    }

    @Test
    func mappedWritableSubjectForwardsMappedWritesToCustomSetter() {
        let subject = CurrentValueSubject<Int, Never>(2)
        var writtenValues: [String] = []
        let connection: Connection<String>.Writable = .subject(subject)
            .map { "value=\($0)" }
            .set { writtenValues.append($0) }
        let session = connection.makeSession(())

        let setValue = session.setValue
        #expect(setValue != nil)

        var receivedValues: [String] = []
        let activation = session.activate { receivedValues.append($0) }
        receivedValues.append(activation.initialValue)
        subject.send(3)

        setValue?("replacement")
        #expect(writtenValues == ["replacement"])
        #expect(subject.value == 3)
        #expect(receivedValues == ["value=2", "value=3"])
        activation.cancellation?.cancel()
    }

    @Test
    func publisherUsesLatestSynchronousValueAndDeliversLaterUpdates() {
        let publisher = PassthroughSubject<Int, Never>()
        let connection: Connection<Int> = .publisher(
            publisher.prepend(2),
            initialValue: 1
        )
        let session = connection.makeSession(())

        var deliveredValues: [Int] = []
        let activation = session.activate { deliveredValues.append($0) }
        #expect(activation.initialValue == 2)
        #expect(deliveredValues.isEmpty)

        publisher.send(3)
        #expect(deliveredValues == [3])

        activation.cancellation?.cancel()
        publisher.send(4)
        #expect(deliveredValues == [3])
    }

    @Test
    func writablePublisherForwardsWritesToSetter() {
        let publisher = PassthroughSubject<Int, Never>()
        var writtenValues: [Int] = []
        let connection: Connection<Int>.Writable = .publisher(
            publisher,
            initialValue: 1
        ).set {
            writtenValues.append($0)
        }
        let session = connection.makeSession(())

        let setValue = session.setValue
        #expect(setValue != nil)

        var receivedValues: [Int] = []
        let activation = session.activate { receivedValues.append($0) }
        receivedValues.append(activation.initialValue)

        setValue?(2)
        publisher.send(3)
        #expect(writtenValues == [2])
        #expect(receivedValues == [1, 3])
        activation.cancellation?.cancel()
    }

    @Test
    func publisherCanUseASynchronousCurrentValueGetter() {
        let publisher = PassthroughSubject<Int, Never>()
        var current = 1
        let connection: Connection<Int> = .publisher(
            publisher,
            currentValue: { current }
        )
        let session = connection.makeSession(())

        current = 2

        var receivedValues: [Int] = []
        let activation = session.activate { receivedValues.append($0) }
        receivedValues.append(activation.initialValue)
        #expect(receivedValues == [2])

        current = 3
        #expect(session.update() == nil)
        #expect(receivedValues == [2])

        publisher.send(3)
        #expect(receivedValues == [2, 3])
        activation.cancellation?.cancel()
    }

    @Test
    func writableCurrentValuePublisherForwardsWrites() {
        let publisher = PassthroughSubject<Int, Never>()
        var writtenValues: [Int] = []
        let connection: Connection<Int>.Writable = .publisher(
            publisher,
            currentValue: { 1 }
        ).set {
            writtenValues.append($0)
        }
        let session = connection.makeSession(())

        let setValue = session.setValue
        #expect(setValue != nil)

        var receivedValues: [Int] = []
        let activation = session.activate { receivedValues.append($0) }
        receivedValues.append(activation.initialValue)

        setValue?(2)
        publisher.send(3)
        #expect(writtenValues == [2])
        #expect(receivedValues == [1, 3])
        activation.cancellation?.cancel()
    }
}

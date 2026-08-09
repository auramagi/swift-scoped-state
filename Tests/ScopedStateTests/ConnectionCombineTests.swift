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

        var receivedValues: [Int] = []
        channel.activate { receivedValues.append($0) }
        #expect(receivedValues == [1])

        subject.send(2)
        #expect(receivedValues == [1, 2])

        channel.deactivate()
        subject.send(3)
        #expect(receivedValues == [1, 2])
    }

    @Test
    func writableSubjectUsesSubjectSendByDefault() {
        let subject = CurrentValueSubject<Int, Never>(1)
        let connection: Connection<Int>.Writable = .subject(subject)
        let channel = connection.makeChannel(())

        let setValue = channel.setValue
        #expect(setValue != nil)

        var receivedValues: [Int] = []
        channel.activate { receivedValues.append($0) }

        setValue?(2)
        #expect(subject.value == 2)
        #expect(receivedValues == [1, 2])
        channel.deactivate()
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

        let setValue = channel.setValue
        #expect(setValue != nil)

        var receivedValues: [Int] = []
        channel.activate { receivedValues.append($0) }

        setValue?(2)
        #expect(writtenValues == [2])
        #expect(subject.value == 1)
        #expect(receivedValues == [1])
        channel.deactivate()
    }

    @Test
    func mappedSubjectMapsCurrentAndSubsequentValues() {
        let subject = CurrentValueSubject<Int, Never>(2)
        let connection: Connection<String> = .subject(
            subject,
            map: { "value=\($0)" }
        )
        let channel = connection.makeChannel(())

        var receivedValues: [String] = []
        channel.activate { receivedValues.append($0) }
        subject.send(3)
        #expect(receivedValues == ["value=2", "value=3"])
        channel.deactivate()
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

        let setValue = channel.setValue
        #expect(setValue != nil)

        var receivedValues: [String] = []
        channel.activate { receivedValues.append($0) }
        subject.send(3)

        setValue?("replacement")
        #expect(writtenValues == ["replacement"])
        #expect(subject.value == 3)
        #expect(receivedValues == ["value=2", "value=3"])
        channel.deactivate()
    }

    @Test
    func publisherUsesInitialValueAndDeliversUpdates() {
        let publisher = PassthroughSubject<Int, Never>()
        let connection: Connection<Int> = .publisher(
            publisher,
            initialValue: 1
        )
        let channel = connection.makeChannel(())

        var receivedValues: [Int] = []
        channel.activate { receivedValues.append($0) }
        #expect(receivedValues == [1])

        publisher.send(2)
        #expect(receivedValues == [1, 2])

        channel.deactivate()
        publisher.send(3)
        #expect(receivedValues == [1, 2])
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

        let setValue = channel.setValue
        #expect(setValue != nil)

        var receivedValues: [Int] = []
        channel.activate { receivedValues.append($0) }

        setValue?(2)
        publisher.send(3)
        #expect(writtenValues == [2])
        #expect(receivedValues == [1, 3])
        channel.deactivate()
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

        current = 2

        var receivedValues: [Int] = []
        channel.activate { receivedValues.append($0) }
        #expect(receivedValues == [2])

        current = 3
        channel.update { receivedValues.append($0) }
        #expect(receivedValues == [2])

        publisher.send(3)
        #expect(receivedValues == [2, 3])
        channel.deactivate()
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

        let setValue = channel.setValue
        #expect(setValue != nil)

        var receivedValues: [Int] = []
        channel.activate { receivedValues.append($0) }

        setValue?(2)
        publisher.send(3)
        #expect(writtenValues == [2])
        #expect(receivedValues == [1, 3])
        channel.deactivate()
    }
}

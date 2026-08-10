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
        typealias Session = Connection<Int>.Session

        var events: [String] = []
        let session = Session { _ in
            events.append("activate")
            return (
                initialValue: 1,
                cancellation: CancellationToken {
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
        session.reconfigure(())
        activation.cancellation?.cancel()

        #expect(events == ["activate", "refresh", "reconfigure", "cancel"])
    }

    @Test
    func writableSessionForwardsWrites() {
        typealias Session = Connection<Int>.Writable.Session

        var writtenValues: [Int] = []
        let session = Session { _ in
            (initialValue: 0, cancellation: nil)
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
}

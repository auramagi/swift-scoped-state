//
//  ConnectionObservationTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-10.
//

import Observation
import SwiftUI
import Testing
@testable import ScopedState

@Suite("Observation connections")
@MainActor struct ConnectionObservationTests {
    @Test
    func expressionInvalidatesThenRefreshesItsCurrentValue() {
        let model = Model(value: 1)
        let connection: Connection<Int> = .observation { model.value }
        let session = connection.makeSession(())

        var deliveredValues: [Int] = []
        var invalidationCount = 0
        let activation = session.activate { update in
            switch update {
            case let .value(value):
                deliveredValues.append(value)
            case .invalidate:
                invalidationCount += 1
            }
        }

        #expect(activation.initialValue == 1)
        #expect(activation.cancellation != nil)
        #expect(deliveredValues.isEmpty)
        #expect(session.refresh() == nil)

        model.value = 2

        #expect(invalidationCount == 1)
        #expect(deliveredValues.isEmpty)
        #expect(session.refresh() == 2)
        #expect(session.refresh() == nil)

        model.value = 3
        #expect(invalidationCount == 2)

        activation.cancellation?.cancel()
        model.value = 4

        #expect(invalidationCount == 2)
        #expect(session.refresh() == nil)
    }

    @Test
    func expressionTracksAllValuesItReadsAndCoalescesChanges() {
        let firstModel = Model(value: 1)
        let secondModel = Model(value: 2)
        let connection: Connection<Int> = .observation {
            firstModel.value + secondModel.value
        }
        let session = connection.makeSession(())

        var invalidationCount = 0
        let activation = session.activate {
            if case .invalidate = $0 {
                invalidationCount += 1
            }
        }
        #expect(activation.initialValue == 3)

        firstModel.value = 3
        secondModel.value = 4

        #expect(invalidationCount == 1)
        #expect(session.refresh() == 7)

        secondModel.value = 5
        #expect(invalidationCount == 2)
    }

    @Test
    func readOnlyKeyPathTracksOnlyThatProperty() {
        let model = Model(value: 1)
        let connection: Connection<Int> = .observation(model, \Model.value)
        let session = connection.makeSession(())

        var invalidationCount = 0
        let activation = session.activate {
            if case .invalidate = $0 {
                invalidationCount += 1
            }
        }

        model.unrelatedValue = 1
        #expect(invalidationCount == 0)

        model.value = 2

        #expect(activation.initialValue == 1)
        #expect(invalidationCount == 1)
        #expect(session.refresh() == 2)
    }

    @Test
    func writableKeyPathInfersPropertyMutation() {
        let model = Model(value: 1)
        let connection: Connection<Int>.Writable = .observation(model, \Model.value)
        let session = connection.makeSession(())

        var invalidationCount = 0
        let activation = session.activate {
            if case .invalidate = $0 {
                invalidationCount += 1
            }
        }
        session.setValue?(2)

        #expect(activation.initialValue == 1)
        #expect(model.value == 2)
        #expect(invalidationCount == 1)
        #expect(session.refresh() == 2)
    }

    @Test
    func expressionSupportsConnectionComposition() {
        let model = Model(value: 1)
        let connection: Connection<String>.Writable = Connection<Int>
            .observation { model.value }
            .map(String.init)
            .set { model.value = Int($0) ?? 0 }
        let session = connection.makeSession(())

        var invalidationCount = 0
        let activation = session.activate {
            if case .invalidate = $0 {
                invalidationCount += 1
            }
        }
        session.setValue?("42")

        #expect(activation.initialValue == "1")
        #expect(model.value == 42)
        #expect(invalidationCount == 1)
        #expect(session.refresh() == "42")
    }

    #if canImport(UIKit)
    @Test
    func scopedStateRefreshesOnceWithTheLatestValue() {
        let model = Model(value: 1)
        let probe = ValueProbe<Int>()
        let host = makeTestHost(
            Root(scope: Scope(value: .observation(model, \Model.value)), probe: probe)
        )

        #expect(probe.values.last == 1)
        render(host, seconds: 0.1)
        let settledValueCount = probe.values.count
        render(host, seconds: 0.1)
        #expect(probe.values.count == settledValueCount)

        let valueCountBeforeChanges = probe.values.count

        model.value = 2
        model.value = 3
        render(host)

        #expect(probe.values.last == 3)
        #expect(probe.values.count == valueCountBeforeChanges + 1)
    }

    @Test
    func observationConnectionCanProvideADerivedScope() {
        let model = Model(value: 1)
        let container = DerivedScopeContainer(model: model)
        let probe = ValueProbe<Int>()
        let host = makeTestHost(
            DerivedScopeRoot(container: container, probe: probe)
        )

        #expect(probe.values.last == 1)

        model.value = 2
        render(host, seconds: 0.1)

        #expect(probe.values.last == 2)
    }

    private struct Scope {
        let value: Connection<Int>
    }

    private struct Root: View {
        let scope: Scope

        let probe: ValueProbe<Int>

        var body: some View {
            Reader(probe: probe)
                .container(self, scope: \Root.scope)
        }
    }

    private struct Reader: View {
        @ScopedState(\Scope.value) private var value

        let probe: ValueProbe<Int>

        var body: some View {
            let _ = probe.record(value)
            Color.clear
        }
    }

    private struct ParentScope {
        let child: Connection<ChildScope>
    }

    private struct ChildScope {
        let value: Connection<Int>
    }

    @MainActor private final class DerivedScopeContainer {
        let model: Model

        init(model: Model) {
            self.model = model
        }

        var scope: ParentScope {
            ParentScope(
                child: .observation {
                    ChildScope(value: .constant(self.model.value))
                }
            )
        }
    }

    private struct DerivedScopeRoot: View {
        let container: DerivedScopeContainer

        let probe: ValueProbe<Int>

        var body: some View {
            ChildReader(probe: probe)
                .scope(\ParentScope.child)
                .container(container, scope: \DerivedScopeContainer.scope)
        }
    }

    private struct ChildReader: View {
        @ScopedState(\ChildScope.value) private var value

        let probe: ValueProbe<Int>

        var body: some View {
            let _ = probe.record(value)
            Color.clear
        }
    }
    #endif

    @MainActor @Observable final class Model {
        var value: Int

        var unrelatedValue = 0

        init(value: Int) {
            self.value = value
        }
    }
}

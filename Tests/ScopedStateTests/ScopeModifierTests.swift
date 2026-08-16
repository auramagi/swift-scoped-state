//
//  ScopeModifierTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-09.
//

#if canImport(UIKit)
import SwiftUI
import Testing
@testable import ScopedState

@Suite("Scope modifier")
@MainActor struct ScopeModifierTests {
    @Test
    func configuredScopeUpdatesItsExistingChannel() {
        let source = ConfiguredScopeSource()
        let container = Container(source: source)
        let probe = ValueProbe<Int>()
        let host = makeTestHost(
            ConfiguredRoot(
                container: container,
                configuration: 1,
                probe: probe
            )
        )

        #expect(probe.values.last == 1)
        #expect(source.createdConfigurations == [1])
        #expect(source.updatedConfigurations.isEmpty)
        #expect(source.observationCount == 1)

        host.rootView = ConfiguredRoot(
            container: container,
            configuration: 1,
            probe: probe
        )
        render(host)

        #expect(source.updatedConfigurations.isEmpty)
        #expect(source.cancellationCount == 0)
        #expect(source.observationCount == 1)

        let valueCountBeforeReconfiguration = probe.values.count
        host.rootView = ConfiguredRoot(
            container: container,
            configuration: 2,
            probe: probe
        )
        render(host)

        #expect(probe.values.last == 2)
        #expect(probe.values.count == valueCountBeforeReconfiguration + 1)
        #expect(container.scopeEvaluationCount == 1)
        #expect(source.createdConfigurations == [1])
        #expect(source.updatedConfigurations == [2])
        #expect(source.cancellationCount == 1)
        #expect(source.observationCount == 2)

        let valueCountBeforeDelivery = probe.values.count
        source.send(3)
        render(host)

        #expect(probe.values.last == 3)
        #expect(probe.values.count == valueCountBeforeDelivery + 1)
    }

    @Test
    func unconfiguredScopeOverloadProvidesItsScope() {
        let container = Container(source: ConfiguredScopeSource())
        let probe = ValueProbe<Int>()
        _ = makeTestHost(
            UnconfiguredRoot(container: container, probe: probe)
        )

        #expect(probe.values.last == 42)
        #expect(container.scopeEvaluationCount == 1)
    }

    @MainActor private struct ChildScope {
        let value: Connection<Int>
    }

    @MainActor private struct ParentScope {
        let configuredChild: ConfiguredConnection<ChildScope, Int>

        let child: Connection<ChildScope>
    }

    @MainActor private final class ConfiguredScopeSource {
        typealias ReceiveValue = @MainActor (ChildScope) -> Void

        struct Observation: Hashable {
            let id: Int
        }

        private(set) var createdConfigurations: [Int] = []

        private(set) var updatedConfigurations: [Int] = []

        private(set) var observationCount = 0

        private(set) var cancellationCount = 0

        private var currentScope = ChildScope(value: .constant(0))

        private var nextObservationID = 0

        private var observations: [Observation: ReceiveValue] = [:]

        var connection: ConfiguredConnection<ChildScope, Int> {
            .readOnly { configuration in
                self.createdConfigurations.append(configuration)
                self.currentScope = self.scope(for: configuration)

                return ConnectionSession<Int, ChildScope>(
                    currentValue: { self.currentScope },
                    observe: { self.observe($0) },
                    cancel: { self.cancel($0) },
                    reconfigure: { self.update(configuration: $0) }
                )
            }
        }

        private func scope(for configuration: Int) -> ChildScope {
            ChildScope(value: .constant(configuration))
        }

        private func observe(_ receiveValue: @escaping ReceiveValue) -> Observation {
            nextObservationID += 1
            let observation = Observation(id: nextObservationID)
            observations[observation] = receiveValue
            observationCount += 1
            return observation
        }

        private func cancel(_ observation: Observation) {
            guard observations.removeValue(forKey: observation) != nil else {
                return
            }
            cancellationCount += 1
        }

        private func update(configuration: Int) {
            updatedConfigurations.append(configuration)
            currentScope = scope(for: configuration)
            for receiveValue in observations.values {
                receiveValue(currentScope)
            }
        }

        func send(_ value: Int) {
            currentScope = scope(for: value)
            for receiveValue in observations.values {
                receiveValue(currentScope)
            }
        }
    }

    @MainActor private final class Container {
        let source: ConfiguredScopeSource

        private(set) var scopeEvaluationCount = 0

        init(source: ConfiguredScopeSource) {
            self.source = source
        }

        var scope: ParentScope {
            scopeEvaluationCount += 1
            return ParentScope(
                configuredChild: source.connection.set { _ in },
                child: .initial(ChildScope(value: .constant(42)))
            )
        }
    }

    @MainActor private struct ValueReader: View {
        @ScopedState(\ChildScope.value) private var value

        let probe: ValueProbe<Int>

        var body: some View {
            let _ = probe.record(value)
            Color.clear
        }
    }

    @MainActor private struct ConfiguredRoot: View {
        let container: Container

        let configuration: Int

        let probe: ValueProbe<Int>

        var body: some View {
            ValueReader(probe: probe)
                .scope(\ParentScope.configuredChild, configuration: configuration)
                .container(container, scope: \Container.scope)
        }
    }

    @MainActor private struct UnconfiguredRoot: View {
        let container: Container

        let probe: ValueProbe<Int>

        var body: some View {
            ValueReader(probe: probe)
                .scope(\ParentScope.child)
                .container(container, scope: \Container.scope)
        }
    }
}
#endif

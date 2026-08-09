//
//  ContainerScopeModifierTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-09.
//

#if canImport(UIKit)
import SwiftUI
import Testing
@testable import ScopedState

@Suite("Container scope modifier")
@MainActor struct ContainerScopeModifierTests {
    @Test
    func evaluatesScopeForEachContainerIdentityAndDeliversConnectedValues() {
        let source = TestValueSource(1)
        let container = Container(source: source)
        let probe = ValueProbe<Int>()
        let host = makeTestHost(
            Root(container: container, revision: 0, probe: probe)
        )

        #expect(probe.values.last == 1)
        #expect(container.scopeEvaluationCount == 1)
        #expect(source.observationCount == 1)

        source.send(2)
        render(host)

        #expect(probe.values.last == 2)

        host.rootView = Root(
            container: container,
            revision: 1,
            probe: probe
        )
        render(host)

        #expect(container.scopeEvaluationCount == 1)
        #expect(source.observationCount == 1)

        let replacementSource = TestValueSource(10)
        let replacementContainer = Container(source: replacementSource)
        host.rootView = Root(
            container: replacementContainer,
            revision: 2,
            probe: probe
        )
        render(host)

        #expect(probe.values.last == 10)
        #expect(container.scopeEvaluationCount == 1)
        #expect(replacementContainer.scopeEvaluationCount == 1)
        #expect(source.cancellationCount == 1)
        #expect(replacementSource.observationCount == 1)
    }

    @MainActor private struct Scope {
        let value: Connection<Int>
    }

    @MainActor private final class Container {
        let source: TestValueSource<Int>

        private(set) var scopeEvaluationCount = 0

        init(source: TestValueSource<Int>) {
            self.source = source
        }

        var scope: Scope {
            scopeEvaluationCount += 1
            return Scope(value: source.readOnlyConnection)
        }
    }

    @MainActor private struct ValueReader: View {
        @ScopedState(\Scope.value) private var value

        let probe: ValueProbe<Int>

        var body: some View {
            let _ = probe.record(value)
            Color.clear
        }
    }

    @MainActor private struct Root: View {
        let container: Container

        let revision: Int

        let probe: ValueProbe<Int>

        var body: some View {
            VStack {
                ValueReader(probe: probe)
                Text("Revision \(revision)")
            }
            .container(container, scope: \Container.scope)
        }
    }
}
#endif

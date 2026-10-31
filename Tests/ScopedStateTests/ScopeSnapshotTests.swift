//
//  ScopeSnapshotTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-10-31.
//

#if canImport(UIKit)
import Observation
import SwiftUI
import Testing
@testable import ScopedState

@Suite("Scope publication")
@MainActor struct ScopeSnapshotTests {
    enum Change: CaseIterable {
        case container, configuration, delivery, invalidation
    }

    @Test(arguments: Change.allCases, [false, true])
    func updatesCachedDescendantWithoutResettingLocalState(_ change: Change, nested: Bool) throws {
        let selection = Selection()
        let probe = Probe()
        let host = makeTestHost(Root(selection: selection, probe: probe, nested: nested))
        try #require(probe.values.last == .init(value: 1, local: 0))
        let local = try #require(probe.local)
        local.wrappedValue = 7
        render(host)
        try #require(probe.values.last == .init(value: 1, local: 7))
        _ = try #require(selection.container.yield)

        switch change {
        case .container:
            selection.container = Container(2)
        case .configuration:
            selection.configuration = 1
        case .delivery:
            selection.container.deliver(2)
        case .invalidation:
            selection.container.invalidate(2)
        }
        render(host)
        #expect(probe.values.last == .init(value: 2, local: 7))
    }

    enum ProviderChange: CaseIterable {
        case container, keyPath
    }

    @Test(arguments: ProviderChange.allCases)
    func changingContainerOrScopeKeyPathUpdatesCachedDescendant(_ change: ProviderChange) throws {
        let selection = KeyPathSelection()
        let probe = Probe()
        let host = makeTestHost(KeyPathRoot(selection: selection, probe: probe))
        try #require(probe.values.last == .init(value: 1, local: 0))
        let local = try #require(probe.local)
        local.wrappedValue = 7
        render(host)
        try #require(probe.values.last == .init(value: 1, local: 7))
        switch change {
        case .container:
            selection.container = DualScopeContainer(value: 2)
        case .keyPath:
            selection.keyPath = \.second
        }
        render(host)
        #expect(probe.values.last == .init(value: 2, local: 7))
    }

    @Test
    func unrelatedParentUpdatesKeepConnectionsAndDescendantsQuiet() throws {
        let selection = Selection()
        let probe = Probe()
        let host = makeTestHost(Root(selection: selection, probe: probe, nested: true))
        try #require(probe.values.last == .init(value: 1, local: 0))
        let renderCount = probe.values.count

        for revision in 1...3 {
            selection.revision = revision
            render(host)
        }

        #expect(probe.values.count == renderCount)
        #expect(selection.container.scopeEvaluations == 1)
        #expect(selection.container.activations == 1)
        #expect(selection.container.reconfigurations == 0)
        #expect(selection.container.cancellations == 0)
    }

    @Test
    func observationBackedScopeUpdatesCachedDescendant() throws {
        let model = Model()
        let probe = Probe()
        let container = ObservationContainer(model: model)
        let host = makeTestHost(
            CachedBranch(probe: probe)
                .equatable()
                .scope(\ObservationParentScope.child)
                .container(container, scope: \.scope)
        )
        try #require(probe.values.last == .init(value: 1, local: 0))
        let local = try #require(probe.local)
        local.wrappedValue = 7
        render(host)
        try #require(probe.values.last == .init(value: 1, local: 7))
        model.value = 2
        render(host)
        #expect(probe.values.last == .init(value: 2, local: 7))
    }

    fileprivate struct ChildScope {
        let value: Connection<Int>
    }

    fileprivate struct ParentScope {
        let child: ConfiguredConnection<ChildScope, Int>

        let intermediate: ConfiguredConnection<IntermediateScope, Int>
    }

    fileprivate struct IntermediateScope {
        let child: Connection<ChildScope>
    }

    fileprivate struct ObservationParentScope {
        let child: Connection<ChildScope>
    }

    @MainActor @Observable fileprivate final class Model {
        var value = 1
    }

    @MainActor fileprivate final class DualScopeContainer {
        let first: ChildScope

        let second = ChildScope(value: .constant(2))

        init(value: Int) {
            first = ChildScope(value: .constant(value))
        }
    }

    @MainActor @Observable fileprivate final class KeyPathSelection {
        var container = DualScopeContainer(value: 1)

        var keyPath: KeyPath<DualScopeContainer, ChildScope> = \.first
    }

    @MainActor fileprivate final class ObservationContainer {
        let model: Model

        init(model: Model) {
            self.model = model
        }

        var scope: ObservationParentScope {
            .init(child: .observation { ChildScope(value: .constant(self.model.value)) })
        }
    }

    @MainActor @Observable fileprivate final class Selection {
        var container = Container(1)

        var configuration = 0

        var revision = 0
    }

    @MainActor fileprivate final class Container {
        var value: Int

        var configuration = 0

        var stale = false

        var activations = 0

        var scopeEvaluations = 0

        var reconfigurations = 0

        var cancellations = 0

        var yield: ConnectionSession<Int, ChildScope>.Yield?

        init(_ value: Int) {
            self.value = value
        }

        var child: ChildScope {
            .init(value: .constant(value + configuration))
        }

        var scope: ParentScope {
            scopeEvaluations += 1
            let child: ConfiguredConnection<ChildScope, Int> = .readOnly { configuration in
                self.configuration = configuration
                return .init(
                    activate: { yield in
                        self.activations += 1
                        self.yield = yield
                        return (initialValue: self.child, observation: CancellationToken {
                            self.cancellations += 1
                            self.yield = nil
                        })
                    },
                    refresh: {
                        guard self.stale else { return nil }
                        self.stale = false
                        return self.child
                    },
                    reconfigure: {
                        self.reconfigurations += 1
                        self.configuration = $0
                    }
                )
            }
            return ParentScope(
                child: child,
                intermediate: child.map { IntermediateScope(child: .constant($0)) }
            )
        }

        func deliver(_ value: Int) {
            self.value = value
            yield?(.value(child))
        }

        func invalidate(_ value: Int) {
            stale = true
            yield?(.invalidate)
            self.value = value
        }
    }

    private struct Snapshot: Equatable {
        let value: Int

        let local: Int
    }

    @MainActor private final class Probe {
        var values: [Snapshot] = []

        var local: Binding<Int>?

        func record(value: Int, local: Int, binding: Binding<Int>) {
            values.append(.init(value: value, local: local))
            self.local = binding
        }
    }

    private struct Root: View {
        let selection: Selection

        let probe: Probe

        let nested: Bool

        var body: some View {
            VStack {
                Text("Revision \(selection.revision)")
                if nested {
                    CachedBranch(probe: probe)
                        .equatable()
                        .scope(\IntermediateScope.child)
                        .scope(\ParentScope.intermediate, configuration: selection.configuration)
                } else {
                    CachedBranch(probe: probe)
                        .equatable()
                        .scope(\ParentScope.child, configuration: selection.configuration)
                }
            }
            .container(selection.container, scope: \.scope)
        }
    }

    private struct CachedBranch: View, Equatable {
        let probe: Probe

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.probe === rhs.probe
        }

        var body: some View {
            Reader(probe: probe)
        }
    }

    private struct KeyPathRoot: View {
        let selection: KeyPathSelection

        let probe: Probe

        var body: some View {
            CachedBranch(probe: probe)
                .equatable()
                .container(selection.container, scope: selection.keyPath)
        }
    }

    private struct Reader: View {
        @ScopedState(\ChildScope.value) private var value

        @State private var local = 0

        let probe: Probe

        var body: some View {
            let _ = probe.record(value: value, local: local, binding: $local)
            Color.clear
        }
    }
}
#endif


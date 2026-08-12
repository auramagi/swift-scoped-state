//
//  ScopedStateTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-09.
//

import Combine
import Observation
import SwiftUI
import Testing
@testable import ScopedState

@Suite("Scoped state")
@MainActor struct ScopedStateTests {
    #if canImport(UIKit)
    @Test
    func writableProjectionForwardsRootReplacement() throws {
        let source = TestValueSource(1)
        let container = Container(source: source)
        let probe = BindingProbe<Int>()
        let host = makeTestHost(
            WritableRoot(container: container, probe: probe)
        )

        #expect(probe.values.last == 1)
        let binding = try #require(probe.binding)

        binding.wrappedValue = 2
        render(host)

        #expect(source.value == 2)
        #expect(source.writtenValues == [2])
        #expect(probe.values.last == 2)
    }

    @Test
    func initialValuesAreLocalToEachConnectedProperty() throws {
        let container = Container(source: TestValueSource(0))
        let firstProbe = BindingProbe<Int>()
        let secondProbe = BindingProbe<Int>()
        let host = makeTestHost(
            InitialValuesRoot(
                container: container,
                firstProbe: firstProbe,
                secondProbe: secondProbe
            )
        )

        #expect(firstProbe.values.last == 1)
        #expect(secondProbe.values.last == 1)

        let firstBinding = try #require(firstProbe.binding)
        firstBinding.wrappedValue = 2
        render(host)

        #expect(firstProbe.values.last == 2)
        #expect(secondProbe.values.last == 1)
    }

    @Test
    func readOnlyProjectionCreatesWritableMemberBindings() throws {
        let model = ScopedStateTestModel(flag: false)
        let container = Container(source: TestValueSource(0), model: model)
        let probe = ObjectProbe()
        let host = makeTestHost(
            ObjectRoot(container: container, probe: probe)
        )

        #expect(probe.models.last === model)
        #expect(probe.flags.last == false)
        let flag = try #require(probe.flag)

        flag.wrappedValue = true
        render(host)

        #expect(model.flag)
        #expect(probe.models.last === model)
        #expect(probe.flags.last == true)
    }

    @Test
    func unobservedCurrentValueRefreshesDuringViewUpdates() {
        let source = TestValueSource(1)
        let container = Container(source: source)
        let probe = ValueProbe<Int>()
        let host = makeTestHost(
            UnobservedRoot(container: container, revision: 0, probe: probe)
        )

        #expect(probe.values.last == 1)

        source.value = 2
        let valueCountBeforeRefresh = probe.values.count
        host.rootView = UnobservedRoot(
            container: container,
            revision: 1,
            probe: probe
        )
        render(host)

        #expect(probe.values.last == 2)
        #expect(probe.values.count == valueCountBeforeRefresh + 1)
        #expect(container.scopeEvaluationCount == 1)
    }

    @Test
    func observedInitialValueReceivesUpdates() {
        let container = Container(source: TestValueSource(0))
        let probe = ValueProbe<Int>()
        let host = makeTestHost(
            ObservedInitialRoot(container: container, probe: probe)
        )

        #expect(probe.values.last == 1)

        let valueCountBeforeDelivery = probe.values.count
        container.updates.send(2)
        render(host)

        #expect(probe.values.last == 2)
        #expect(probe.values.count == valueCountBeforeDelivery + 1)

        container.updates.send(2)
        render(host)

        #expect(probe.values.count == valueCountBeforeDelivery + 1)
    }

    @Test
    func removingConnectedViewCancelsItsObservation() {
        let source = TestValueSource(1)
        let container = Container(source: source)
        let probe = ValueProbe<Int>()
        let host = makeTestHost(
            ConditionalRoot(showValue: true, container: container, probe: probe)
        )

        #expect(source.observationCount == 1)
        #expect(source.cancellationCount == 0)

        host.rootView = ConditionalRoot(
            showValue: false,
            container: container,
            probe: probe
        )
        render(host)

        #expect(source.cancellationCount == 1)
    }

    @Test
    func removingConnectedViewCancelsItsActivation() {
        let source = TestValueSource(1)
        let container = Container(source: source)
        let probe = ValueProbe<Int>()
        let host = makeTestHost(
            UnobservedConditionalRoot(showValue: true, container: container, probe: probe)
        )

        #expect(source.cancellationCount == 0)

        host.rootView = UnobservedConditionalRoot(
            showValue: false,
            container: container,
            probe: probe
        )
        render(host)

        #expect(source.cancellationCount == 1)
    }

    @Suite("ObservableObject support")
    @MainActor struct ObservableObjectSupport {
        @Test
        func changesInvalidateReadOnlyConnectedValue() throws {
            let model = Model(flag: false)
            let container = ReadOnlyContainer(model: model)
            let probe = BindingProbe<Bool>()
            let host = makeTestHost(
                ReadOnlyRoot(container: container, probe: probe)
            )

            #expect(probe.values == [false])

            model.flag = true
            render(host)

            #expect(probe.values == [false, true])

            let flag = try #require(probe.binding)
            flag.wrappedValue = false
            render(host)

            #expect(probe.values == [false, true, false])
        }

        @Test
        func writableReplacementMovesObservationToNewValue() throws {
            let firstModel = EquatableModel(flag: false)
            let secondModel = EquatableModel(flag: false)
            let container = WritableContainer(model: firstModel)
            let modelProbe = BindingProbe<EquatableModel>()
            let flagProbe = BindingProbe<Bool>()
            let host = makeTestHost(
                WritableRoot(
                    container: container,
                    modelProbe: modelProbe,
                    flagProbe: flagProbe
                )
            )

            #expect(modelProbe.values.last === firstModel)
            #expect(flagProbe.values == [false])

            let model = try #require(modelProbe.binding)
            model.wrappedValue = secondModel
            render(host)

            #expect(container.subject.value === secondModel)
            #expect(modelProbe.values.last === secondModel)

            let valueCountAfterReplacement = flagProbe.values.count
            firstModel.flag = true
            render(host)

            #expect(flagProbe.values.count == valueCountAfterReplacement)

            secondModel.flag = true
            render(host)

            #expect(flagProbe.values.count == valueCountAfterReplacement + 1)
            #expect(flagProbe.values.last == true)

            let flag = try #require(flagProbe.binding)
            flag.wrappedValue = false
            render(host)

            #expect(flagProbe.values.count == valueCountAfterReplacement + 2)
            #expect(flagProbe.values.last == false)
        }

        @MainActor private final class Model: ObservableObject {
            @Published var flag: Bool

            init(flag: Bool) {
                self.flag = flag
            }
        }

        @MainActor private final class EquatableModel: ObservableObject, Equatable {
            @Published var flag: Bool

            init(flag: Bool) {
                self.flag = flag
            }

            nonisolated static func == (lhs: EquatableModel, rhs: EquatableModel) -> Bool {
                MainActor.assumeIsolated {
                    lhs.flag == rhs.flag
                }
            }
        }

        @MainActor private struct ReadOnlyScope {
            let model: Connection<Model>
        }

        @MainActor private final class ReadOnlyContainer {
            let model: Model

            init(model: Model) {
                self.model = model
            }

            var scope: ReadOnlyScope {
                ReadOnlyScope(model: .constant(model))
            }
        }

        @MainActor private struct WritableScope {
            let model: Connection<EquatableModel>.Writable
        }

        @MainActor private final class WritableContainer {
            let subject: CurrentValueSubject<EquatableModel, Never>

            init(model: EquatableModel) {
                subject = CurrentValueSubject(model)
            }

            var scope: WritableScope {
                WritableScope(model: .subject(subject))
            }
        }

        @MainActor private struct ReadOnlyReader: View {
            @ScopedState(\ReadOnlyScope.model) private var model

            let probe: BindingProbe<Bool>

            var body: some View {
                let _ = probe.record(model.flag, binding: $model.flag)
                Color.clear
            }
        }

        @MainActor private struct WritableReader: View {
            @ScopedState(\WritableScope.model) private var model

            let modelProbe: BindingProbe<EquatableModel>

            let flagProbe: BindingProbe<Bool>

            var body: some View {
                let _ = modelProbe.record(model, binding: $model)
                let _ = flagProbe.record(model.flag, binding: $model.flag)
                Color.clear
            }
        }

        @MainActor private struct ReadOnlyRoot: View {
            let container: ReadOnlyContainer

            let probe: BindingProbe<Bool>

            var body: some View {
                ReadOnlyReader(probe: probe)
                    .container(container, scope: \ReadOnlyContainer.scope)
            }
        }

        @MainActor private struct WritableRoot: View {
            let container: WritableContainer

            let modelProbe: BindingProbe<EquatableModel>

            let flagProbe: BindingProbe<Bool>

            var body: some View {
                WritableReader(
                    modelProbe: modelProbe,
                    flagProbe: flagProbe
                )
                .container(container, scope: \WritableContainer.scope)
            }
        }
    }

    @MainActor private struct Scope {
        let value: Connection<Int>

        let writableValue: Connection<Int>.Writable

        let initialValue: Connection<Int>.Writable

        let unobservedValue: Connection<Int>

        let observedInitialValue: Connection<Int>

        let model: Connection<ScopedStateTestModel>
    }

    @MainActor private final class Container {
        let source: TestValueSource<Int>

        let model: ScopedStateTestModel

        let updates = PassthroughSubject<Int, Never>()

        private(set) var scopeEvaluationCount = 0

        init(
            source: TestValueSource<Int>,
            model: ScopedStateTestModel = ScopedStateTestModel(flag: false)
        ) {
            self.source = source
            self.model = model
        }

        var scope: Scope {
            scopeEvaluationCount += 1
            return Scope(
                value: source.readOnlyConnection,
                writableValue: source.writableConnection,
                initialValue: .initial(1),
                unobservedValue: source.unobservedConnection,
                observedInitialValue: .publisher(updates, initialValue: 1),
                model: .constant(model)
            )
        }
    }

    @MainActor private final class ObjectProbe {
        private(set) var models: [ScopedStateTestModel] = []

        private(set) var flags: [Bool] = []

        var flag: Binding<Bool>?

        func record(_ model: ScopedStateTestModel, flag: Binding<Bool>) {
            models.append(model)
            flags.append(model.flag)
            self.flag = flag
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

    @MainActor private struct WritableValueReader: View {
        @ScopedState(\Scope.writableValue) private var value

        let probe: BindingProbe<Int>

        var body: some View {
            let _ = probe.record(value, binding: $value)
            Color.clear
        }
    }

    @MainActor private struct InitialValueReader: View {
        @ScopedState(\Scope.initialValue) private var value

        let probe: BindingProbe<Int>

        var body: some View {
            let _ = probe.record(value, binding: $value)
            Color.clear
        }
    }

    @MainActor private struct ObjectReader: View {
        @ScopedState(\Scope.model) private var model

        let probe: ObjectProbe

        var body: some View {
            let _ = probe.record(model, flag: $model.flag)
            Color.clear
        }
    }

    @MainActor private struct UnobservedValueReader: View {
        @ScopedState(\Scope.unobservedValue) private var value

        let probe: ValueProbe<Int>

        var body: some View {
            let _ = probe.record(value)
            Color.clear
        }
    }

    @MainActor private struct ObservedInitialValueReader: View {
        @ScopedState(\Scope.observedInitialValue) private var value

        let probe: ValueProbe<Int>

        var body: some View {
            let _ = probe.record(value)
            Color.clear
        }
    }

    @MainActor private struct WritableRoot: View {
        let container: Container

        let probe: BindingProbe<Int>

        var body: some View {
            WritableValueReader(probe: probe)
                .container(container, scope: \Container.scope)
        }
    }

    @MainActor private struct InitialValuesRoot: View {
        let container: Container

        let firstProbe: BindingProbe<Int>

        let secondProbe: BindingProbe<Int>

        var body: some View {
            VStack {
                InitialValueReader(probe: firstProbe)
                InitialValueReader(probe: secondProbe)
            }
            .container(container, scope: \Container.scope)
        }
    }

    @MainActor private struct ObjectRoot: View {
        let container: Container

        let probe: ObjectProbe

        var body: some View {
            ObjectReader(probe: probe)
                .container(container, scope: \Container.scope)
        }
    }

    @MainActor private struct UnobservedRoot: View {
        let container: Container

        let revision: Int

        let probe: ValueProbe<Int>

        var body: some View {
            VStack {
                UnobservedValueReader(probe: probe)
                Text("Revision \(revision)")
            }
            .container(container, scope: \Container.scope)
        }
    }

    @MainActor private struct ObservedInitialRoot: View {
        let container: Container

        let probe: ValueProbe<Int>

        var body: some View {
            ObservedInitialValueReader(probe: probe)
                .container(container, scope: \Container.scope)
        }
    }

    @MainActor private struct ConditionalRoot: View {
        let showValue: Bool

        let container: Container

        let probe: ValueProbe<Int>

        @ViewBuilder var body: some View {
            Group {
                if showValue {
                    ValueReader(probe: probe)
                }
            }
            .container(container, scope: \Container.scope)
        }
    }

    @MainActor private struct UnobservedConditionalRoot: View {
        let showValue: Bool

        let container: Container

        let probe: ValueProbe<Int>

        @ViewBuilder var body: some View {
            Group {
                if showValue {
                    UnobservedValueReader(probe: probe)
                }
            }
            .container(container, scope: \Container.scope)
        }
    }
    #endif

    #if os(macOS)
    @Test
    func writingProjectionBeforeUpdateFails() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let state = ScopedState<ExitScope, Void, WritableConnectedValue<Int>>(\.value)
                state.projectedValue.wrappedValue = 1
            }
        }
    }

    @MainActor private struct ExitScope {
        let value: Connection<Int>.Writable
    }
    #endif
}

#if canImport(UIKit)
@MainActor @Observable private final class ScopedStateTestModel {
    var flag: Bool

    init(flag: Bool) {
        self.flag = flag
    }
}
#endif

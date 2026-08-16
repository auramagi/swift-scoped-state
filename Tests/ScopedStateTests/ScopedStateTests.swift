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
    func writableConnectionCanBeConsumedAsReadOnly() {
        let source = TestValueSource(1)
        let container = Container(source: source)
        let probe = ValueProbe<Int>()
        let host = makeTestHost(
            ReadOnlyWritableRoot(container: container, probe: probe)
        )

        #expect(probe.values.last == 1)

        source.send(2)
        render(host)

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
    func readOnlyProjectionDoesNotForwardRootReplacement() throws {
        let model = ScopedStateTestModel(flag: false)
        let container = Container(source: TestValueSource(0), model: model)
        let probe = ObjectProbe()
        let host = makeTestHost(
            ReadOnlyWritableObjectReader(probe: probe)
                .container(container, scope: \Container.scope)
        )

        let flag = try #require(probe.flag)
        flag.wrappedValue = true
        render(host)

        #expect(model.flag)
        #expect(container.modelSource.writtenValues.isEmpty)
        #expect(probe.flags.last == true)
    }

    @Test
    func readOnlyProjectionSupportsNonmutatingMembers() throws {
        let model = ScopedStateTestModel(flag: false)
        let container = Container(source: TestValueSource(0), model: model)
        let probe = BindingProbe<Bool>()
        let host = makeTestHost(
            ControlsReader(probe: probe)
                .container(container, scope: \Container.scope)
        )

        let flag = try #require(probe.binding)
        flag.wrappedValue = true
        render(host)

        #expect(model.flag)
        #expect(probe.values.last == true)
    }

    @Test
    func writableProjectionSupportsDerivedBindings() throws {
        let container = Container(source: TestValueSource(0))
        let probe = BindingProbe<Bool>()
        let host = makeTestHost(
            InvertedFlagReader(probe: probe)
                .container(container, scope: \Container.scope)
        )

        #expect(probe.values.last == true)
        let invertedFlag = try #require(probe.binding)
        invertedFlag.wrappedValue = false
        render(host)

        #expect(container.flagSource.value)
        #expect(container.flagSource.writtenValues == [true])
        #expect(probe.values.last == false)
    }

    @Test
    func configuredWritableLeafForwardsRootReplacement() throws {
        let container = Container(source: TestValueSource(0))
        let probe = BindingProbe<Int>()
        let host = makeTestHost(
            ConfiguredValueReader(probe: probe)
                .container(container, scope: \Container.scope)
        )

        #expect(probe.values.last == 7)
        let value = try #require(probe.binding)
        value.wrappedValue = 8
        render(host)

        #expect(container.configuredSource.writtenValues == [8])
        #expect(probe.values.last == 8)
    }

    @Test
    func changingKeyPathReplacesTheActiveConnection() {
        let source = TestValueSource(1)
        let container = Container(source: source)
        let probe = ValueProbe<Int>()
        let host = makeTestHost(
            SelectedValueRoot(
                container: container,
                keyPath: \Scope.value,
                probe: probe
            )
        )

        #expect(probe.values.last == 1)
        #expect(source.observationCount == 1)

        host.rootView = SelectedValueRoot(
            container: container,
            keyPath: \Scope.secondValue,
            probe: probe
        )
        render(host)

        #expect(probe.values.last == 10)
        #expect(source.cancellationCount == 1)
        #expect(container.secondSource.observationCount == 1)
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

    @MainActor private struct Scope {
        let value: Connection<Int>

        let secondValue: Connection<Int>

        let writableValue: WritableConnection<Int>

        let writableFlag: WritableConnection<Bool>

        let readOnlyWritableValue: Connection<Int>

        let readOnlyWritableModel: Connection<ScopedStateTestModel>

        let initialValue: WritableConnection<Int>

        let unobservedValue: Connection<Int>

        let observedInitialValue: Connection<Int>

        let model: Connection<ScopedStateTestModel>

        let controls: Connection<NonmutatingControls>

        let configuredValue: WritableConfiguredConnection<Int, Int>
    }

    @MainActor private final class Container {
        let source: TestValueSource<Int>

        let secondSource = TestValueSource(10)

        let flagSource = TestValueSource(false)

        let model: ScopedStateTestModel

        let modelSource: TestValueSource<ScopedStateTestModel>

        let configuredSource = ConfiguredValueSource()

        let updates = PassthroughSubject<Int, Never>()

        private(set) var scopeEvaluationCount = 0

        init(
            source: TestValueSource<Int>,
            model: ScopedStateTestModel = ScopedStateTestModel(flag: false)
        ) {
            self.source = source
            self.model = model
            self.modelSource = TestValueSource(model)
        }

        var scope: Scope {
            scopeEvaluationCount += 1
            return Scope(
                value: source.readOnlyConnection,
                secondValue: secondSource.readOnlyConnection,
                writableValue: source.writableConnection,
                writableFlag: flagSource.writableConnection,
                readOnlyWritableValue: source.writableConnection,
                readOnlyWritableModel: modelSource.writableConnection,
                initialValue: .initial(1),
                unobservedValue: source.unobservedConnection,
                observedInitialValue: .publisher(updates, initialValue: 1),
                model: .constant(model),
                controls: .constant(NonmutatingControls(model: model)),
                configuredValue: configuredSource.connection
            )
        }
    }

    @MainActor private final class ConfiguredValueSource {
        private(set) var writtenValues: [Int] = []

        private var yield: ConnectionSession<Int, Int>.Yield?

        var connection: WritableConfiguredConnection<Int, Int> {
            .readWrite { configuration in
                ConnectionSession { yield in
                    self.yield = yield
                    return (initialValue: configuration, observation: nil)
                } reconfigure: { _ in
                } setValue: {
                    self.writtenValues.append($0)
                    self.yield?(.value($0))
                }
            }
        }
    }

    @MainActor private struct NonmutatingControls {
        let model: ScopedStateTestModel

        var flag: Bool {
            get { model.flag }
            nonmutating set { model.flag = newValue }
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

    @MainActor private struct ReadOnlyWritableValueReader: View {
        @ScopedState(\Scope.readOnlyWritableValue) private var value

        let probe: ValueProbe<Int>

        var body: some View {
            let _: ScopedStateProjection<Int> = $value
            let _ = probe.record(value)
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

    @MainActor private struct ReadOnlyWritableObjectReader: View {
        @ScopedState(\Scope.readOnlyWritableModel) private var model

        let probe: ObjectProbe

        var body: some View {
            let _ = probe.record(model, flag: $model.flag)
            Color.clear
        }
    }

    @MainActor private struct ControlsReader: View {
        @ScopedState(\Scope.controls) private var controls

        let probe: BindingProbe<Bool>

        var body: some View {
            let _ = probe.record(controls.flag, binding: $controls.flag)
            Color.clear
        }
    }

    @MainActor private struct InvertedFlagReader: View {
        @ScopedState(\Scope.writableFlag) private var flag

        let probe: BindingProbe<Bool>

        var body: some View {
            let _ = probe.record(flag.inverted, binding: $flag.inverted)
            Color.clear
        }
    }

    @MainActor private struct ConfiguredValueReader: View {
        @ScopedState(\Scope.configuredValue, configuration: 7) private var value

        let probe: BindingProbe<Int>

        var body: some View {
            let _ = probe.record(value, binding: $value)
            Color.clear
        }
    }

    @MainActor private struct SelectedValueReader: View {
        @ScopedState<Scope, EmptyConfiguration, Int, ReadOnlyValueProjection<Int>> private var value: Int

        let probe: ValueProbe<Int>

        init(
            keyPath: KeyPath<Scope, Connection<Int>>,
            probe: ValueProbe<Int>
        ) {
            self._value = ScopedState(keyPath)
            self.probe = probe
        }

        var body: some View {
            let _ = probe.record(value)
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

    @MainActor private struct ReadOnlyWritableRoot: View {
        let container: Container

        let probe: ValueProbe<Int>

        var body: some View {
            ReadOnlyWritableValueReader(probe: probe)
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

    @MainActor private struct SelectedValueRoot: View {
        let container: Container

        let keyPath: KeyPath<Scope, Connection<Int>>

        let probe: ValueProbe<Int>

        var body: some View {
            SelectedValueReader(keyPath: keyPath, probe: probe)
                .container(container, scope: \Container.scope)
        }
    }
    #endif

    #if os(macOS)
    @Test
    func writingProjectionBeforeUpdateFails() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let state = ScopedState<ExitScope, EmptyConfiguration, Int, ReadWriteValueProjection<Int>>(\.value)
                state.projectedValue.wrappedValue = 1
            }
        }
    }

    @MainActor private struct ExitScope {
        let value: WritableConnection<Int>
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

private extension Bool {
    var inverted: Bool {
        get { !self }
        set { self = !newValue }
    }
}
#endif

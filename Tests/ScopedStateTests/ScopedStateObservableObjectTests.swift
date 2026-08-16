//
//  ScopedStateObservableObjectTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-12.
//

import Combine
import SwiftUI
import Testing
@testable import ScopedState

#if canImport(UIKit)
@Suite("Scoped state ObservableObject support")
@MainActor struct ScopedStateObservableObjectTests {
    @Test
    func changesInvalidateReadOnlyValue() throws {
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
#endif

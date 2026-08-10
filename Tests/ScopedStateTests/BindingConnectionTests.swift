//
//  BindingConnectionTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-10.
//

#if canImport(UIKit)
import SwiftUI
import Testing
@testable import ScopedState

@Suite("Binding connections")
@MainActor struct BindingConnectionTests {
    @Test
    func viewContainerPropagatesStateChangesInBothDirections() throws {
        let sourceProbe = BindingProbe<Bool>()
        let readOnlyProbe = ValueProbe<Bool>()
        let writableProbe = BindingProbe<Bool>()
        let host = makeTestHost(
            Root(
                sourceProbe: sourceProbe,
                readOnlyProbe: readOnlyProbe,
                writableProbe: writableProbe
            )
        )

        #expect(readOnlyProbe.values.last == false)
        #expect(writableProbe.values.last == false)

        render(host, seconds: 0.1)
        let settledReadOnlyCount = readOnlyProbe.values.count
        let settledWritableCount = writableProbe.values.count
        render(host, seconds: 0.1)

        #expect(readOnlyProbe.values.count == settledReadOnlyCount)
        #expect(writableProbe.values.count == settledWritableCount)

        let source = try #require(sourceProbe.binding)
        #expect(source.wrappedValue == false)
        source.wrappedValue = true
        render(host)

        #expect(readOnlyProbe.values.last == true)
        #expect(writableProbe.values.last == true)

        let writable = try #require(writableProbe.binding)
        writable.wrappedValue = false
        render(host)

        #expect(source.wrappedValue == false)
        #expect(readOnlyProbe.values.last == false)
        #expect(writableProbe.values.last == false)
    }

    @MainActor private struct Scope {
        let readOnlyValue: Connection<Bool>

        let writableValue: Connection<Bool>.Writable
    }

    @MainActor private struct Reader: View {
        @ScopedState(\Scope.readOnlyValue) private var readOnlyValue

        @ScopedState(\Scope.writableValue) private var writableValue

        let readOnlyProbe: ValueProbe<Bool>

        let writableProbe: BindingProbe<Bool>

        var body: some View {
            let _ = readOnlyProbe.record(readOnlyValue)
            let _ = writableProbe.record(writableValue, binding: $writableValue)
            Color.clear
        }
    }

    @MainActor private struct Root: View {
        @State private var value = false

        let sourceProbe: BindingProbe<Bool>

        let readOnlyProbe: ValueProbe<Bool>

        let writableProbe: BindingProbe<Bool>

        private var scope: Scope {
            Scope(
                readOnlyValue: .binding($value),
                writableValue: .binding($value)
            )
        }

        var body: some View {
            let _ = sourceProbe.record($value)
            Reader(
                readOnlyProbe: readOnlyProbe,
                writableProbe: writableProbe
            )
            .container(self, scope: \Root.scope)
        }
    }
}
#endif

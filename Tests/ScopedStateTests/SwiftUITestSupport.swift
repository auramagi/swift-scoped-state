//
//  SwiftUITestSupport.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-09.
//

#if canImport(UIKit)
import SwiftUI
import UIKit
@testable import ScopedState

@MainActor func makeTestHost<Content: View>(_ content: Content) -> UIHostingController<Content> {
    let host = UIHostingController(rootView: content)
    render(host)
    return host
}

@MainActor func render<Content>(
    _ host: UIHostingController<Content>,
    seconds: TimeInterval = 0
) {
    host._render(seconds: seconds)
}

@MainActor final class TestValueSource<Value> {
    typealias ReceiveValue = @MainActor (Value) -> Void

    struct Observation: Hashable {
        let id: Int
    }

    var value: Value

    private(set) var observationCount = 0

    private(set) var cancellationCount = 0

    private(set) var deactivationCount = 0

    private(set) var writtenValues: [Value] = []

    private var nextObservationID = 0

    private var observations: [Observation: ReceiveValue] = [:]

    init(_ value: Value) {
        self.value = value
    }

    var readOnlyConnection: Connection<Value> {
        Connection(
            currentValue: { self.value },
            observe: { self.observe($0) },
            cancel: { self.cancel($0) }
        )
    }

    var writableConnection: Connection<Value>.Writable {
        Connection(
            currentValue: { self.value },
            observe: { self.observe($0) },
            cancel: { self.cancel($0) }
        ).set {
            self.writtenValues.append($0)
            self.send($0)
        }
    }

    var unobservedConnection: Connection<Value> {
        Connection { yield in
            yield(self.value)
        } update: { yield in
            yield(self.value)
        } deactivate: {
            self.deactivationCount += 1
        }
    }

    func send(_ value: Value) {
        self.value = value
        for receiveValue in observations.values {
            receiveValue(value)
        }
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
}

@MainActor final class ValueProbe<Value> {
    private(set) var values: [Value] = []

    func record(_ value: Value) {
        values.append(value)
    }
}

@MainActor final class BindingProbe<Value> {
    private(set) var values: [Value] = []

    var binding: Binding<Value>?

    func record(_ value: Value, binding: Binding<Value>) {
        values.append(value)
        self.binding = binding
    }

    func record(_ binding: Binding<Value>) {
        self.binding = binding
    }
}
#endif

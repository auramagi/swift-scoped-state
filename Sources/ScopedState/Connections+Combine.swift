//
//  Connections+Combine.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-09.
//

import Combine

extension ConnectionDefinition where Self == Connections {
    /// Creates a writable connection to a current-value subject.
    public static func subject<WrappedValue>(
        _ subject: CurrentValueSubject<WrappedValue, Never>
    ) -> some WritableConnectionDefinition<EmptyConfiguration, WrappedValue> {
        let connection = ReadOnlyConnectionDefinition { _ in
            .init(
                currentValue: { subject.value },
                observe: { subject.sink(receiveValue: $0) },
                cancel: { $0.cancel() }
            )
        }
        return connection.set { subject.send($0) }
    }

    /// Creates a read-only connection that starts with an initial value and
    /// then receives values from a publisher.
    public static func publisher<Updates: Publisher, WrappedValue>(
        _ publisher: Updates,
        initialValue: WrappedValue
    ) -> some ConnectionDefinition<EmptyConfiguration, WrappedValue> where Updates.Output == WrappedValue, Updates.Failure == Never {
        ReadOnlyConnectionDefinition { _ in
            .init(
                initialValue: initialValue,
                observe: { publisher.sink(receiveValue: $0) },
                cancel: { $0.cancel() }
            )
        }
    }

    /// Creates a read-only connection backed by a publisher and a synchronous
    /// current-value getter.
    public static func publisher<Updates: Publisher, WrappedValue>(
        _ publisher: Updates,
        currentValue: @escaping () -> WrappedValue
    ) -> some ConnectionDefinition<EmptyConfiguration, WrappedValue> where Updates.Output == WrappedValue, Updates.Failure == Never {
        ReadOnlyConnectionDefinition { _ in
            .init(
                currentValue: currentValue,
                observe: { publisher.sink(receiveValue: $0) },
                cancel: { $0.cancel() }
            )
        }
    }
}

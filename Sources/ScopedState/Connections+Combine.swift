//
//  Connections+Combine.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-09.
//

import Combine

extension ConnectionDefinition where Self == Connections {
    /// Creates a writable connection to a current-value subject.
    ///
    /// The subject updates connected properties. Writes through a property's
    /// binding call the subject's `send` method.
    ///
    /// - Parameter subject: The subject that supplies and receives values.
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

    /// Creates a read-only publisher connection with an initial value.
    ///
    /// - Parameters:
    ///   - publisher: The publisher that delivers later values.
    ///   - initialValue: The value to use until the publisher emits a value.
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

    /// Creates a read-only publisher connection with a current-value getter.
    ///
    /// - Parameters:
    ///   - publisher: The publisher that delivers later values.
    ///   - currentValue: A closure that synchronously reads the latest value.
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

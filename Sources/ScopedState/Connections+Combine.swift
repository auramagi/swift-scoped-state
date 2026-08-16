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
    /// Values sent by the subject update connected properties, and values
    /// written through the connection are sent back to the subject.
    ///
    /// - Parameter subject: The subject that supplies and receives values.
    /// - Returns: A writable Combine-backed connection definition.
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
    ///
    /// - Parameters:
    ///   - publisher: The publisher that delivers later values.
    ///   - initialValue: The value available before the publisher delivers.
    /// - Returns: A read-only Combine-backed connection definition.
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
    ///
    /// - Parameters:
    ///   - publisher: The publisher that delivers later values.
    ///   - currentValue: A closure that synchronously reads the latest value.
    /// - Returns: A read-only Combine-backed connection definition.
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

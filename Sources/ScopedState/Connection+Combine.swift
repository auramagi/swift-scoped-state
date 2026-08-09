//
//  Connection+Combine.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-09.
//

import Combine

private extension GenericConnection.Session {
    static func observing(
        activate: @escaping @MainActor (@escaping YieldValue) -> AnyCancellable
    ) -> Self {
        var cancellation: AnyCancellable?

        return Self(
            activate: { yield in
                cancellation?.cancel()
                cancellation = activate(yield)
            },
            update: { _ in },
            reconfigure: { _, _ in },
            deactivate: {
                cancellation?.cancel()
                cancellation = nil
            },
            setValue: nil
        )
    }

    static func subject(
        _ subject: CurrentValueSubject<Connected.WrappedValue, Never>
    ) -> Self {
        Self.observing(
            activate: { yield in
                subject.sink(receiveValue: yield)
            }
        )
    }

    static func publisher<Updates: Publisher>(
        initialValue: Connected.WrappedValue,
        updates: Updates
    ) -> Self where Updates.Output == Connected.WrappedValue, Updates.Failure == Never {
        Self.observing(
            activate: { yield in
                yield(initialValue)
                return updates.sink(receiveValue: yield)
            }
        )
    }

    static func publisher<Updates: Publisher>(
        currentValue: @escaping @MainActor () -> Connected.WrappedValue,
        updates: Updates
    ) -> Self where Updates.Output == Connected.WrappedValue, Updates.Failure == Never {
        Self.observing(
            activate: { yield in
                let cancellation = updates.sink(receiveValue: yield)
                yield(currentValue())
                return cancellation
            }
        )
    }
}

extension GenericConnection where Configuration == Void {
    /// Creates a read-only connection to a current-value subject.
    public static func subject<WrappedValue>(
        _ subject: CurrentValueSubject<WrappedValue, Never>
    ) -> Connection<WrappedValue> {
        Connection<WrappedValue> {
            Connection<WrappedValue>.Session.subject(subject)
        }
    }

    /// Creates a writable connection to a current-value subject.
    public static func subject<WrappedValue>(
        _ subject: CurrentValueSubject<WrappedValue, Never>
    ) -> Connection<WrappedValue>.Writable {
        let connection: Connection<WrappedValue> = .subject(subject)
        return connection.set { subject.send($0) }
    }

    /// Creates a read-only connection that starts with an initial value and
    /// then receives values from a publisher.
    public static func publisher<Updates: Publisher, WrappedValue>(
        _ publisher: Updates,
        initialValue: WrappedValue
    ) -> Connection<WrappedValue> where Updates.Output == WrappedValue, Updates.Failure == Never {
        Connection<WrappedValue> {
            Connection<WrappedValue>.Session.publisher(
                initialValue: initialValue,
                updates: publisher
            )
        }
    }

    /// Creates a read-only connection backed by a publisher and a synchronous
    /// current-value getter.
    public static func publisher<Updates: Publisher, WrappedValue>(
        _ publisher: Updates,
        currentValue: @escaping @MainActor () -> WrappedValue
    ) -> Connection<WrappedValue> where Updates.Output == WrappedValue, Updates.Failure == Never {
        Connection<WrappedValue> {
            Connection<WrappedValue>.Session.publisher(
                currentValue: currentValue,
                updates: publisher
            )
        }
    }
}

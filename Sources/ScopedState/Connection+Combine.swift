//
//  Connection+Combine.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-09.
//

import Combine

private extension GenericConnection.Channel {
    static func observing(
        activate: @escaping @MainActor (@escaping YieldValue) -> AnyCancellable,
        setValue: SetValue?
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
            setValue: setValue
        )
    }

    static func subject<SubjectValue>(
        subject: CurrentValueSubject<SubjectValue, Never>,
        map: @escaping @MainActor (SubjectValue) -> Connected.WrappedValue,
        setValue: (@MainActor (Connected.WrappedValue) -> Void)?
    ) -> Self {
        Self.observing(
            activate: { yield in
                subject.sink { value in
                    yield(map(value))
                }
            },
            setValue: setValue
        )
    }

    static func publisher<Updates: Publisher>(
        initialValue: Connected.WrappedValue,
        updates: Updates,
        map: @escaping @MainActor (Updates.Output) -> Connected.WrappedValue,
        setValue: (@MainActor (Connected.WrappedValue) -> Void)?
    ) -> Self where Updates.Failure == Never {
        Self.observing(
            activate: { yield in
                yield(initialValue)
                return updates.sink { value in
                    yield(map(value))
                }
            },
            setValue: setValue
        )
    }

    static func publisher<Updates: Publisher>(
        currentValue: @escaping @MainActor () -> Connected.WrappedValue,
        updates: Updates,
        map: @escaping @MainActor (Updates.Output) -> Connected.WrappedValue,
        setValue: (@MainActor (Connected.WrappedValue) -> Void)?
    ) -> Self where Updates.Failure == Never {
        Self.observing(
            activate: { yield in
                let cancellation = updates.sink { value in
                    yield(map(value))
                }
                yield(currentValue())
                return cancellation
            },
            setValue: setValue
        )
    }
}

extension GenericConnection where Configuration == Void {
    /// Creates a read-only connection to a current-value subject.
    public static func subject<WrappedValue>(
        _ subject: CurrentValueSubject<WrappedValue, Never>
    ) -> Self where Connected == ReadOnlyConnectedValue<WrappedValue> {
        Self {
            Channel.subject(
                subject: subject,
                map: { $0 },
                setValue: nil
            )
        }
    }

    /// Creates a writable connection to a current-value subject.
    public static func subject<WrappedValue>(
        _ subject: CurrentValueSubject<WrappedValue, Never>
    ) -> Self where Connected == WritableConnectedValue<WrappedValue> {
        Self {
            Channel.subject(
                subject: subject,
                map: { $0 },
                setValue: { subject.send($0) }
            )
        }
    }

    /// Creates a writable connection that observes a current-value subject
    /// while forwarding writes to a custom setter.
    public static func subject<WrappedValue>(
        _ subject: CurrentValueSubject<WrappedValue, Never>,
        set: @escaping @MainActor (WrappedValue) -> Void
    ) -> Self where Connected == WritableConnectedValue<WrappedValue> {
        Self {
            Channel.subject(
                subject: subject,
                map: { $0 },
                setValue: set
            )
        }
    }

    /// Creates a read-only connection by mapping a current-value subject.
    public static func subject<SubjectValue, WrappedValue>(
        _ subject: CurrentValueSubject<SubjectValue, Never>,
        map: @escaping @MainActor (SubjectValue) -> WrappedValue
    ) -> Self where Connected == ReadOnlyConnectedValue<WrappedValue> {
        Self {
            Channel.subject(
                subject: subject,
                map: map,
                setValue: nil
            )
        }
    }

    /// Creates a writable connection by mapping a current-value subject while
    /// forwarding writes to a custom setter.
    public static func subject<SubjectValue, WrappedValue>(
        _ subject: CurrentValueSubject<SubjectValue, Never>,
        map: @escaping @MainActor (SubjectValue) -> WrappedValue,
        set: @escaping @MainActor (WrappedValue) -> Void
    ) -> Self where Connected == WritableConnectedValue<WrappedValue> {
        Self {
            Channel.subject(
                subject: subject,
                map: map,
                setValue: set
            )
        }
    }

    /// Creates a read-only connection that starts with an initial value and
    /// then receives values from a publisher.
    public static func publisher<Updates: Publisher, WrappedValue>(
        _ publisher: Updates,
        initialValue: WrappedValue
    ) -> Self where Updates.Output == WrappedValue, Updates.Failure == Never, Connected == ReadOnlyConnectedValue<WrappedValue> {
        Self {
            Channel.publisher(
                initialValue: initialValue,
                updates: publisher,
                map: { $0 },
                setValue: nil
            )
        }
    }

    /// Creates a writable connection that starts with an initial value,
    /// receives values from a publisher, and forwards writes to a setter.
    public static func publisher<Updates: Publisher, WrappedValue>(
        _ publisher: Updates,
        initialValue: WrappedValue,
        set: @escaping @MainActor (WrappedValue) -> Void
    ) -> Self where Updates.Output == WrappedValue, Updates.Failure == Never, Connected == WritableConnectedValue<WrappedValue> {
        Self {
            Channel.publisher(
                initialValue: initialValue,
                updates: publisher,
                map: { $0 },
                setValue: set
            )
        }
    }

    /// Creates a read-only connection backed by a publisher and a synchronous
    /// current-value getter.
    public static func publisher<Updates: Publisher, WrappedValue>(
        _ publisher: Updates,
        currentValue: @escaping @MainActor () -> WrappedValue
    ) -> Self where Updates.Output == WrappedValue, Updates.Failure == Never, Connected == ReadOnlyConnectedValue<WrappedValue> {
        Self {
            Channel.publisher(
                currentValue: currentValue,
                updates: publisher,
                map: { $0 },
                setValue: nil
            )
        }
    }

    /// Creates a writable connection backed by a publisher, a synchronous
    /// current-value getter, and a setter.
    public static func publisher<Updates: Publisher, WrappedValue>(
        _ publisher: Updates,
        currentValue: @escaping @MainActor () -> WrappedValue,
        set: @escaping @MainActor (WrappedValue) -> Void
    ) -> Self where Updates.Output == WrappedValue, Updates.Failure == Never, Connected == WritableConnectedValue<WrappedValue> {
        Self {
            Channel.publisher(
                currentValue: currentValue,
                updates: publisher,
                map: { $0 },
                setValue: set
            )
        }
    }
}

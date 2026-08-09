//
//  Connection+Concurrency.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-10.
//

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@MainActor private func observe<Updates: AsyncSequence, Value>(
    _ updates: Updates,
    map: @escaping @MainActor (Updates.Element) -> Value,
    yield: @escaping @MainActor (Value) -> Void
) -> Task<Void, Never> where Updates.Failure == Never {
    Task { @MainActor in
        var iterator = updates.makeAsyncIterator()
        while let update = await iterator.next(isolation: #isolation) {
            guard !Task.isCancelled else { return }
            yield(map(update))
        }
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
private extension GenericConnection where Configuration == Void {
    static func readOnlyAsyncSequence<Updates: AsyncSequence, WrappedValue>(
        _ updates: @escaping @MainActor () -> Updates,
        currentValue: @escaping @MainActor () -> WrappedValue,
        map: @escaping @MainActor (Updates.Element) -> WrappedValue
    ) -> Self where Updates.Failure == Never, Connected == ReadOnlyConnectedValue<WrappedValue> {
        Self {
            Session(
                currentValue: currentValue,
                observe: { yield in
                    observe(updates(), map: map, yield: yield)
                },
                cancel: { $0.cancel() }
            )
        }
    }

    static func writableAsyncSequence<Updates: AsyncSequence, WrappedValue>(
        _ updates: @escaping @MainActor () -> Updates,
        currentValue: @escaping @MainActor () -> WrappedValue,
        map: @escaping @MainActor (Updates.Element) -> WrappedValue,
        setValue: @escaping @MainActor (WrappedValue) -> Void
    ) -> Self where Updates.Failure == Never, Connected == WritableConnectedValue<WrappedValue> {
        Self {
            Session(
                currentValue: currentValue,
                setValue: setValue,
                observe: { yield in
                    observe(updates(), map: map, yield: yield)
                },
                cancel: { $0.cancel() }
            )
        }
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension GenericConnection where Configuration == Void {
    /// Creates a read-only connection that starts with an initial value and
    /// then receives values from an asynchronous sequence.
    /// The sequence expression is evaluated whenever observation starts.
    public static func async<Updates: AsyncSequence, WrappedValue>(
        _ updates: @autoclosure @escaping @MainActor () -> Updates,
        initialValue: WrappedValue
    ) -> Self where Updates.Element == WrappedValue, Updates.Failure == Never, Connected == ReadOnlyConnectedValue<WrappedValue> {
        Self.readOnlyAsyncSequence(
            updates,
            currentValue: { initialValue },
            map: { $0 }
        )
    }

    /// Creates a writable connection that starts with an initial value,
    /// receives values from an asynchronous sequence, and forwards
    /// writes to a setter.
    /// The sequence expression is evaluated whenever observation starts.
    public static func async<Updates: AsyncSequence, WrappedValue>(
        _ updates: @autoclosure @escaping @MainActor () -> Updates,
        initialValue: WrappedValue,
        set: @escaping @MainActor (WrappedValue) -> Void
    ) -> Self where Updates.Element == WrappedValue, Updates.Failure == Never, Connected == WritableConnectedValue<WrappedValue> {
        Self.writableAsyncSequence(
            updates,
            currentValue: { initialValue },
            map: { $0 },
            setValue: set
        )
    }

    /// Creates a read-only connection backed by an asynchronous
    /// sequence and a synchronous current-value getter.
    /// The sequence expression is evaluated whenever observation starts.
    public static func async<Updates: AsyncSequence, WrappedValue>(
        _ updates: @autoclosure @escaping @MainActor () -> Updates,
        currentValue: @escaping @MainActor () -> WrappedValue
    ) -> Self where Updates.Element == WrappedValue, Updates.Failure == Never, Connected == ReadOnlyConnectedValue<WrappedValue> {
        Self.readOnlyAsyncSequence(
            updates,
            currentValue: currentValue,
            map: { $0 }
        )
    }

    /// Creates a writable connection backed by an asynchronous
    /// sequence, a synchronous current-value getter, and a setter.
    /// The sequence expression is evaluated whenever observation starts.
    public static func async<Updates: AsyncSequence, WrappedValue>(
        _ updates: @autoclosure @escaping @MainActor () -> Updates,
        currentValue: @escaping @MainActor () -> WrappedValue,
        set: @escaping @MainActor (WrappedValue) -> Void
    ) -> Self where Updates.Element == WrappedValue, Updates.Failure == Never, Connected == WritableConnectedValue<WrappedValue> {
        Self.writableAsyncSequence(
            updates,
            currentValue: currentValue,
            map: { $0 },
            setValue: set
        )
    }

    /// Creates a read-only connection that maps values from an
    /// asynchronous sequence.
    /// The sequence expression is evaluated whenever observation starts.
    public static func async<Updates: AsyncSequence, WrappedValue>(
        _ updates: @autoclosure @escaping @MainActor () -> Updates,
        initialValue: WrappedValue,
        map: @escaping @MainActor (Updates.Element) -> WrappedValue
    ) -> Self where Updates.Failure == Never, Connected == ReadOnlyConnectedValue<WrappedValue> {
        Self.readOnlyAsyncSequence(
            updates,
            currentValue: { initialValue },
            map: map
        )
    }

    /// Creates a writable connection that maps values from an
    /// asynchronous sequence and forwards writes to a setter.
    /// The sequence expression is evaluated whenever observation starts.
    public static func async<Updates: AsyncSequence, WrappedValue>(
        _ updates: @autoclosure @escaping @MainActor () -> Updates,
        initialValue: WrappedValue,
        map: @escaping @MainActor (Updates.Element) -> WrappedValue,
        set: @escaping @MainActor (WrappedValue) -> Void
    ) -> Self where Updates.Failure == Never, Connected == WritableConnectedValue<WrappedValue> {
        Self.writableAsyncSequence(
            updates,
            currentValue: { initialValue },
            map: map,
            setValue: set
        )
    }

    /// Creates a read-only connection that maps values from an
    /// asynchronous sequence and uses a synchronous current-value getter.
    /// The sequence expression is evaluated whenever observation starts.
    public static func async<Updates: AsyncSequence, WrappedValue>(
        _ updates: @autoclosure @escaping @MainActor () -> Updates,
        currentValue: @escaping @MainActor () -> WrappedValue,
        map: @escaping @MainActor (Updates.Element) -> WrappedValue
    ) -> Self where Updates.Failure == Never, Connected == ReadOnlyConnectedValue<WrappedValue> {
        Self.readOnlyAsyncSequence(
            updates,
            currentValue: currentValue,
            map: map
        )
    }

    /// Creates a writable connection that maps values from an
    /// asynchronous sequence, uses a synchronous current-value getter, and
    /// forwards writes to a setter.
    /// The sequence expression is evaluated whenever observation starts.
    public static func async<Updates: AsyncSequence, WrappedValue>(
        _ updates: @autoclosure @escaping @MainActor () -> Updates,
        currentValue: @escaping @MainActor () -> WrappedValue,
        map: @escaping @MainActor (Updates.Element) -> WrappedValue,
        set: @escaping @MainActor (WrappedValue) -> Void
    ) -> Self where Updates.Failure == Never, Connected == WritableConnectedValue<WrappedValue> {
        Self.writableAsyncSequence(
            updates,
            currentValue: currentValue,
            map: map,
            setValue: set
        )
    }
}

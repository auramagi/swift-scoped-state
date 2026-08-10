//
//  Connection+Concurrency.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-10.
//

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@MainActor private func observe<Updates: AsyncSequence>(
    _ updates: Updates,
    yield: @escaping @MainActor (Updates.Element) -> Void
) -> Task<Void, Never> where Updates.Failure == Never {
    Task { @MainActor in
        var iterator = updates.makeAsyncIterator()
        while let update = await iterator.next(isolation: #isolation) {
            guard !Task.isCancelled else { return }
            yield(update)
        }
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension GenericConnection where Configuration == Void {
    /// Creates a read-only connection that starts with an initial value and
    /// then receives values from an asynchronous sequence.
    /// The sequence expression is evaluated whenever observation starts.
    public static func async<Updates: AsyncSequence, WrappedValue>(
        _ updates: @autoclosure @escaping () -> Updates,
        initialValue: WrappedValue
    ) -> Connection<WrappedValue> where Updates.Element == WrappedValue, Updates.Failure == Never {
        Connection<WrappedValue> {
            .init(
                initialValue: initialValue,
                observe: { yield in observe(updates(), yield: yield) },
                cancel: { $0.cancel() }
            )
        }
    }

    /// Creates a read-only connection backed by an asynchronous
    /// sequence and a synchronous current-value getter.
    /// The sequence expression is evaluated whenever observation starts.
    public static func async<Updates: AsyncSequence, WrappedValue>(
        _ updates: @autoclosure @escaping () -> Updates,
        currentValue: @escaping () -> WrappedValue
    ) -> Connection<WrappedValue> where Updates.Element == WrappedValue, Updates.Failure == Never {
        Connection<WrappedValue> {
            .init(
                currentValue: currentValue,
                observe: { yield in observe(updates(), yield: yield) },
                cancel: { $0.cancel() }
            )
        }
    }
}

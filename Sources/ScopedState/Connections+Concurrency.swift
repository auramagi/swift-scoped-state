//
//  Connections+Concurrency.swift
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
extension ConnectionDefinition where Self == Connections {
    /// Creates a read-only connection to an asynchronous sequence with an initial value.
    ///
    /// Each activation evaluates `updates` and starts a task to iterate the sequence.
    ///
    /// - Parameters:
    ///   - updates: The asynchronous sequence that delivers later values.
    ///   - initialValue: The value to use until the sequence produces a value.
    public static func async<Updates: AsyncSequence, WrappedValue>(
        _ updates: @autoclosure @escaping () -> Updates,
        initialValue: WrappedValue
    ) -> some ConnectionDefinition<EmptyConfiguration, WrappedValue> where Updates.Element == WrappedValue, Updates.Failure == Never {
        ReadOnlyConnectionDefinition { _ in
            .init(
                initialValue: initialValue,
                observe: { yield in observe(updates(), yield: yield) },
                cancel: { $0.cancel() }
            )
        }
    }

    /// Creates a read-only connection to an asynchronous sequence with a current-value getter.
    ///
    /// Each activation evaluates `updates` and starts a task to iterate the sequence.
    ///
    /// - Parameters:
    ///   - updates: The asynchronous sequence that delivers later values.
    ///   - currentValue: A closure that synchronously reads the latest value.
    public static func async<Updates: AsyncSequence, WrappedValue>(
        _ updates: @autoclosure @escaping () -> Updates,
        currentValue: @escaping () -> WrappedValue
    ) -> some ConnectionDefinition<EmptyConfiguration, WrappedValue> where Updates.Element == WrappedValue, Updates.Failure == Never {
        ReadOnlyConnectionDefinition { _ in
            .init(
                currentValue: currentValue,
                observe: { yield in observe(updates(), yield: yield) },
                cancel: { $0.cancel() }
            )
        }
    }
}

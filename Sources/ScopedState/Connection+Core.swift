//
//  Connection+Core.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-09.
//

extension GenericConnection where Configuration == Void {
    /// Creates a read-only connection that always provides the same value.
    public static func constant<WrappedValue>(
        _ value: WrappedValue
    ) -> Self where Connected == ReadOnlyConnectedValue<WrappedValue> {
        Self {
            Channel(
                valueSource: .initial(value),
                setValue: nil,
                observe: nil,
                updateConfiguration: { _ in }
            )
        }
    }
}

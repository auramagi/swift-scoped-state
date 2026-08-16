//
//  Connections.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-16.
//

/// A namespace for constructing connections.
public typealias Connections = ReadOnlyConnectionDefinition<EmptyConfiguration, Never>

extension ConnectionDefinition where Self == Connections {
    /// Creates a custom read-only connection.
    public static func readOnly<Configuration: Equatable, Value>(
        _ makeSession: @escaping (Configuration) -> ConnectionSession<Configuration, Value>
    ) -> some ConnectionDefinition<Configuration, Value> {
        ReadOnlyConnectionDefinition(createSession: makeSession)
    }

    /// Creates a custom read-only connection without configuration.
    public static func readOnly<Value>(
        _ makeSession: @escaping () -> ConnectionSession<EmptyConfiguration, Value>
    ) -> some ConnectionDefinition<EmptyConfiguration, Value> {
        ReadOnlyConnectionDefinition { _ in makeSession() }
    }

    /// Creates a custom writable connection.
    public static func readWrite<Configuration: Equatable, Value>(
        _ makeSession: @escaping (Configuration) -> ConnectionSession<Configuration, Value>
    ) -> some WritableConnectionDefinition<Configuration, Value> {
        ReadWriteConnectionDefinition(createSession: makeSession)
    }

    /// Creates a custom writable connection without configuration.
    public static func readWrite<Value>(
        _ makeSession: @escaping () -> ConnectionSession<EmptyConfiguration, Value>
    ) -> some WritableConnectionDefinition<EmptyConfiguration, Value> {
        ReadWriteConnectionDefinition { _ in makeSession() }
    }

    /// Creates a read-only connection that always provides the same value.
    public static func constant<WrappedValue>(
        _ value: WrappedValue
    ) -> some ConnectionDefinition<EmptyConfiguration, WrappedValue> {
        ReadOnlyConnectionDefinition { _ in
            .init { _ in
                (initialValue: value, observation: nil)
            }
        }
    }

    /// Creates a writable connection whose local scoped state starts with the
    /// provided value.
    ///
    /// Each connected property owns an independent value. The value changes
    /// only when that property is written and resets when its connection
    /// identity is recreated.
    public static func initial<WrappedValue>(
        _ initialValue: WrappedValue
    ) -> some WritableConnectionDefinition<EmptyConfiguration, WrappedValue> {
        ReadWriteConnectionDefinition { _ in
            var yieldValue: ((WrappedValue) -> Void)?

            return .init(
                activate: { yield in
                    yieldValue = { yield(.value($0)) }
                    return (initialValue: initialValue, observation: nil)
                },
                setValue: {
                    yieldValue?($0)
                }
            )
        }
    }
}

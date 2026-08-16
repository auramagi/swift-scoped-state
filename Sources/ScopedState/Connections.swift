//
//  Connections.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-16.
//

/// A namespace for constructing connection definitions.
///
/// When an expected connection type is available, Swift can infer this
/// namespace from leading-dot factory syntax.
///
/// ```swift
/// let fixed: Connection<Int> = .constant(42)
/// let editable: WritableConnection<String> = .initial("")
/// ```
public typealias Connections = ReadOnlyConnectionDefinition<EmptyConfiguration, Never>

extension ConnectionDefinition where Self == Connections {
    /// Creates a configured read-only connection from a session factory.
    ///
    /// - Parameter makeSession: A closure that creates a session for each
    ///   configuration.
    /// - Returns: A configured read-only connection definition.
    public static func readOnly<Configuration: Equatable, Value>(
        _ makeSession: @escaping (Configuration) -> ConnectionSession<Configuration, Value>
    ) -> some ConnectionDefinition<Configuration, Value> {
        ReadOnlyConnectionDefinition(createSession: makeSession)
    }

    /// Creates an unconfigured read-only connection from a session factory.
    ///
    /// - Parameter makeSession: A closure that creates the connection session.
    /// - Returns: A read-only connection definition.
    public static func readOnly<Value>(
        _ makeSession: @escaping () -> ConnectionSession<EmptyConfiguration, Value>
    ) -> some ConnectionDefinition<EmptyConfiguration, Value> {
        ReadOnlyConnectionDefinition { _ in makeSession() }
    }

    /// Creates a configured writable connection from a session factory.
    ///
    /// - Parameter makeSession: A closure that creates a session for each
    ///   configuration.
    /// - Returns: A configured writable connection definition.
    public static func readWrite<Configuration: Equatable, Value>(
        _ makeSession: @escaping (Configuration) -> ConnectionSession<Configuration, Value>
    ) -> some WritableConnectionDefinition<Configuration, Value> {
        ReadWriteConnectionDefinition(createSession: makeSession)
    }

    /// Creates an unconfigured writable connection from a session factory.
    ///
    /// - Parameter makeSession: A closure that creates the connection session.
    /// - Returns: A writable connection definition.
    public static func readWrite<Value>(
        _ makeSession: @escaping () -> ConnectionSession<EmptyConfiguration, Value>
    ) -> some WritableConnectionDefinition<EmptyConfiguration, Value> {
        ReadWriteConnectionDefinition { _ in makeSession() }
    }

    /// Creates a read-only connection that always provides the same value.
    ///
    /// A constant connection doesn't observe changes or accept replacement of
    /// its value. Constants are also useful for injecting actions represented
    /// by closures.
    ///
    /// - Parameter value: The value delivered to every connected property.
    /// - Returns: A read-only constant connection definition.
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
    ///
    /// - Parameter initialValue: The value assigned when a connection starts.
    /// - Returns: A writable connection with property-local state.
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

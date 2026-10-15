//
//  Connection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-08.
//

/// A read-only connection that requires no configuration.
///
/// Declare connections as properties of a scope, then select them from a view
/// with ``ScopedState``.
///
/// ```swift
/// struct AppScope {
///     let title: Connection<String>
/// }
/// ```
public typealias Connection<Value> = any ConnectionDefinition<EmptyConfiguration, Value>

/// A writable connection that requires no configuration.
///
/// A view accesses the value's SwiftUI binding through `$property`.
public typealias WritableConnection<Value> = any WritableConnectionDefinition<EmptyConfiguration, Value>

/// A read-only connection that takes an equatable configuration.
///
/// Use the configuration to select a value or child scope, for example by
/// passing an entity identifier.
public typealias ConfiguredConnection<Value, Configuration: Equatable> = any ConnectionDefinition<Configuration, Value>

/// A writable connection that takes an equatable configuration.
public typealias WritableConfiguredConnection<Value, Configuration: Equatable> = any WritableConnectionDefinition<Configuration, Value>

/// A definition that creates connection sessions for scoped state.
///
/// Declare scope properties with ``Connection`` or ``ConfiguredConnection``
/// and create their definitions with the factories on ``Connections``.
@MainActor public protocol ConnectionDefinition<Configuration, Value>: SendableMetatype {
    /// The configuration used to establish and update a session.
    associatedtype Configuration: Equatable

    /// The value delivered by the connection.
    associatedtype Value

    /// Creates a session for the supplied configuration.
    ///
    /// - Parameter configuration: The configuration for the new session.
    func makeSession(_ configuration: Configuration) -> ConnectionSession<Configuration, Value>
}

/// A connection definition that supports writing its connected value.
///
/// A writable definition can be stored in a read-only ``Connection`` property.
/// A writable property requires a writable definition.
public protocol WritableConnectionDefinition<Configuration, Value>: ConnectionDefinition { }

/// A concrete read-only connection definition returned by connection factories.
public struct ReadOnlyConnectionDefinition<Configuration: Equatable, Value>: ConnectionDefinition {
    let createSession: (Configuration) -> ConnectionSession<Configuration, Value>

    /// Creates a session for the supplied configuration.
    ///
    /// - Parameter configuration: The configuration for the new session.
    public func makeSession(_ configuration: Configuration) -> ConnectionSession<Configuration, Value> {
        createSession(configuration)
    }
}

/// A concrete writable connection definition returned by connection factories.
public struct ReadWriteConnectionDefinition<Configuration: Equatable, Value>: WritableConnectionDefinition {
    let createSession: (Configuration) -> ConnectionSession<Configuration, Value>

    /// Creates a writable session for the supplied configuration.
    ///
    /// - Parameter configuration: The configuration for the new session.
    public func makeSession(_ configuration: Configuration) -> ConnectionSession<Configuration, Value> {
        createSession(configuration)
    }
}

/// A placeholder for connections that take no configuration.
public struct EmptyConfiguration: Equatable {
    /// Creates an empty configuration.
    public init() { }
}

private extension ConnectionSession {
    func map<MappedValue>(
        get: @escaping (Value) -> MappedValue,
        set: ((MappedValue) -> Value)?
    ) -> ConnectionSession<Configuration, MappedValue> {
        let mappedSetValue: ((MappedValue) -> Void)?
        if let set, let setValue {
            mappedSetValue = { setValue(set($0)) }
        } else {
            mappedSetValue = nil
        }

        return .init(
            activate: { yield in
                let activation = activate { update in
                    switch update {
                    case let .value(value):
                        yield(.value(get(value)))
                    case .invalidate:
                        yield(.invalidate)
                    }
                }
                return (
                    initialValue: get(activation.initialValue),
                    observation: activation.observation
                )
            },
            refresh: {
                refresh().map(get)
            },
            reconfigure: reconfigure,
            setValue: mappedSetValue
        )
    }
}

extension ConnectionDefinition {
    /// Creates a read-only connection by transforming the source's values.
    ///
    /// The new connection uses the source's configuration and lifecycle.
    ///
    /// - Parameter transform: A closure that transforms a delivered value.
    public func map<MappedValue>(
        _ transform: @escaping (Value) -> MappedValue
    ) -> some ConnectionDefinition<Configuration, MappedValue> {
        ReadOnlyConnectionDefinition(
            createSession: { configuration in
                makeSession(configuration).map(get: transform, set: nil)
            }
        )
    }

    /// Adds or replaces the write operation of a connection.
    ///
    /// - Parameter setValue: A closure that receives values written through
    ///   the resulting connection.
    /// - Returns: A writable definition with the same read behavior.
    public func set(
        _ setValue: @escaping (Value) -> Void
    ) -> some WritableConnectionDefinition<Configuration, Value> {
        ReadWriteConnectionDefinition(
            createSession: { configuration in
                let session = makeSession(configuration)

                return .init(
                    activate: session.activate,
                    refresh: session.refresh,
                    reconfigure: session.reconfigure,
                    setValue: setValue
                )
            }
        )
    }
}

extension WritableConnectionDefinition {
    /// Creates a writable connection by transforming reads and writes.
    ///
    /// The new connection uses the source's configuration and lifecycle.
    ///
    /// - Parameters:
    ///   - get: A closure that transforms values delivered by the source.
    ///   - set: A closure that maps a written value back to the source value.
    public func map<MappedValue>(
        get: @escaping (Value) -> MappedValue,
        set: @escaping (MappedValue) -> Value
    ) -> some WritableConnectionDefinition<Configuration, MappedValue> {
        ReadWriteConnectionDefinition(
            createSession: { configuration in
                makeSession(configuration).map(get: get, set: set)
            }
        )
    }
}

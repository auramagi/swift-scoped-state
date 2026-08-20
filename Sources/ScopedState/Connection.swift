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
/// The projection of a writable scoped property is a SwiftUI binding to its
/// connected value.
public typealias WritableConnection<Value> = any WritableConnectionDefinition<EmptyConfiguration, Value>

/// A read-only connection established with an equatable configuration.
///
/// Use a configured connection to derive a scope or value for a particular
/// context, such as an entity identifier.
public typealias ConfiguredConnection<Value, Configuration: Equatable> = any ConnectionDefinition<Configuration, Value>

/// A writable connection established with an equatable configuration.
public typealias WritableConfiguredConnection<Value, Configuration: Equatable> = any WritableConnectionDefinition<Configuration, Value>

/// A definition that creates connection sessions for scoped state.
///
/// Most code works with ``Connection``, ``ConfiguredConnection``, and the
/// factory methods on ``Connections`` instead of conforming to this protocol
/// directly.
@MainActor public protocol ConnectionDefinition<Configuration, Value>: SendableMetatype {
    /// The configuration used to establish and update a session.
    associatedtype Configuration: Equatable

    /// The value delivered by the connection.
    associatedtype Value

    /// Creates a session for the supplied configuration.
    ///
    /// - Parameter configuration: The configuration for the new session.
    /// - Returns: A session that connects scoped state to its source.
    func makeSession(_ configuration: Configuration) -> ConnectionSession<Configuration, Value>
}

/// A connection definition that supports writing its connected value.
///
/// Writable definitions can satisfy read-only ``Connection`` declarations,
/// but read-only definitions can't satisfy writable declarations.
public protocol WritableConnectionDefinition<Configuration, Value>: ConnectionDefinition { }

/// A concrete read-only connection definition returned by connection factories.
public struct ReadOnlyConnectionDefinition<Configuration: Equatable, Value>: ConnectionDefinition {
    let createSession: (Configuration) -> ConnectionSession<Configuration, Value>

    /// Creates a read-only session for the supplied configuration.
    ///
    /// - Parameter configuration: The configuration for the new session.
    /// - Returns: A session that receives values from its source.
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
    /// - Returns: A session that receives and writes values.
    public func makeSession(_ configuration: Configuration) -> ConnectionSession<Configuration, Value> {
        createSession(configuration)
    }
}

/// The configuration used by connections that require no configuration.
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
    /// Transforms every delivered value into a read-only connection.
    ///
    /// The transformed definition preserves the source configuration and
    /// lifecycle behavior, but doesn't expose a write operation.
    ///
    /// - Parameter transform: A closure that transforms a delivered value.
    /// - Returns: A read-only definition for the transformed value.
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
    /// Bidirectionally transforms values delivered by and written through this
    /// connection while preserving its configuration and lifecycle behavior.
    ///
    /// - Parameters:
    ///   - get: A closure that transforms values delivered by the source.
    ///   - set: A closure that maps a written value back to the source value.
    /// - Returns: A writable definition for the transformed value.
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

//
//  Connection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-08.
//

public typealias Connection<Value> = any ConnectionDefinition<EmptyConfiguration, Value>

public typealias WritableConnection<Value> = any WritableConnectionDefinition<EmptyConfiguration, Value>

public typealias ConfiguredConnection<Value, Configuration: Equatable> = any ConnectionDefinition<Configuration, Value>

public typealias WritableConfiguredConnection<Value, Configuration: Equatable> = any WritableConnectionDefinition<Configuration, Value>

@MainActor public protocol ConnectionDefinition<Configuration, Value>: SendableMetatype {
    associatedtype Configuration: Equatable

    associatedtype Value

    func makeSession(_ configuration: Configuration) -> ConnectionSession<Configuration, Value>
}

public protocol WritableConnectionDefinition<Configuration, Value>: ConnectionDefinition { }

public struct ReadOnlyConnectionDefinition<Configuration: Equatable, Value>: ConnectionDefinition {
    let createSession: (Configuration) -> ConnectionSession<Configuration, Value>

    public func makeSession(_ configuration: Configuration) -> ConnectionSession<Configuration, Value> {
        createSession(configuration)
    }
}

public struct ReadWriteConnectionDefinition<Configuration: Equatable, Value>: WritableConnectionDefinition {
    let createSession: (Configuration) -> ConnectionSession<Configuration, Value>

    public func makeSession(_ configuration: Configuration) -> ConnectionSession<Configuration, Value> {
        createSession(configuration)
    }
}

public struct EmptyConfiguration: Equatable {
    public init() { }
}

extension ConnectionDefinition {
    /// Transforms every value delivered by this connection while preserving
    /// its configuration and lifecycle behavior.
    public func map<MappedValue>(
        _ transform: @escaping (Value) -> MappedValue
    ) -> some ConnectionDefinition<Configuration, MappedValue> {
        ReadOnlyConnectionDefinition(
            createSession: { configuration in
                let session = makeSession(configuration)

                return .init(
                    activate: { yield in
                        let activation = session.activate { update in
                            switch update {
                            case let .value(value):
                                yield(.value(transform(value)))
                            case .invalidate:
                                yield(.invalidate)
                            }
                        }
                        return (
                            initialValue: transform(activation.initialValue),
                            observation: activation.observation
                        )
                    },
                    refresh: {
                        session.refresh().map(transform)
                    },
                    reconfigure: session.reconfigure
                )
            }
        )
    }

    /// Adds a write operation to a read-only connection.
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

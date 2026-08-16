//
//  Connection+Core.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-09.
//

extension GenericConnection {
    /// Transforms every value delivered by this connection while preserving
    /// its configuration and lifecycle behavior.
    public func map<Configuration, Value, MappedValue>(
        _ transform: @escaping (Value) -> MappedValue
    ) -> GenericConnection<ReadOnlyValueDefinition<Configuration, MappedValue>> where Definition == ReadOnlyValueDefinition<Configuration, Value> {
        .init(
            makeSession: { configuration in
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
            },
            configurationsEqual: configurationsEqual
        )
    }

    /// Adds a write operation to a read-only connection.
    public func set<Configuration, Value>(
        _ setValue: @escaping (Value) -> Void
    ) -> GenericConnection<ReadWriteValueDefinition<Configuration, Value>> where Definition == ReadOnlyValueDefinition<Configuration, Value> {
        .init(
            makeSession: { configuration in
                let session = makeSession(configuration)

                return .init(
                    activate: session.activate,
                    refresh: session.refresh,
                    reconfigure: session.reconfigure,
                    setValue: setValue
                )
            },
            configurationsEqual: configurationsEqual
        )
    }
}

extension GenericConnection where Definition.Configuration == Void {
    /// Creates a read-only connection that always provides the same value.
    public static func constant<WrappedValue>(
        _ value: WrappedValue
    ) -> Connection<WrappedValue> {
        .init {
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
    ) -> Connection<WrappedValue>.Writable {
        .init {
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

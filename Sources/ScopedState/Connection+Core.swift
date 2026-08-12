//
//  Connection+Core.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-09.
//

extension GenericConnection {
    /// Transforms every value delivered by this connection while preserving
    /// its configuration and lifecycle behavior.
    public func map<WrappedValue, MappedValue>(
        _ transform: @escaping (WrappedValue) -> MappedValue
    ) -> GenericConnection<Configuration, ReadOnlyConnectedValue<MappedValue>> where Connected == ReadOnlyConnectedValue<WrappedValue> {
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
    public func set<WrappedValue>(
        _ setValue: @escaping (WrappedValue) -> Void
    ) -> GenericConnection<Configuration, WritableConnectedValue<WrappedValue>> where Connected == ReadOnlyConnectedValue<WrappedValue> {
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

extension GenericConnection where Configuration == Void {
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

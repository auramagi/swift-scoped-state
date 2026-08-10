//
//  Connection+Core.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-09.
//

@MainActor private final class ObservationActivation<State> {
    var state: State

    var isOngoing = true

    init(state: State) {
        self.state = state
    }
}

private extension GenericConnection.Session {
    static func observing<Observation>(
        activate: @escaping @MainActor (@escaping YieldValue) -> (
            initialValue: Connected.WrappedValue,
            observation: Observation
        ),
        cancel: @escaping (Observation) -> Void,
        reconfigure: @escaping @MainActor (Configuration) -> Void
    ) -> Self {
        Self(
            activate: { yield in
                let activation = activate { yield(.value($0)) }
                return (
                    initialValue: activation.initialValue,
                    cancellation: CancellationToken {
                        cancel(activation.observation)
                    }
                )
            },
            refresh: { nil },
            reconfigure: reconfigure,
            setValue: nil
        )
    }
}

extension GenericConnection.Session {
    public init<WrappedValue, Observation>(
        currentValue: @escaping @MainActor () -> WrappedValue,
        observe: @escaping @MainActor (@escaping YieldValue) -> Observation,
        cancel: @escaping (Observation) -> Void,
        reconfigure: @escaping @MainActor (Configuration) -> Void
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self = Self.observing(
            activate: { yield in
                let activation = ObservationActivation(state: ())
                let observation = observe { value in
                    guard !activation.isOngoing else { return }
                    yield(value)
                }
                let value = currentValue()
                activation.isOngoing = false
                return (initialValue: value, observation: observation)
            },
            cancel: cancel,
            reconfigure: reconfigure
        )
    }
}

extension GenericConnection.Session where Configuration == Void {
    public init<WrappedValue, Observation>(
        initialValue: WrappedValue,
        observe: @escaping @MainActor (@escaping YieldValue) -> Observation,
        cancel: @escaping (Observation) -> Void
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self = Self.observing(
            activate: { yield in
                let activation = ObservationActivation(state: initialValue)
                let observation = observe { value in
                    if activation.isOngoing {
                        activation.state = value
                    } else {
                        yield(value)
                    }
                }
                activation.isOngoing = false
                return (initialValue: activation.state, observation: observation)
            },
            cancel: cancel,
            reconfigure: { _ in }
        )
    }

    public init<WrappedValue, Observation>(
        currentValue: @escaping @MainActor () -> WrappedValue,
        observe: @escaping @MainActor (@escaping YieldValue) -> Observation,
        cancel: @escaping (Observation) -> Void
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.init(
            currentValue: currentValue,
            observe: observe,
            cancel: cancel,
            reconfigure: { _ in }
        )
    }
}

extension GenericConnection {
    /// Transforms every value delivered by this connection while preserving
    /// its configuration and lifecycle behavior.
    public func map<WrappedValue, MappedValue>(
        _ transform: @escaping @MainActor (WrappedValue) -> MappedValue
    ) -> GenericConnection<Configuration, ReadOnlyConnectedValue<MappedValue>> where Connected == ReadOnlyConnectedValue<WrappedValue> {
        typealias MappedConnection = GenericConnection<Configuration, ReadOnlyConnectedValue<MappedValue>>

        return MappedConnection(
            makeSession: { configuration in
                let session = makeSession(configuration)

                return MappedConnection.Session(
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
                            cancellation: activation.cancellation
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
        _ setValue: @escaping @MainActor (WrappedValue) -> Void
    ) -> GenericConnection<Configuration, WritableConnectedValue<WrappedValue>> where Connected == ReadOnlyConnectedValue<WrappedValue> {
        typealias WritableConnection = GenericConnection<Configuration, WritableConnectedValue<WrappedValue>>

        return WritableConnection(
            makeSession: { configuration in
                let session = makeSession(configuration)

                return WritableConnection.Session(
                    activate: { yield in
                        let activation = session.activate { update in
                            switch update {
                            case let .value(value):
                                yield(.value(value))
                            case .invalidate:
                                yield(.invalidate)
                            }
                        }
                        return (
                            initialValue: activation.initialValue,
                            cancellation: activation.cancellation
                        )
                    },
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
        Connection<WrappedValue> {
            .init { _ in
                (initialValue: value, cancellation: nil)
            }
        }
    }
}

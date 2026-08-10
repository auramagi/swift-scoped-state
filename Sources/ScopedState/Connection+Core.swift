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
            value: Connected.WrappedValue,
            observation: Observation
        ),
        cancel: @escaping (Observation) -> Void,
        reconfigure: @escaping @MainActor (Configuration) -> Void
    ) -> Self {
        var cancellationToken: CancellationToken?

        func cancelObservation() {
            cancellationToken?.cancel()
            cancellationToken = nil
        }

        func start(yield: @escaping YieldValue) -> Connected.WrappedValue {
            let activation = activate(yield)
            cancellationToken = CancellationToken { cancel(activation.observation) }
            return activation.value
        }

        return Self(
            activate: { yield in
                cancelObservation()
                return start(yield: yield)
            },
            update: { nil },
            reconfigure: { configuration, yield in
                cancelObservation()
                reconfigure(configuration)
                return start(yield: yield)
            },
            deactivate: cancelObservation,
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
                return (value, observation)
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
                return (activation.state, observation)
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
                        transform(session.activate { yield(transform($0)) })
                    },
                    update: {
                        session.update().map(transform)
                    },
                    reconfigure: { configuration, yield in
                        transform(session.reconfigure(configuration) { yield(transform($0)) })
                    },
                    deactivate: session.deactivate
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
                    activate: session.activate,
                    update: session.update,
                    reconfigure: session.reconfigure,
                    deactivate: session.deactivate,
                    setValue: setValue
                )
            },
            configurationsEqual: configurationsEqual
        )
    }
}

extension GenericConnection where Configuration == Void {
    public init<WrappedValue, Observation>(
        initialValue: WrappedValue,
        observe: @escaping @MainActor (@escaping Session.YieldValue) -> Observation,
        cancel: @escaping (Observation) -> Void
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.init {
            Session(
                initialValue: initialValue,
                observe: observe,
                cancel: cancel
            )
        }
    }

    public init<WrappedValue, Observation>(
        currentValue: @escaping @MainActor () -> WrappedValue,
        observe: @escaping @MainActor (@escaping Session.YieldValue) -> Observation,
        cancel: @escaping (Observation) -> Void
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.init {
            Session(
                currentValue: currentValue,
                observe: observe,
                cancel: cancel
            )
        }
    }

    /// Creates a read-only connection that always provides the same value.
    public static func constant<WrappedValue>(
        _ value: WrappedValue
    ) -> Connection<WrappedValue> {
        Connection<WrappedValue> {
            .init { _ in value }
        }
    }
}

//
//  Connection+Core.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-09.
//

private extension GenericConnection.Session {
    static func observing<Observation>(
        currentValue: @escaping @MainActor () -> Connected.WrappedValue,
        observe: @escaping @MainActor (@escaping YieldValue) -> Observation,
        cancel: @escaping (Observation) -> Void,
        reconfigure: @escaping @MainActor (Configuration) -> Void
    ) -> Self {
        var cancellationToken: CancellationToken?

        func cancelObservation() {
            cancellationToken?.cancel()
            cancellationToken = nil
        }

        func startObservation(yield: @escaping YieldValue) {
            let observation = observe(yield)
            cancellationToken = CancellationToken { cancel(observation) }
            yield(currentValue())
        }

        return Self(
            activate: { yield in
                cancelObservation()
                startObservation(yield: yield)
            },
            update: { _ in },
            reconfigure: { configuration, yield in
                cancelObservation()
                reconfigure(configuration)
                startObservation(yield: yield)
            },
            deactivate: {
                cancelObservation()
            },
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
            currentValue: currentValue,
            observe: observe,
            cancel: cancel,
            reconfigure: reconfigure
        )
    }
}

extension GenericConnection.Session where Configuration == Void {
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

                func transformYield(
                    _ yield: @escaping MappedConnection.Session.YieldValue
                ) -> Session.YieldValue {
                    { value in
                        yield(transform(value))
                    }
                }

                return MappedConnection.Session(
                    activate: { yield in
                        session.activate(transformYield(yield))
                    },
                    update: { yield in
                        session.update(transformYield(yield))
                    },
                    reconfigure: { configuration, yield in
                        session.reconfigure(configuration, transformYield(yield))
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
    /// Creates an unconfigured connection whose operations' capture-list state
    /// is recreated for every session.
    public init<WrappedValue>(
        activate: @autoclosure @escaping @MainActor () -> Session.Activate,
        update: @autoclosure @escaping @MainActor () -> Session.Update = ({ (_: @escaping Session.YieldValue) in } as Session.Update),
        deactivate: @autoclosure @escaping @MainActor () -> Session.Deactivate = ({} as Session.Deactivate)
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.init {
            Session(
                activate: activate(),
                update: update(),
                deactivate: deactivate()
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
        Connection<WrappedValue> { yield in
            yield(value)
        }
    }
}

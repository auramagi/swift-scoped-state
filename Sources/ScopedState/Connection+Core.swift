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

private extension ConnectionSession {
    static func observing<Observation>(
        activate: @escaping (@escaping @MainActor (Value) -> Void) -> (
            initialValue: Value,
            observation: Observation
        ),
        cancel: @escaping (Observation) -> Void,
        reconfigure: @escaping (Configuration) -> Void
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
            reconfigure: reconfigure
        )
    }
}

extension ConnectionSession {
    public init<Observation>(
        currentValue: @escaping () -> Value,
        observe: @escaping (@escaping @MainActor (Value) -> Void) -> Observation,
        cancel: @escaping (Observation) -> Void,
        reconfigure: @escaping (Configuration) -> Void
    ) {
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

extension ConnectionSession where Configuration == Void {
    public init<Observation>(
        initialValue: Value,
        observe: @escaping (@escaping @MainActor (Value) -> Void) -> Observation,
        cancel: @escaping (Observation) -> Void
    ) {
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

    public init<Observation>(
        currentValue: @escaping () -> Value,
        observe: @escaping (@escaping @MainActor (Value) -> Void) -> Observation,
        cancel: @escaping (Observation) -> Void
    ) {
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
                (initialValue: value, cancellation: nil)
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
                    return (initialValue: initialValue, cancellation: nil)
                },
                setValue: {
                    yieldValue?($0)
                }
            )
        }
    }
}

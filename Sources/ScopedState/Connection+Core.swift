//
//  Connection+Core.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-09.
//

private extension GenericConnection.Channel {
    static func observing<Observation>(
        currentValue: @escaping @MainActor () -> Connected.WrappedValue,
        observe: @escaping @MainActor (@escaping YieldValue) -> Observation,
        cancel: @escaping (Observation) -> Void,
        reconfigure: @escaping @MainActor (Configuration) -> Void,
        setValue: SetValue?
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
            setValue: setValue
        )
    }
}

extension GenericConnection.Channel {
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
            reconfigure: reconfigure,
            setValue: nil
        )
    }

    public init<WrappedValue, Observation>(
        currentValue: @escaping @MainActor () -> WrappedValue,
        setValue: @escaping @MainActor (WrappedValue) -> Void,
        observe: @escaping @MainActor (@escaping YieldValue) -> Observation,
        cancel: @escaping (Observation) -> Void,
        reconfigure: @escaping @MainActor (Configuration) -> Void
    ) where Connected == WritableConnectedValue<WrappedValue> {
        self = Self.observing(
            currentValue: currentValue,
            observe: observe,
            cancel: cancel,
            reconfigure: reconfigure,
            setValue: setValue
        )
    }
}

extension GenericConnection.Channel where Configuration == Void {
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

    public init<WrappedValue, Observation>(
        currentValue: @escaping @MainActor () -> WrappedValue,
        setValue: @escaping @MainActor (WrappedValue) -> Void,
        observe: @escaping @MainActor (@escaping YieldValue) -> Observation,
        cancel: @escaping (Observation) -> Void
    ) where Connected == WritableConnectedValue<WrappedValue> {
        self.init(
            currentValue: currentValue,
            setValue: setValue,
            observe: observe,
            cancel: cancel,
            reconfigure: { _ in }
        )
    }
}

extension GenericConnection where Configuration == Void {
    /// Creates an unconfigured connection whose operations' capture-list state
    /// is recreated for every channel.
    public init<WrappedValue>(
        activate: @autoclosure @escaping @MainActor () -> Channel.Activate,
        update: @autoclosure @escaping @MainActor () -> Channel.Update = ({ (_: @escaping Channel.YieldValue) in } as Channel.Update),
        deactivate: @autoclosure @escaping @MainActor () -> Channel.Deactivate = ({} as Channel.Deactivate)
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.init {
            Channel(
                activate: activate(),
                update: update(),
                deactivate: deactivate()
            )
        }
    }

    /// Creates an unconfigured writable connection whose operations' capture-list
    /// state is recreated for every channel.
    public init<WrappedValue>(
        activate: @autoclosure @escaping @MainActor () -> Channel.Activate,
        update: @autoclosure @escaping @MainActor () -> Channel.Update = ({ (_: @escaping Channel.YieldValue) in } as Channel.Update),
        deactivate: @autoclosure @escaping @MainActor () -> Channel.Deactivate = ({} as Channel.Deactivate),
        setValue: @autoclosure @escaping @MainActor () -> Channel.SetValue
    ) where Connected == WritableConnectedValue<WrappedValue> {
        self.init {
            Channel(
                activate: activate(),
                update: update(),
                deactivate: deactivate(),
                setValue: setValue()
            )
        }
    }

    public init<WrappedValue, Observation>(
        currentValue: @escaping @MainActor () -> WrappedValue,
        observe: @escaping @MainActor (@escaping Channel.YieldValue) -> Observation,
        cancel: @escaping (Observation) -> Void
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.init {
            Channel(
                currentValue: currentValue,
                observe: observe,
                cancel: cancel
            )
        }
    }

    public init<WrappedValue, Observation>(
        currentValue: @escaping @MainActor () -> WrappedValue,
        setValue: @escaping @MainActor (WrappedValue) -> Void,
        observe: @escaping @MainActor (@escaping Channel.YieldValue) -> Observation,
        cancel: @escaping (Observation) -> Void
    ) where Connected == WritableConnectedValue<WrappedValue> {
        self.init {
            Channel(
                currentValue: currentValue,
                setValue: setValue,
                observe: observe,
                cancel: cancel
            )
        }
    }

    /// Creates a read-only connection that always provides the same value.
    public static func constant<WrappedValue>(
        _ value: WrappedValue
    ) -> Self where Connected == ReadOnlyConnectedValue<WrappedValue> {
        Self { yield in
            yield(value)
        }
    }
}

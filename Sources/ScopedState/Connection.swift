//
//  Connection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-08.
//

public typealias Connection<WrappedValue> = GenericConnection<Void, ReadOnlyConnectedValue<WrappedValue>>

extension Connection {
    public typealias Configuration<NewConfiguration> = GenericConnection<NewConfiguration, Connected>

    public typealias Writable = GenericConnection<Configuration, WritableConnectedValue<Connected.WrappedValue>>
}

/// The generic implementation underlying the public `Connection<Value>` family.
@MainActor public struct GenericConnection<Configuration, Connected: ConnectedValue> {
    /// A configurable value channel between scoped state and an external
    /// implementation.
    /// Its closures retain any implementation object needed to keep the value alive.
    @MainActor public struct Channel {
        public typealias ReceiveValue = @MainActor (Connected.WrappedValue) -> Void

        public enum ValueSource {
            case initial(Connected.WrappedValue)

            case current(@MainActor () -> Connected.WrappedValue)
        }

        final class CancellationToken {
            private var cancellation: (() -> Void)?

            init(_ cancellation: @escaping () -> Void) {
                self.cancellation = cancellation
            }

            func cancel() {
                guard let cancellation else {
                    return
                }
                self.cancellation = nil
                cancellation()
            }

            deinit {
                cancel()
            }
        }

        let valueSource: ValueSource

        let setValue: (@MainActor (Connected.WrappedValue) -> Void)?

        let observe: (@MainActor (@escaping ReceiveValue) -> CancellationToken)?

        let updateConfiguration: @MainActor (Configuration) -> Void
    }

    let makeChannel: @MainActor (Configuration) -> Channel

    let configurationsEqual: @MainActor (Configuration, Configuration) -> Bool

    public init(
        makeChannel: @escaping @MainActor (Configuration) -> Channel,
        configurationsEqual: @escaping @MainActor (Configuration, Configuration) -> Bool
    ) {
        self.makeChannel = makeChannel
        self.configurationsEqual = configurationsEqual
    }
}

extension GenericConnection.Channel {
    public init<WrappedValue, Observation>(
        valueSource: ValueSource,
        observe: @escaping @MainActor (@escaping ReceiveValue) -> Observation,
        cancel: @escaping (Observation) -> Void,
        updateConfiguration: @escaping @MainActor (Configuration) -> Void = { _ in }
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.init(
            valueSource: valueSource,
            setValue: nil,
            observe: { receiveValue in
                let observation = observe(receiveValue)
                return CancellationToken { cancel(observation) }
            },
            updateConfiguration: updateConfiguration
        )
    }

    public init<WrappedValue, Observation>(
        valueSource: ValueSource,
        setValue: @escaping @MainActor (WrappedValue) -> Void,
        observe: @escaping @MainActor (@escaping ReceiveValue) -> Observation,
        cancel: @escaping (Observation) -> Void,
        updateConfiguration: @escaping @MainActor (Configuration) -> Void = { _ in }
    ) where Connected == WritableConnectedValue<WrappedValue> {
        self.init(
            valueSource: valueSource,
            setValue: setValue,
            observe: { receiveValue in
                let observation = observe(receiveValue)
                return CancellationToken { cancel(observation) }
            },
            updateConfiguration: updateConfiguration
        )
    }
}

extension GenericConnection where Configuration: Equatable {
    public init(
        makeChannel: @escaping @MainActor (Configuration) -> Channel
    ) {
        self.init(
            makeChannel: makeChannel,
            configurationsEqual: { $0 == $1 }
        )
    }
}

extension GenericConnection where Configuration == Void {
    public init(
        makeChannel: @escaping @MainActor () -> Channel
    ) {
        self.init(
            makeChannel: { _ in makeChannel() },
            configurationsEqual: { _, _ in true }
        )
    }

    public init<WrappedValue, Observation>(
        currentValue: @escaping @MainActor () -> WrappedValue,
        observe: @escaping @MainActor (@escaping Channel.ReceiveValue) -> Observation,
        cancel: @escaping (Observation) -> Void
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.init {
            Channel(
                valueSource: .current(currentValue),
                observe: observe,
                cancel: cancel
            )
        }
    }

    public init<WrappedValue, Observation>(
        currentValue: @escaping @MainActor () -> WrappedValue,
        setValue: @escaping @MainActor (WrappedValue) -> Void,
        observe: @escaping @MainActor (@escaping Channel.ReceiveValue) -> Observation,
        cancel: @escaping (Observation) -> Void
    ) where Connected == WritableConnectedValue<WrappedValue> {
        self.init {
            Channel(
                valueSource: .current(currentValue),
                setValue: setValue,
                observe: observe,
                cancel: cancel
            )
        }
    }
}

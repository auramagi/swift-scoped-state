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
        public typealias YieldValue = @MainActor (Connected.WrappedValue) -> Void

        public typealias Activate = @MainActor (@escaping YieldValue) -> Void

        public typealias Update = @MainActor (@escaping YieldValue) -> Void

        public typealias Reconfigure = @MainActor (Configuration, @escaping YieldValue) -> Void

        public typealias Deactivate = @MainActor () -> Void

        public typealias SetValue = @MainActor (Connected.WrappedValue) -> Void

        let activate: Activate

        let update: Update

        let reconfigure: Reconfigure

        let deactivate: Deactivate

        let setValue: SetValue?
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
    public init<WrappedValue>(
        activate: @escaping Activate,
        update: @escaping Update = { _ in },
        reconfigure: @escaping Reconfigure,
        deactivate: @escaping Deactivate = {}
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.activate = activate
        self.update = update
        self.reconfigure = reconfigure
        self.deactivate = deactivate
        self.setValue = nil
    }

    public init<WrappedValue>(
        activate: @escaping Activate,
        update: @escaping Update = { _ in },
        reconfigure: @escaping Reconfigure,
        deactivate: @escaping Deactivate = {},
        setValue: @escaping SetValue
    ) where Connected == WritableConnectedValue<WrappedValue> {
        self.activate = activate
        self.update = update
        self.reconfigure = reconfigure
        self.deactivate = deactivate
        self.setValue = setValue
    }
}

extension GenericConnection.Channel where Configuration == Void {
    public init<WrappedValue>(
        activate: @escaping Activate,
        update: @escaping Update = { _ in },
        deactivate: @escaping Deactivate = {}
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.init(
            activate: activate,
            update: update,
            reconfigure: { _, _ in },
            deactivate: deactivate
        )
    }

    public init<WrappedValue>(
        activate: @escaping Activate,
        update: @escaping Update = { _ in },
        deactivate: @escaping Deactivate = {},
        setValue: @escaping SetValue
    ) where Connected == WritableConnectedValue<WrappedValue> {
        self.init(
            activate: activate,
            update: update,
            reconfigure: { _, _ in },
            deactivate: deactivate,
            setValue: setValue
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
}

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
    /// A configurable session connecting scoped state to an external
    /// implementation.
    /// Its closures retain any implementation object needed to keep the value alive.
    @MainActor public struct Session {
        /// The value installed when observation starts and the token retaining
        /// that observation for the activation lifetime.
        public typealias Activation = (
            initialValue: Connected.WrappedValue,
            cancellation: CancellationToken?
        )

        /// Delivers values produced after the active lifecycle operation returns.
        public typealias YieldValue = @MainActor (Connected.WrappedValue) -> Void

        /// Starts observation and returns its initial value and cancellation.
        let activate: @MainActor (@escaping YieldValue) -> Activation

        /// Optionally refreshes the current value without delivering an update.
        let update: @MainActor () -> Connected.WrappedValue?

        /// Updates the external implementation before starting a new activation.
        let reconfigure: @MainActor (Configuration) -> Void

        let setValue: (@MainActor (Connected.WrappedValue) -> Void)?
    }

    let makeSession: @MainActor (Configuration) -> Session

    let configurationsEqual: @MainActor (Configuration, Configuration) -> Bool

    public init(
        makeSession: @escaping @MainActor (Configuration) -> Session,
        configurationsEqual: @escaping @MainActor (Configuration, Configuration) -> Bool
    ) {
        self.makeSession = makeSession
        self.configurationsEqual = configurationsEqual
    }
}

extension GenericConnection.Session {
    public init<WrappedValue>(
        activate: @escaping @MainActor (@escaping YieldValue) -> Activation,
        update: @escaping @MainActor () -> WrappedValue? = { nil },
        reconfigure: @escaping @MainActor (Configuration) -> Void
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.activate = activate
        self.update = update
        self.reconfigure = reconfigure
        self.setValue = nil
    }

    public init<WrappedValue>(
        activate: @escaping @MainActor (@escaping YieldValue) -> Activation,
        update: @escaping @MainActor () -> WrappedValue? = { nil },
        reconfigure: @escaping @MainActor (Configuration) -> Void,
        setValue: @escaping @MainActor (WrappedValue) -> Void
    ) where Connected == WritableConnectedValue<WrappedValue> {
        self.activate = activate
        self.update = update
        self.reconfigure = reconfigure
        self.setValue = setValue
    }
}

extension GenericConnection.Session where Configuration == Void {
    public init<WrappedValue>(
        activate: @escaping @MainActor (@escaping YieldValue) -> Activation,
        update: @escaping @MainActor () -> WrappedValue? = { nil }
    ) where Connected == ReadOnlyConnectedValue<WrappedValue> {
        self.init(
            activate: activate,
            update: update,
            reconfigure: { _ in }
        )
    }

    public init<WrappedValue>(
        activate: @escaping @MainActor (@escaping YieldValue) -> Activation,
        update: @escaping @MainActor () -> WrappedValue? = { nil },
        setValue: @escaping @MainActor (WrappedValue) -> Void
    ) where Connected == WritableConnectedValue<WrappedValue> {
        self.init(
            activate: activate,
            update: update,
            reconfigure: { _ in },
            setValue: setValue
        )
    }
}

extension GenericConnection where Configuration: Equatable {
    public init(
        makeSession: @escaping @MainActor (Configuration) -> Session
    ) {
        self.init(
            makeSession: makeSession,
            configurationsEqual: { $0 == $1 }
        )
    }
}

extension GenericConnection where Configuration == Void {
    public init(
        makeSession: @escaping @MainActor () -> Session
    ) {
        self.init(
            makeSession: { _ in makeSession() },
            configurationsEqual: { _, _ in true }
        )
    }
}

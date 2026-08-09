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

extension GenericConnection.Session where Configuration == Void {
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

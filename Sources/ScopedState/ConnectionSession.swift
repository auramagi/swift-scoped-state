//
//  ConnectionSession.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-10.
//

/// A configurable session connecting scoped state to an external
/// implementation.
/// Its closures retain any implementation object needed to keep the value alive.
@MainActor public struct ConnectionSession<Configuration, Value> {
    /// A change emitted by an active session.
    public enum Update {
        /// Installs a value delivered by an external source.
        case value(Value)

        /// Invalidates the current value so it can be refreshed during the
        /// next dynamic-property update.
        case invalidate
    }

    /// The value installed when observation starts and the token retaining
    /// that observation for the activation lifetime.
    public typealias Activation = (
        initialValue: Value,
        cancellation: CancellationToken?
    )

    /// Delivers updates produced after the active lifecycle operation returns.
    public typealias Yield = @MainActor (Update) -> Void

    /// Starts observation and returns its initial value and cancellation.
    let activate: (@escaping Yield) -> Activation

    /// Optionally refreshes the current value without delivering an update.
    let refresh: () -> Value?

    /// Updates the external implementation before starting a new activation.
    let reconfigure: (Configuration) -> Void

    let setValue: ((Value) -> Void)?

    public init(
        activate: @escaping (@escaping Yield) -> Activation,
        refresh: @escaping () -> Value? = { nil },
        reconfigure: @escaping (Configuration) -> Void,
        setValue: ((Value) -> Void)? = nil
    ) {
        self.activate = activate
        self.refresh = refresh
        self.reconfigure = reconfigure
        self.setValue = setValue
    }
}

extension ConnectionSession where Configuration == Void {
    public init(
        activate: @escaping (@escaping Yield) -> Activation,
        refresh: @escaping () -> Value? = { nil },
        setValue: ((Value) -> Void)? = nil
    ) {
        self.init(
            activate: activate,
            refresh: refresh,
            reconfigure: { _ in },
            setValue: setValue
        )
    }
}

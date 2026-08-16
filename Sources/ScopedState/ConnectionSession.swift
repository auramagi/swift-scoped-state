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

    /// The value installed when observation starts and the observation whose
    /// ownership transfers to ScopedState for the activation lifetime.
    public typealias Activation = (
        initialValue: Value,
        observation: CancellationToken?
    )

    /// Delivers updates produced after the active lifecycle operation returns.
    public typealias Yield = @MainActor (Update) -> Void

    /// Starts observation and returns its initial value and observation token.
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

extension ConnectionSession where Configuration == EmptyConfiguration {
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

@MainActor private final class ActivationState<Value> {
    var value: Value

    var didActivate = false

    init(value: Value) {
        self.value = value
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
                    observation: CancellationToken {
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
                let activation = ActivationState(value: ())
                let observation = observe { value in
                    guard activation.didActivate else { return }
                    yield(value)
                }
                let value = currentValue()
                activation.didActivate = true
                return (initialValue: value, observation: observation)
            },
            cancel: cancel,
            reconfigure: reconfigure
        )
    }
}

extension ConnectionSession where Configuration == EmptyConfiguration {
    public init<Observation>(
        initialValue: Value,
        observe: @escaping (@escaping @MainActor (Value) -> Void) -> Observation,
        cancel: @escaping (Observation) -> Void
    ) {
        self = Self.observing(
            activate: { yield in
                let activation = ActivationState(value: initialValue)
                let observation = observe { value in
                    if activation.didActivate {
                        yield(value)
                    } else {
                        activation.value = value
                    }
                }
                activation.didActivate = true
                return (initialValue: activation.value, observation: observation)
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

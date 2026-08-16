//
//  CancellationToken.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-09.
//

/// An idempotent cancellation action that also runs when the token is released.
public final class CancellationToken {
    private var cancellation: (() -> Void)?

    /// Creates a token that performs the supplied action when cancelled.
    ///
    /// - Parameter cancellation: The action to run at most once, either from
    ///   ``cancel()`` or when the token is released.
    public init(_ cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    /// Runs the cancellation action if it hasn't already run.
    ///
    /// Calling this method more than once has no additional effect.
    public func cancel() {
        let cancellation = self.cancellation
        self.cancellation = nil
        cancellation?()
    }

    deinit {
        cancel()
    }
}

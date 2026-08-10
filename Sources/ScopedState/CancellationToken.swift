//
//  CancellationToken.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-09.
//

/// An idempotent cancellation action that also runs when the token is released.
public final class CancellationToken {
    private var cancellation: (() -> Void)?

    public init(_ cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    public func cancel() {
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

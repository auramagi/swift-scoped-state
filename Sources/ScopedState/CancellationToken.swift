//
//  CancellationToken.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-09.
//

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

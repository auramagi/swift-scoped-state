//
//  CancellationTokenTests.swift
//  ScopedStateTests
//
//  Created by Mikhail Apurin on 2026-08-09.
//

import Testing
@testable import ScopedState

@Suite("Cancellation token")
struct CancellationTokenTests {
    @Test
    func cancelsOnDeinitialization() {
        var cancellationCount = 0
        var cancellationToken: CancellationToken? = CancellationToken {
            cancellationCount += 1
        }

        #expect(cancellationToken != nil)
        cancellationToken = nil
        #expect(cancellationCount == 1)
    }
}

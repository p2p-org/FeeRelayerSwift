// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation
import Combine

/// Manager class for RelayContext
public protocol RelayContextManager {
    /// Current RelayContext
    var currentContext: RelayContext? { get }
    
    /// Publisher for current RelayContext
    var contextPublisher: AnyPublisher<RelayContext?, Never> { get }
    
    /// Update current context
    @discardableResult
    func update() async throws -> RelayContext
    
    /// Modify context locally
    func replaceContext(by context: RelayContext)
}

public enum RelayContextManagerError: Swift.Error, Equatable {
    case invalidContext
}

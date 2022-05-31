// Copyright 2022 P2P Validator Authors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be
// found in the LICENSE file.

import Foundation

public protocol FeeRelayerContextManager: AnyObject {
    func getCurrentContext() async throws -> FeeRelayerContext
    func update() async throws
    func validate() async throws -> Bool
}

public enum FeeRelayerContextManagerError: Swift.Error {
    case invalidContext
}
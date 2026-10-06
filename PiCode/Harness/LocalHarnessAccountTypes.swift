//
//  LocalHarnessAccountTypes.swift
//  PiCode
//

import Foundation

struct LocalHarnessAccountStatus: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case subscription
        case localCredentials
        case apiKey
        case signedOut
        case unavailable
    }

    var kind: Kind
    var title: String
    var detail: String
}

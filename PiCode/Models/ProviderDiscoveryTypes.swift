//
//  ProviderDiscoveryTypes.swift
//  PiCode
//
//  Results returned when Settings connects to a third-party model endpoint.
//

import Foundation

struct ProviderDiscoveryResult {
    var endpoint: URL
    var models: [PiProviderService.CustomModel]
}

enum ProviderDiscoveryError: LocalizedError {
    case invalidEndpoint
    case unsupportedAPI(String)
    case unavailable(String)
    case noModels

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Enter a valid HTTP or HTTPS endpoint."
        case .unsupportedAPI(let api):
            return "\(api) does not expose a model-list endpoint. Add its model IDs manually."
        case .unavailable(let detail):
            return detail
        case .noModels:
            return "The endpoint responded, but did not return any models."
        }
    }
}

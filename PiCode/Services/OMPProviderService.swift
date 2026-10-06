//
//  OMPProviderService.swift
//  PiCode
//
//  Exports PiCode's neutral third-party providers to OMP's models.yml. JSON is
//  valid YAML, which lets the shared lossless JSON writer preserve model fields.
//

import Foundation

enum OMPProviderService {
    static var modelsFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".omp/agent/models.yml")
    }

    static func saveCustomProviders(_ providers: [ProviderConfiguration]) throws {
        if FileManager.default.fileExists(atPath: modelsFile.path) {
            let data = try Data(contentsOf: modelsFile)
            if !data.isEmpty, (try? JSONCoding.decode(data).objectValue) == nil {
                throw NSError(
                    domain: "PiCode.OMPProviders",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "OMP's models.yml contains hand-written YAML. PiCode left it unchanged; convert it to JSON-compatible YAML before enabling shared provider sync."]
                )
            }
        }
        try ProviderConfigurationStore.save(providers, to: modelsFile) { model, object in
            if model.reasoning {
                object["thinking"] = ProviderModelCapabilities.standardThinking
            } else {
                object.removeValue(forKey: "thinking")
            }
        }
    }
}

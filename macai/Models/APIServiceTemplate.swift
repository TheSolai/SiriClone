//
//  APIServiceTemplate.swift
//  SiriClone
//
//  Kept as empty types so legacy code that imports it still compiles.
//  SiriClone uses Apple Intelligence only and has no template catalog.
//

import Foundation

struct APIServiceTemplateCatalog: Codable {
    let providers: [APIServiceProviderTemplate]
}

struct APIServiceProviderTemplate: Codable, Identifiable {
    let id: String
    let displayName: String
    let description: String?
    let defaultName: String?
    let note: String?
    let models: [APIServiceModelTemplate]
}

struct APIServiceModelTemplate: Codable, Identifiable {
    let id: String
    let displayName: String
    let description: String?
    let note: String?
    private let isDefault: Bool?
    private let requiresExpert: Bool?
    let settings: APIServiceTemplateSettings?
}

struct APIServiceTemplateSettings: Codable {
    let generateChatNames: Bool?
    let contextSize: Int?
    let useStreaming: Bool?
    let allowImageUploads: Bool?
    let allowPdfUploads: Bool?
    let imageGenerationSupported: Bool?
}

extension APIServiceTemplateCatalog {
    static let empty = APIServiceTemplateCatalog(providers: [])
}
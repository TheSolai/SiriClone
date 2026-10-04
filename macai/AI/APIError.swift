//
//  APIError.swift
//  SiriClone
//
//  Generic error type kept for call-site compatibility. With Apple
//  Intelligence, most of these won't fire; we still use the enum so
//  ErrorBubbleView can render meaningful messages from streaming errors.
//

import Foundation

enum APIError: Error {
    case requestFailed(Error)
    case invalidResponse
    case decodingFailed(String)
    case unauthorized
    case rateLimited
    case serverError(String)
    case unknown(String)
    case noApiService(String)
    case attachmentNotReady(String)

    var displayTitle: String {
        switch self {
        case .requestFailed: return "Connection Error"
        case .invalidResponse: return "Invalid Response"
        case .decodingFailed: return "Decoding Error"
        case .unauthorized: return "Authentication Required"
        case .rateLimited: return "Rate Limited"
        case .serverError: return "Server Error"
        case .unknown: return "Unknown Error"
        case .noApiService: return "No API Service"
        case .attachmentNotReady: return "Attachment Not Ready"
        }
    }

    var displayMessage: String {
        switch self {
        case .requestFailed(let e): return e.localizedDescription
        case .invalidResponse: return "The server returned an unexpected response."
        case .decodingFailed(let m): return m
        case .unauthorized: return "Your Apple Intelligence session could not be authorized."
        case .rateLimited: return "Apple Intelligence is rate-limiting requests."
        case .serverError(let m): return m
        case .unknown(let m): return m
        case .noApiService(let m): return m
        case .attachmentNotReady(let m): return m
        }
    }

    var isRetryable: Bool {
        switch self {
        case .requestFailed, .rateLimited, .serverError: return true
        case .invalidResponse, .decodingFailed, .unauthorized, .unknown, .noApiService, .attachmentNotReady:
            return false
        }
    }
}
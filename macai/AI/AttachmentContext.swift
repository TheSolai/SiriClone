//
//  AttachmentContext.swift
//  SiriClone
//
//  Pulls attachment content (PDF, images) into a format the active chat
//  provider can consume. The two providers have different ingestion strategies:
//    - Local LLM: OpenAI multimodal — `image_url` content parts with data
//      URIs for images, plain text content parts for PDF text.
//    - Apple Intelligence: text-only — we extract PDF text via PDFKit and
//      prepend image metadata (dimensions, format) since Foundation Models
//      doesn't accept images natively.
//
//  Output:
//    - textContext:    String to prepend to the prompt (works for both providers).
//    - imagePayloads:  Array of (filename, base64 JPEG, mimeType) for the
//                      local LLM to attach as image_url content parts.
//
//  Hard caps protect the model from huge attachments:
//    - Max 8 MB extracted per attachment
//    - Max 64 KB total extracted text per call
//

import AppKit
import Foundation
import PDFKit

@available(macOS 26.0, *)
@MainActor
struct AttachmentContext {

    /// Text to inject into the prompt. Includes PDF text + image metadata.
    let textContext: String

    /// Image payloads for OpenAI multimodal (local LLM backend).
    struct ImagePayload {
        let filename: String
        let base64JPEG: String
        let mimeType: String
    }
    let imagePayloads: [ImagePayload]

    /// Empty context — no attachments.
    static let empty = AttachmentContext(textContext: "", imagePayloads: [])

    private static let maxPDFBytes: Int = 8 * 1024 * 1024  // 8 MB
    private static let maxTotalTextChars: Int = 64 * 1024   // 64 KB

    /// Build context from current attachments.
    static func build(
        attachedFiles: [DocumentAttachment],
        attachedImages: [ImageAttachment]
    ) -> AttachmentContext {
        var textParts: [String] = []
        var imagePayloads: [ImagePayload] = []

        // PDF text extraction
        for file in attachedFiles {
            guard let url = file.previewURL() ?? file.url else { continue }
            let filename = url.lastPathComponent
            let extracted = extractPDFText(from: url, maxBytes: maxPDFBytes)
            if !extracted.isEmpty {
                textParts.append("[PDF attachment: \(filename)]\n\(extracted)\n[/PDF]")
            } else {
                textParts.append("[PDF attachment: \(filename) — text could not be extracted, possibly scanned. Use file_read or run_shell to inspect it.]")
            }
        }

        // Image metadata + base64 (for local LLM with vision)
        for image in attachedImages {
            let filename = image.url?.lastPathComponent ?? "image.jpg"
            let dims: String
            if let img = image.image {
                dims = "\(Int(img.size.width))×\(Int(img.size.height))"
            } else {
                dims = "unknown"
            }
            textParts.append("[Image attachment: \(filename) — \(dims) PNG/JPEG]")
            if let base64 = image.toBase64() {
                let mime = image.originalFileType.preferredMIMEType ?? "image/jpeg"
                imagePayloads.append(ImagePayload(
                    filename: filename,
                    base64JPEG: base64,
                    mimeType: mime
                ))
            }
        }

        // Cap text length to protect prompt budget.
        var combined = textParts.joined(separator: "\n\n")
        if combined.count > maxTotalTextChars {
            let truncated = String(combined.prefix(maxTotalTextChars))
            combined = truncated + "\n\n[... attachment content truncated ...]"
        }

        return AttachmentContext(textContext: combined, imagePayloads: imagePayloads)
    }

    /// Render the text context as a block suitable for prepending to a
    /// user prompt. Returns "" when no attachments were present.
    func formattedPrefix() -> String {
        guard !textContext.isEmpty else { return "" }
        return """

        ── ATTACHMENT CONTEXT ──
        The user attached files. Use this content to answer.

        \(textContext)

        ── END ATTACHMENT CONTEXT ──

        """
    }

    // MARK: - PDF text extraction

    private static func extractPDFText(from url: URL, maxBytes: Int) -> String {
        guard let doc = PDFDocument(url: url) else { return "" }
        var out = ""
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            guard let s = page.string else { continue }
            out += s
            out += "\n\n"
            if out.utf8.count > maxBytes {
                out += "\n[... PDF truncated at \(maxBytes) bytes ...]"
                break
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
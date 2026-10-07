//
//  ChatBottomContainerView.swift
//  macai
//
//  Created by Renat on 19.01.2025.
//
import SwiftUI

struct ChatBottomContainerView: View {
    @ObservedObject var chat: ChatEntity
    @Binding var newMessage: String
    @Binding var isExpanded: Bool
    @Binding var attachedImages: [ImageAttachment]
    @Binding var attachedFiles: [DocumentAttachment]
    let isInferenceInProgress: Bool
    let isEditingSystemMessage: Bool
    var imageUploadsAllowed: Bool
    var pdfUploadsAllowed: Bool
    var imageGenerationSupported: Bool
    var onSendMessage: () -> Void
    var onExpandToggle: () -> Void
    var onAddImage: () -> Void
    var onAddFile: () -> Void
    var onStopInference: () -> Void
    var onCancelEdit: () -> Void
    var onExpandedStateChange: ((Bool) -> Void)?  // Add this line

    init(
        chat: ChatEntity,
        newMessage: Binding<String>,
        isExpanded: Binding<Bool>,
        attachedImages: Binding<[ImageAttachment]> = .constant([]),
        attachedFiles: Binding<[DocumentAttachment]> = .constant([]),
        isInferenceInProgress: Bool = false,
        isEditingSystemMessage: Bool = false,
        imageUploadsAllowed: Bool = false,
        pdfUploadsAllowed: Bool = false,
        imageGenerationSupported: Bool = false,
        onSendMessage: @escaping () -> Void,
        onExpandToggle: @escaping () -> Void = {},
        onAddImage: @escaping () -> Void = {},
        onAddFile: @escaping () -> Void = {},
        onStopInference: @escaping () -> Void = {},
        onCancelEdit: @escaping () -> Void = {},
        onExpandedStateChange: ((Bool) -> Void)? = nil
    ) {
        self.chat = chat
        self._newMessage = newMessage
        self._isExpanded = isExpanded
        self._attachedImages = attachedImages
        self._attachedFiles = attachedFiles
        self.isInferenceInProgress = isInferenceInProgress
        self.isEditingSystemMessage = isEditingSystemMessage
        self.imageUploadsAllowed = imageUploadsAllowed
        self.pdfUploadsAllowed = pdfUploadsAllowed
        self.imageGenerationSupported = imageGenerationSupported
        self.onSendMessage = onSendMessage
        self.onExpandToggle = onExpandToggle
        self.onAddImage = onAddImage
        self.onAddFile = onAddFile
        self.onStopInference = onStopInference
        self.onCancelEdit = onCancelEdit
        self.onExpandedStateChange = onExpandedStateChange

        if chat.messagesArray.isEmpty {
            DispatchQueue.main.async {
                isExpanded.wrappedValue = true
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                VStack {
                    if isExpanded {
                        PersonaSelectorView(chat: chat)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                HStack {
                    MessageInputView(
                        text: $newMessage,
                        attachedImages: $attachedImages,
                        attachedFiles: $attachedFiles,
                        isInferenceInProgress: isInferenceInProgress,
                        isEditingSystemMessage: isEditingSystemMessage,
                        imageUploadsAllowed: imageUploadsAllowed,
                        pdfUploadsAllowed: pdfUploadsAllowed,
                        imageGenerationSupported: imageGenerationSupported,
                        onEnter: onSendMessage,
                        onAddImage: onAddImage,
                        onAddFile: onAddFile,
                        onStopInference: onStopInference,
                        onCancelEdit: onCancelEdit
                    )
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .padding()
                }
                .border(width: 1, edges: [.top], color: Color(NSColor.windowBackgroundColor).opacity(0.8))
            }

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                    onExpandedStateChange?(isExpanded)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 13))
                    Text(chat.persona?.name ?? "Select Assistant")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(NSColor.windowBackgroundColor).opacity(0.9))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .help("Switch agent / persona")
            .padding(.trailing, 12)
            .offset(y: -10)
        }

    }
}

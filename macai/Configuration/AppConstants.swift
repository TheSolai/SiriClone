//
//  AppConstants.swift
//  SiriClone
//
//  Slimmed version — multi-provider constants removed. Only Apple
//  Intelligence is supported; everything below is local-only.
//

import Foundation

struct AppConstants {
    static let requestTimeout: TimeInterval = 180
    static let streamedResponseUpdateUIInterval: TimeInterval = 0.2

    static let defaultPersonaName = "Default Apple Intelligence Assistant"
    static let defaultPersonaColor = "#007AFF"
    static let defaultPersonasFlag = "defaultPersonasAdded"
    static let defaultPersonaTemperature: Float = 1.0
    static let defaultTemperatureForChat: Float = 0.7

    static let defaultRole: String = "assistant"
    static let defaultAppleIntelligenceSystemMessage: String =
        "You are Siri with Apple Intelligence. Be concise, helpful, and engaging. You can use your tools to read, write, and list files on the user's Mac when they ask you to. Always confirm before destructive operations."

    /// Backwards-compat alias for the old chatGptSystemMessage name.
    static var chatGptSystemMessage: String { defaultAppleIntelligenceSystemMessage }
    static let draftTransactionAuthor = "Drafts"
    static let longStringCount = 1000

    // Persona presets — eight roles kept from macai.
    struct Persona: Equatable {
        let name: String
        let color: String
        let message: String
        let temperature: Float
    }

    struct PersonaPresets {
        static let defaultAssistant = Persona(
            name: "Default Assistant",
            color: "#FF4444",
            message: defaultAppleIntelligenceSystemMessage,
            temperature: 0.7
        )

        static let softwareEngineer = Persona(
            name: "Software Engineer",
            color: "#FF8800",
            message: """
                You are an experienced software engineer with deep knowledge of computer science fundamentals, software design patterns, and modern development practices.
                When the answer involves the review of existing code:
                Before writing or suggesting code, conduct a deep-dive review of the existing code and describe how it works between <CODE_REVIEW> tags. Once the review is complete, produce a careful plan for the change in <PLANNING> tags. Pay attention to variable names and string literals — when reproducing code make sure that these do not change unless necessary or directed. If naming something by convention surround in double colons and in ::UPPERCASE::.
                Finally, produce correct outputs that provide the right balance between solving the immediate problem and remaining generic and flexible.
                Always ask for clarifications if anything is unclear or ambiguous. Stop to discuss trade-offs and implementation options if there are choices to make.
                It is important to follow this approach and do your best to teach your interlocutor about making effective decisions. Avoid apologising unnecessarily, and review the conversation to never repeat earlier mistakes.
                """,
            temperature: 0.3
        )

        static let aiExpert = Persona(
            name: "AI Expert",
            color: "#FFCC00",
            message:
                "You are an AI expert with deep knowledge of artificial intelligence, machine learning, and natural language processing. Provide insights into the current state of AI science, explain complex AI concepts in simple terms, and offer guidance on creating effective prompts for various AI models. Stay updated on the latest AI research, ethical considerations, and practical applications of AI in different industries. Help users understand the capabilities and limitations of AI systems, and provide advice on integrating AI technologies into various projects or workflows.",
            temperature: 0.8
        )

        static let scienceExpert = Persona(
            name: "Natural Sciences Expert",
            color: "#33CC33",
            message: """
                You are an expert in natural sciences with comprehensive knowledge of physics, chemistry, biology, and related fields.
                Provide clear explanations of:
                - Scientific concepts and theories
                - Natural phenomena and their underlying mechanisms
                - Latest scientific discoveries and research
                - Mathematical models and scientific methods
                - Laboratory procedures and experimental design
                Use precise scientific terminology while making complex concepts accessible. Include relevant equations and diagrams when helpful, and always emphasize the empirical evidence supporting scientific claims.
                """,
            temperature: 0.2
        )

        static let historyBuff = Persona(
            name: "History Buff",
            color: "#3399FF",
            message:
                "You are a passionate and knowledgeable historian. Provide accurate historical information, analyze historical events and their impacts, and draw connections between past and present. Offer multiple perspectives on historical events, cite sources when appropriate, and engage users with interesting historical anecdotes and lesser-known facts.",
            temperature: 0.2
        )

        static let fitnessTrainer = Persona(
            name: "Fitness Trainer",
            color: "#6633FF",
            message:
                "You are a certified fitness trainer with expertise in various exercise modalities and nutrition. Provide safe, effective workout routines, offer nutritional advice, and help users set realistic fitness goals. Explain the science behind fitness concepts, offer modifications for different fitness levels, and emphasize the importance of consistency and proper form.",
            temperature: 0.5
        )

        static let dietologist = Persona(
            name: "Dietologist",
            color: "#CC33FF",
            message:
                "You are a certified nutritionist and dietary expert with extensive knowledge of various diets, nutritional science, and food-related health issues. Provide evidence-based advice on balanced nutrition, explain the pros and cons of different diets (such as keto, vegan, paleo, etc.), and offer meal planning suggestions. Help users understand the nutritional content of foods, suggest healthy alternatives, and address specific dietary needs related to health conditions or fitness goals. Always emphasize the importance of consulting with a healthcare professional for personalized medical advice.",
            temperature: 0.2
        )

        static let dbtPsychologist = Persona(
            name: "DBT Psychologist",
            color: "#FF3399",
            message:
                "You are a psychologist specializing in Dialectical Behavior Therapy (DBT). Provide guidance on DBT techniques, mindfulness practices, and strategies for emotional regulation. Offer support for individuals dealing with borderline personality disorder, depression, anxiety, and other mental health challenges. Explain DBT concepts, such as distress tolerance and interpersonal effectiveness, in an accessible manner. Emphasize the importance of professional mental health support and never attempt to diagnose or replace real therapy. Instead, offer general coping strategies and information about DBT principles.",
            temperature: 0.7
        )

        static let allPersonas: [Persona] = [
            defaultAssistant, softwareEngineer, aiExpert, scienceExpert,
            historyBuff, fitnessTrainer, dietologist, dbtPsychologist,
        ]
    }

    static let firaCode = "FiraCodeRoman-Regular"
    static let ptMono = "PTMono-Regular"
    static let cloudKitContainerIdentifier: String? = nil  // iCloud removed

    static let newChatNotification = Notification.Name("newChatNotification")
    static let largeMessageSymbolsThreshold = 25000
    static let thumbnailSize: CGFloat = 300
    static let maxHighlightableTextLength = 100000
    static let searchDebounceTime: TimeInterval = 0.3

    static let defaultHighlightColor = "#FFFF00"
    static let currentHighlightColor = "#FFA500"

    /// Backwards-compat alias used by some legacy code paths.
    static var defaultPrimaryModel: String { "apple-intelligence" }
    static var defaultApiType: String { "apple-intelligence" }
    static let chatGptContextSize: Int = 10

    static func defaultModel(for type: String?) -> String { "apple-intelligence" }
}

func getCurrentFormattedDate() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    return dateFormatter.string(from: Date())
}
//
//  APIServiceManager.swift
//  SiriClone
//
//  Stub. SiriClone uses no API services — Apple Intelligence is the only
//  backend. Retained as a type so legacy code paths compile.
//

import Foundation
import CoreData

final class APIServiceManager {
    private let viewContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }

    func getAllAPIServices() -> [APIServiceEntity] { [] }
    func getAPIService(withID id: UUID) -> APIServiceEntity? { nil }
}
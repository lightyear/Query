//
//  CoreDataTestCase.swift
//  QueryTests
//
//  Created by Steve Madsen on 3/8/22.
//  Copyright © 2022 Light Year Software, LLC
//

import CoreData
import XCTest

class CoreDataTestCase: XCTestCase {
    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let testBundle = Bundle(for: Self.self)
        let resources = Bundle(url: testBundle.resourceURL!.appendingPathComponent("Query_QueryTests.bundle"))!
        let model = NSManagedObjectModel(contentsOf: resources.url(forResource: "QueryTests", withExtension: "momd")!)!
        container = NSPersistentContainer(name: "QueryTests", managedObjectModel: model)
        container.persistentStoreDescriptions[0].url = URL(fileURLWithPath: "/dev/null")
        container.loadPersistentStores { _, _ in }
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.parent = container.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }
}

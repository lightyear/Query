//
//  Entity.swift
//  QueryTests
//
//  Created by Steve Madsen on 3/8/22.
//  Copyright © 2018-22 Light Year Software, LLC
//

import CoreData
import Query

class Entity: NSManagedObject, Identifiable, Queryable {
    @NSManaged var id: UUID
    @NSManaged var number: Int32
    @NSManaged var text: String
    @NSManaged var text2: String

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
    }
    
    enum Attribute {
        case id, number, text
    }
}

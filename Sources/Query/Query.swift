//
//  Query.swift
//  Query
//
//  Created by Steve Madsen on 2/18/18.
//  Copyright © 2018-22 Light Year Software, LLC
//

import CoreData

/** Classes that conform to this protocol may use the `Query<T>` query builder.

The only requirement to conform to this protocol is the definition of the `Attribute`
associated type. Typically, this is a simple enum with a String raw value type,
whose cases are the names of the attributes that you want to query. Use these
in calls to the dictionary forms of `where` and `or` for type-safe conditions,
instead of stringly-typed conditions.
*/
public protocol Queryable {
    associatedtype Attribute: Hashable
}

public extension NSFetchRequestResult where Self: NSManagedObject, Self: Queryable {
    static func query(in context: NSManagedObjectContext) -> Query<Self> {
        Query<Self>(in: context)
    }

    func query() -> Query<Self> {
        Query<Self>(in: managedObjectContext!)
    }
}

public enum QueryError: Error {
    case tooComplex
}

/// A chainable query builder for Core Data.
public struct Query<T> where T: NSManagedObject & Queryable {
    public enum SortDirection {
        case ascending
        case descending
    }

    public enum Selector {
        case none
        case localizedStandard
        case localizedCaseInsensitive
    }

    public let context: NSManagedObjectContext
    var predicates = [NSPredicate]()
    var sortDescriptors = [NSSortDescriptor]()
    var defaultValues: [String: Any]? = [:]

    public init(in context: NSManagedObjectContext) {
        self.context = context
    }

    public var fetchRequest: NSFetchRequest<T> {
        let entityName = "\(T.self)"
        let fetchRequest = NSFetchRequest<T>(entityName: entityName)
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        fetchRequest.sortDescriptors = sortDescriptors
        return fetchRequest
    }

    public func all() throws -> [T] {
        try context.fetch(fetchRequest)
    }

    public func count() throws -> Int {
        try context.count(for: fetchRequest)
    }

    public func first() throws -> T? {
        let fetchRequest = self.fetchRequest
        fetchRequest.fetchLimit = 1
        let results = try context.fetch(fetchRequest)
        return results.first
    }

    public func firstOrInsert() throws -> T {
        guard let defaultValues = defaultValues else { throw QueryError.tooComplex }

        if let first = try first() {
            return first
        }

        let new = NSEntityDescription.insertNewObject(forEntityName: "\(T.self)", into: context) as! T
        new.setValuesForKeys(defaultValues)
        return new
    }

    public func order(by attribute: T.Attribute, _ direction: SortDirection = .ascending, _ selector: Selector = .none) -> Query<T> {
        order(by: "\(attribute)", direction, selector)
    }

    public func order(by attribute: String, _ direction: SortDirection = .ascending, _ selector: Selector = .none) -> Query<T> {
        var query = self
        switch selector {
        case .none:
            query.sortDescriptors.append(NSSortDescriptor(key: attribute, ascending: direction == .ascending))
        case .localizedStandard:
            query.sortDescriptors.append(NSSortDescriptor(key: attribute, ascending: direction == .ascending, selector: #selector(NSString.localizedStandardCompare(_:))))
        case .localizedCaseInsensitive:
            query.sortDescriptors.append(NSSortDescriptor(key: attribute, ascending: direction == .ascending, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:))))
        }
        return query
    }

    public func `where`(_ format: String, _ args: Any...) -> Query<T> {
        var query = self
        query.predicates.append(NSPredicate(format: format, argumentArray: args))
        query.defaultValues = nil
        return query
    }

    public func `where`(_ dictionary: [T.Attribute: Any]) -> Query<T> {
        var query = self
        query.predicates.append(andSubpredicate(from: dictionary))

        for (key, value) in dictionary {
            switch value {
            case is Inequality, is CountableRange<Int>, is CountableClosedRange<Int>:
                query.defaultValues = nil
            default:
                query.defaultValues?["\(key)"] = value
            }
        }

        return query
    }

    private func andSubpredicate(from dictionary: [T.Attribute: Any]) -> NSCompoundPredicate {
        var predicates = [NSPredicate]()
        for (attribute, value) in dictionary {
            switch value {
            case let inequality as Inequality:
                switch inequality {
                case .lessThan(let value):
                    predicates.append(NSPredicate(format: "%K < %@", argumentArray: ["\(attribute)", value]))
                case .lessThanOrEqual(let value):
                    predicates.append(NSPredicate(format: "%K <= %@", argumentArray: ["\(attribute)", value]))
                }
            case let range as CountableRange<Int>:
                predicates.append(NSPredicate(format: "%K BETWEEN %@", "\(attribute)", [range.lowerBound, range.upperBound - 1]))
            case let range as CountableClosedRange<Int>:
                predicates.append(NSPredicate(format: "%K BETWEEN %@", "\(attribute)", [range.lowerBound, range.upperBound]))
            default:
                predicates.append(NSPredicate(format: "%K == %@", argumentArray: ["\(attribute)", value]))
            }
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    public func or(_ format: String, args: Any...) -> Query<T> {
        var query = self
        guard let lastPredicate = query.predicates.popLast() else {
            preconditionFailure("No existing “where” condition to modify with “or”")
        }
        query.predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [lastPredicate, NSPredicate(format: format, argumentArray: args)]))
        query.defaultValues = nil
        return query
    }

    public func or(_ dictionary: [T.Attribute: Any]) -> Query<T> {
        var query = self
        guard let lastPredicate = query.predicates.popLast() else {
            preconditionFailure("No existing “where” condition to modify with “or”")
        }
        query.predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [lastPredicate, andSubpredicate(from: dictionary)]))
        query.defaultValues = nil
        return query
    }
}

public extension Query where T: Identifiable {
    /**
     Check if an object exists with the provided ID.

     - Parameter id: the unique identifier of the object
     - Returns: `true` if an object matching the ID exists, `false` otherwise.
     */
    func exists(_ id: T.ID) throws -> Bool {
        try `where`("id == %@", id).count() > 0
    }

    /**
     Fetch the object matching the provided ID.

     - Parameter id: the unique identifier of the object
     - Returns: The object if it exists or `nil` if it does not.
     */
    func fetch(_ id: T.ID) throws -> T? {
        try `where`("id == %@", id).first()
    }

    /**
     Fetch the object matching the provided ID or insert a new object if one with
     the ID does not exist.

     - Parameter id: the unique identifier of the object
     - Returns: An object instance with its ID set to the provided identifier.
     */
    func fetchOrInsert(_ id: T.ID) throws -> T {
        if let object = try fetch(id) {
            return object
        } else {
            let new = NSEntityDescription.insertNewObject(forEntityName: "\(T.self)", into: context) as! T
            new.setValue(id, forKey: "id")
            return new
        }
    }
}

public enum Inequality {
    case lessThan(Any)
    case lessThanOrEqual(Any)
}

public func lt(_ value: Any) -> Inequality {
    Inequality.lessThan(value)
}

public func lte(_ value: Any) -> Inequality {
    Inequality.lessThanOrEqual(value)
}

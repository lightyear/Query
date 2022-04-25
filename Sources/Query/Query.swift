//
//  Query.swift
//  Query
//
//  Created by Steve Madsen on 2/18/18.
//  Copyright © 2018-22 Light Year Software, LLC
//

import CoreData

/**
 Classes that conform to this protocol may use the `Query<T>` query builder's
 `Attribute`-focused functions.

 `Attribute` is typically a simple enum, whose cases are the names of the
 attributes that you want to query. Use these in calls to the dictionary forms of
 `where` and `or` for type-safe conditions, instead of stringly-typed conditions.
*/
public protocol Queryable {
    associatedtype Attribute: Hashable
}

public extension NSFetchRequestResult where Self: NSManagedObject {
    /**
     Create a new `Query` builder tied to the provided context.

     - Parameter context: the managed object context in which to query for objects
     - Returns: A new `Query` instance
    */
    static func query(in context: NSManagedObjectContext) -> Query<Self> {
        Query<Self>(in: context)
    }

    /**
     Create a new `Query` builder tied to the managed object context of this instance.

     - Returns: A new `Query` instance
     */
    func query() -> Query<Self> {
        Query<Self>(in: managedObjectContext!)
    }
}

/// Errors thrown by the Query library.
public enum QueryError: Error {
    /**
     The current `Query` instance is too complex for the desired result.

     This error is thrown from `firstOrInsert()` when the predicate part of the
     query is formed from stringly-typed clauses or inequalities.

     In the former case, this library does not include a parser to deconstruct
     the predicate string to discover default property values. In the latter,
     there are multiple values that would match the predicate and it doesn't
     make sense to pick one at random.
     */
    case tooComplex
}

/**
 A chainable query builder for Core Data.

 Note that `Query` is a value type and none of its functions are mutating.
 Functions that return a `Query` return new instances with the additional
 functionality applied. You can chain calls to build up a complex fetch request.
*/
public struct Query<T> where T: NSManagedObject {
    /// The sort order used in calls to `order(by:_:_:)`.
    public enum SortDirection {
        /// Results should be sorted by increasing value (1, 2, 3, ...).
        case ascending
        /// Results should be sorted by decreasing value (3, 2, 1, ...).
        case descending
    }

    /// The selector to use when sorting string values in calls to `order(by:_:_:)`.
    public enum Selector {
        /// Default (case sensitive, locale unaware) comparison.
        case none
        /// A standardized, locale-aware comparison. This is equivalent to `StringProtocol.localizedStandardCompare(_:)`.
        case localizedStandard
        /// A case insensitive, locale-aware comparison. This is equivalent to `StringProtocol.localizedCaseInsensitiveCompare(_:)`.
        case localizedCaseInsensitive
    }

    /// The managed object context in which the query will be executed.
    public let context: NSManagedObjectContext
    var predicates = [NSPredicate]()
    var sortDescriptors = [NSSortDescriptor]()
    var defaultValues: [String: Any]? = [:]

    /**
     Initializes a new `Query` instance with the provided managed object context.

     - Parameter context: the managed object context in which to query for objects
     */
    public init(in context: NSManagedObjectContext) {
        self.context = context
    }

    /// Returns a new `NSFetchRequest` instance with the same predicate and sort order as this `Query` instance.
    public var fetchRequest: NSFetchRequest<T> {
        let entityName = "\(T.self)"
        let fetchRequest = NSFetchRequest<T>(entityName: entityName)
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        fetchRequest.sortDescriptors = sortDescriptors
        return fetchRequest
    }

    /**
     Fetches all objects matching this `Query` instance.

     - Throws: Rethrows errors from the underlying `NSManagedObject.fetch(_:)` call.
     - Returns: All matching managed objects from the `Query`'s context.
     */
    public func all() throws -> [T] {
        try context.fetch(fetchRequest)
    }

    /**
     Counts the number of objects matching this `Query` instance.

     - Throws: Rethrows errors from the underlying `NSManagedObject.count(for:)` call.
     - Returns: The number of matching managed objects in the `Query`'s context.
     */
    public func count() throws -> Int {
        try context.count(for: fetchRequest)
    }

    /**
     Fetches the first object matching this `Query` instance.

     "First" only has useful meaning if the results are sorted.

     - Throws: Rethrows errors from the underlying `NSManagedObject.fetch(_:)` call.
     - Returns: The first matching object from the `Query`'s context or `nil` if
       no objects match.
     */
    public func first() throws -> T? {
        let fetchRequest = self.fetchRequest
        fetchRequest.fetchLimit = 1
        let results = try context.fetch(fetchRequest)
        return results.first
    }

    /**
     Adds a level of sorting to the `Query`.

     - Parameter attribute: the name of the property by which to sort
     - Parameter direction: the direction of the sort (default is `.ascending`)
     - Parameter selector: for string values, the selector to use for comparisons
       (default is `.none`, a case sensitive, locale-unaware comparison)
     - Returns: A new `Query` with the sort applied
     */
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

    /**
     Add a filtering predicate to the `Query`.

     The predicate in this function is combined with any existing predicates on
     the `Query` with an AND. After calling this function, `firstOrInsert()`
     cannot be used on the resulting `Query` because the matching property values
     are not parsed from the format string.

     - Parameter format: the `NSPredicate` format string
     - Parameter args: arguments matching up to format string placeholders, if any
     - Returns: A new `Query` with the predicate applied
     */
    public func `where`(_ format: String, _ args: Any...) -> Query<T> {
        var query = self
        query.predicates.append(NSPredicate(format: format, argumentArray: args))
        query.defaultValues = nil
        return query
    }

    /**
     Add a filtering predicate to the `Query`.

     The predicate in this function is combined with any existing predicates on
     the `Query` with an OR. After calling this function, `firstOrInsert()`
     cannot be used on the resulting `Query` because the matching property values
     are not parsed from the format string.

     - Parameter format: the `NSPredicate` format string
     - Parameter args: arguments matching up to format string placeholders, if any
     - Returns: A new `Query` with the predicate applied
     */
    public func or(_ format: String, args: Any...) -> Query<T> {
        var query = self
        guard let lastPredicate = query.predicates.popLast() else {
            preconditionFailure("No existing “where” condition to modify with “or”")
        }
        query.predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [lastPredicate, NSPredicate(format: format, argumentArray: args)]))
        query.defaultValues = nil
        return query
    }
}

public extension Query where T: Queryable {
    /**
     Find the first matching object in the context or insert and return a new one.

     This function only works when the predicates are built using the dictionary
     forms of `where(_:)` and `.or(_:)`, and only when using strict equality
     tests.

     - Throws: Rethrows errors from the underlying `NSManagedObject.fetch(_:)`
       call or `QueryError.tooComplex` if the default property values cannot be
       determined.
     - Returns: The first matching object or a newly inserted object with its
       properties set to match the `Query` filter predicate.
     */
    func firstOrInsert() throws -> T {
        guard let defaultValues = defaultValues else { throw QueryError.tooComplex }

        if let first = try first() {
            return first
        }

        let new = NSEntityDescription.insertNewObject(forEntityName: "\(T.self)", into: context) as! T
        new.setValuesForKeys(defaultValues)
        return new
    }

    /**
     Adds a level of sorting to the `Query`.

     - Parameter attribute: the property by which to sort
     - Parameter direction: the direction of the sort (default is `.ascending`)
     - Parameter selector: for string values, the selector to use for comparisons
       (default is `.none`, a case sensitive, locale-unaware comparison)
     - Returns: A new `Query` with the sort applied
     */
    func order(by attribute: T.Attribute, _ direction: SortDirection = .ascending, _ selector: Selector = .none) -> Query<T> {
        order(by: "\(attribute)", direction, selector)
    }

    /**
     Add a filtering predicate to the `Query`.

     The predicate in this function is combined with any existing predicates on
     the `Query` with an AND.

     - Parameter dictionary: the properties and the values expected to match.
       Values can include inequalities wrapped in `lt` or `lte`, or Swift ranges.
     - Returns: A new `Query` with the predicate applied
     */
    func `where`(_ dictionary: [T.Attribute: Any]) -> Query<T> {
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

    /**
     Add a filtering predicate to the `Query`.

     The predicate in this function is combined with any existing predicates on
     the `Query` with an OR. After calling this function, `firstOrInsert()`
     cannot be used on the resulting `Query` because the matching property values
     are indeterminant.

     - Parameter dictionary: the properties and the values expected to match.
       Values can include inequalities wrapped in `lt` or `lte`, or Swift ranges.
     - Returns: A new `Query` with the predicate applied
     */
    func or(_ dictionary: [T.Attribute: Any]) -> Query<T> {
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

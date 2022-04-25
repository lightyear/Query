# Query

Query is a fluent-style query builder for Core Data.

## Install

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Flightyear%2FQuery%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/lightyear/Query)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Flightyear%2FQuery%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/lightyear/Query)

Installation is done through Swift Package Manager. Paste the URL of this repo into Xcode or add this line to your `Package.swift`:

    .package(url: "https://github.com/lightyear/Query", from: "1.0.0")

## Usage

Querying Core Data managed object contexts involves a lot of boilerplate code. This package provides a new `Query<T>` type that is a fluent-style, chainable query builder:

    class Entity: NSManagedObject { ... }

    try Entity.query(in: someManagedObjectContext)
        .where("quantity == 1")
        .order(by: "date")
        .all()
    // result is [Entity] or a thrown error

If your managed object subclasses also conform to the `Queryable` protocol and supply a nested `Attribute` type, additional overrides for `.where()` and `.order()` are available that accept attributes that can be checked by the compiler, instead of strings:

    extension Entity: Queryable {
        enum Attribute {
            case quantity, date
        }
    }
    
    try Entity.query(in: someManagedObjectContext)
        .where([.quantity: 1])
        .order(by: .date)
        .all()
    // result is [Entity] or a thrown error
    
([SR-5220 Expose API to retrieve string representation of KeyPath](https://bugs.swift.org/browse/SR-5220) is a much better way to support something like this. If we ever get it, `Queryable` will be deprecated.)

### Predicates

The basic filtering predicate is `.where()`. It accepts the same arguments as `NSPredicate` or, if the managed object subclass conforms to `Queryable`, an additional version that takes a `Dictionary` keyed by attributes:

    where("quantity == 1")
    where("quantity == %d", 1)
    where("name == %@", "Alice")
    where("%K == %@", "name", "Alice")
    where([.quantity: 1])
    where([.name: "Alice"])
    
Chained calls to `.where()` combine with AND:

    where("quantity == 1").where("name == %@", "Alice")
    // same as where("quantity == 1 AND name == %@", "Alice")

There is also `.or()`:

    where("quantity == 1").or("name == %@", "Alice")
    // same as where("quantity == 1 OR name == %@", "Alice")

When combined with `.where()`, `.or()` treats everything before it as if it were wrapped in a set of parentheses. 

    where("quantity == 1").where("name == %@", "Alice").or("name == %@", "Bob")
    // same as where("(quantity == 1 AND name == %@) OR name == %@", "Alice", "Bob")

The dictionary forms of `.where()` and `.or()` support inequality wrappers around values and ranges:

    where([.quantity: lt(1)])  // same as where("quantity < 1")
    where([.quantity: 1...3])  // same as where("quantity BETWEEN (1,3)")
    
### Ordering

Adding one or more sort descriptors is done with `order()`:

    order(by: "department").order(by: "name")
    
The default sort order is ascending, but descending is an option:

    order(by: "quantity", .descending)
    
String values can also be sorted case-insensitively or using a localized comparison:

    order(by: "name", .ascending, .localizedCaseInsensitive)
    order(by: "name", .ascending, .localizedStandard)

### Fetching result objects or counts

All of the matching results in the requested order (if specified) are fetched by calling `.all()`. If you only want the first matching result, use `.first()`. If you only care about the number of matching objects, use `.count()`.

If your managed object subclass conforms to `Queryable`, you use the typed `Attribute` version of `.where()` without inequalities or `.or()` conditions, `.firstOrInsert()` will fetch the first match or insert a new instance into the context with its properties set to the query conditions. It throws `QueryError.tooComplex` in cases where the initial values are indeterminant.

### Getting the underlying fetch request

If you need a real `NSFetchRequest` matching the current query, you can get it from the `fetchRequest` property. This is useful for further customizing the fetch request or handing it to an `NSFetchedResultsController`.

### `Identifiable` managed objects

Managed object subclasses that also conform to `Identifiable` gain a few additional query functions. `exists(_:)` returns `true` if an object exists in the context with the provided ID.

`fetch(_:)` returns the instance with the provided ID or `nil` if no object exists in the context with that ID.

`fetchOrInsert(_:)` returns the instance with the provided ID or, if no object exists with it already, a new instance with the `id` property set to that ID.

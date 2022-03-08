//
//  QueryTests.swift
//  Query
//
//  Created by Steve Madsen on 2/18/18.
//  Copyright © 2018-22 Light Year Software, LLC
//

import XCTest
import Nimble
@testable import Query

class QueryTests: CoreDataTestCase {
    var query: Query<Entity>!

    override func setUp() {
        super.setUp()
        
        query = Query<Entity>(in: context)
    }

    override func tearDown() {
        query = nil
        super.tearDown()
    }

    func newEntity() -> Entity {
        NSEntityDescription.insertNewObject(forEntityName: "Entity", into: context) as! Entity
    }

    func testAll() {
        let e1 = newEntity()
        let e2 = newEntity()
        let all = try! query.all()
        expect(all.count) == 2
        expect(all).to(contain(e1))
        expect(all).to(contain(e2))
    }

    func testCount() {
        (1...10).forEach { _ in _ = newEntity() }
        expect(try self.query.count()) == 10
    }

    func testExists() {
        let entry = newEntity()
        expect(try self.query.exists(entry.id)) == true
        expect(try self.query.exists(UUID())) == false
    }

    func testFetch() {
        let entry = newEntity()
        expect(try self.query.fetch(entry.id)) === entry
        expect(try self.query.fetch(UUID())).to(beNil())
    }

    func testFetchOrInsert() {
        let entry = newEntity()
        expect(try self.query.fetchOrInsert(entry.id)) === entry
        let inserted = try! self.query.fetchOrInsert(UUID())
        expect(inserted).toNot(beNil())
        expect(inserted) !== entry
    }

    func testFirst() {
        let entry = newEntity()
        expect(try self.query.first()) === entry
    }

    func testFirstNoResults() {
        expect(try self.query.first()).to(beNil())
    }

    func testFirstOrInsertReturnsExisting() {
        let entity = newEntity()
        entity.number = 1
        expect(try self.query.where([.number: 1]).firstOrInsert()) === entity
    }

    func testFirstOrInsertNoMatch() {
        let entity = try! query.where([.text: "foo", .number: 1]).firstOrInsert()
        expect(entity.text) == "foo"
        expect(entity.number) == 1
    }

    func testFirstOrCreateWithComplexQueryThrows() {
        expect { try self.query.where("number2 == 1").firstOrInsert() }.to(throwError(QueryError.tooComplex))
        expect { try self.query.where([.number: lt(1)]).firstOrInsert() }.to(throwError(QueryError.tooComplex))
        expect { try self.query.where([.number: 1...3]).firstOrInsert() }.to(throwError(QueryError.tooComplex))
        expect { try self.query.where([.number: 1..<3]).firstOrInsert() }.to(throwError(QueryError.tooComplex))
        expect { try self.query.where([.number: 1]).or("number == 2").firstOrInsert() }.to(throwError(QueryError.tooComplex))
        expect { try self.query.where([.number: 1]).or([.number: 2]).firstOrInsert() }.to(throwError(QueryError.tooComplex))
    }

    func testOrder() {
        let q = query.order(by: .text).order(by: .number, .descending)
        expect(q.fetchRequest.sortDescriptors) == [NSSortDescriptor(key: "text", ascending: true), NSSortDescriptor(key: "number", ascending: false)]
    }

    func testOrderStringKey() {
        let q = query.order(by: "text").order(by: "number", .descending)
        expect(q.fetchRequest.sortDescriptors) == [NSSortDescriptor(key: "text", ascending: true), NSSortDescriptor(key: "number", ascending: false)]
    }

    func testOrderWithSelector() {
        var q = query.order(by: .text, .ascending, .localizedStandard)
        expect(q.fetchRequest.sortDescriptors) == [NSSortDescriptor(key: "text", ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))]

        q = query.order(by: "text", .ascending, .localizedCaseInsensitive)
        expect(q.fetchRequest.sortDescriptors) == [NSSortDescriptor(key: "text", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))]
    }

    func testWhereAddsPredicate() {
        let q = query.where("number == 1")
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 1])) == true
    }

    func testWhereAddsPredicateWithArguments() {
        let q = query.where("number == %d", 1)
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 1])) == true
    }

    func testWhereWithDictionaryInt() {
        let q = query.where([.number: 1])
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 1])) == true
    }

    func testWhereWithLessThanInequality() {
        let q = query.where([.number: lt(2)])
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 1])) == true
    }

    func testWhereWithLessThanOrEqualInequality() {
        let q = query.where([.number: lte(2)])
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 2])) == true
    }

    func testWhereWithDictionaryOpenRange() {
        let q = query.where([.number: 10..<20])
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 9])) == false
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 15])) == true
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 2])) == false
    }

    func testWhereWithDictionaryClosedRange() {
        let q = query.where([.number: 10...20])
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 9])) == false
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 15])) == true
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 21])) == false
    }

    func testWhereWithDictionaryEverythingElse() {
        let text = "foo bar"
        let entity = newEntity()
        entity.text = text
        let q = query.where([.text: text])
        expect(q.fetchRequest.predicate?.evaluate(with: ["text": text])) == true
    }

    func testWhereMultiplePredicates() {
        let q = query.where("number == 1").where("text == 'foo'")
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 1, "text": "foo"])) == true
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 1])) == false
    }

    func testOrCombinesWithPreviousPredicate() {
        let q = query.where("number == 1").or("number == 2")
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 1])) == true
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 2])) == true
    }

    func testOrWithDictionaryWithMultipleKeys() {
        let q = query.where([.text: "foo", .number: 1]).or([.text: "bar", .number: 2])
        expect(q.fetchRequest.predicate?.evaluate(with: ["text": "foo", "number": 1])) == true
        expect(q.fetchRequest.predicate?.evaluate(with: ["text": "bar", "number": 2])) == true
        expect(q.fetchRequest.predicate?.evaluate(with: ["text": "bar", "number": 1])) == false
    }

    func testOrWithMoreThanTwoClauses() {
        let q = query.where("number == 1").or("number == 2").or("number == 3")
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 1])) == true
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 2])) == true
        expect(q.fetchRequest.predicate?.evaluate(with: ["number": 3])) == true
    }

    func testComplexWhereWithOrs() {
        let q = query.where("text == 'foo'").where("number == 1").or("number == 2").where("text2 == 'bar'")
        expect(q.fetchRequest.predicate?.evaluate(with: ["text": "foo", "number": 1, "text2": "bar"])) == true
        expect(q.fetchRequest.predicate?.evaluate(with: ["text": "foo", "number": 2, "text2": "bar"])) == true
        expect(q.fetchRequest.predicate?.evaluate(with: ["text": "foo", "number": 1, "text2": "baz"])) == false
        expect(q.fetchRequest.predicate?.evaluate(with: ["text": "bar", "number": 1, "text2": "bar"])) == false
    }
}

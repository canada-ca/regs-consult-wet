import Vapor
import Fluent
import Foundation
// MARK: Model

struct Email: ValidationSuite, Validatable {
    let value: String

    public static func validate(input value: Email) throws {
        try Vapor.Email.validate(input: value.value)
    }
}

struct Commentary: Model {
    struct Constants {
        static let id = "id"
        static let documentId = "document_id"
        static let document = "document"
        static let name = "name"
        static let email = "email"
        static let represents = "represents"
        static let organization = "organization"
        static let createddate = "createddate"
        static let submitteddate = "submitteddate"
        static let submitted = "submitted"
        static let acknowledgeddate = "acknowledgeddate"
        static let status = "status"
    }

    struct Status {
        static let new = "new"
        
        static let notuseful = "notuseful"
        static let abuse = "abuse"
        
    }

    struct SubmitStatus {
        static let submitted = "submitted"

        static let missinginfo = "missing"
        static let ready = "ready"

    }
    var id: Node?
    var document: Node?
    var name: String?
    var email: Email?
    var represents: String?
    var organization: String?
    var createddate: Date?
    var submitteddate: Date?
    var submitted: Bool
    var acknowledgeddate: Date?
    var status: String?

    // used by fluent internally
    var exists: Bool = false
    static var entity = "commentaries" //db table name
    enum Error: Swift.Error {
        case dateNotSupported
        case idTooLarge
    }
    // MARK: NodeConvertible

           init(node: Node, in context: Context) throws {
            if let suggestedId = node[Constants.id]?.uint {
                if suggestedId < UInt(UInt32.max) &&  suggestedId != 0{
                    id = Node(suggestedId)
                } else {
                    throw Error.idTooLarge
                }
            } else {
                id = Node(UniqueID32()) //conflict overwrite currently on caller
            }
            document = try node.extract(Constants.documentId)
            name = node[Constants.name]?.string
            if let em = node[Constants.email]?.string {
                email = Email(value: em)
            }

            represents = node[Constants.represents]?.string
            organization = node[Constants.organization]?.string
            if let unix = node[Constants.createddate]?.double {
                // allow unix timestamps (easy to send this format from Paw)
                createddate = Date(timeIntervalSince1970: unix)
            } else if let raw = node[Constants.createddate]?.string {
                // if it's a string we assume it's in mysql date format
                // this could be expanded to support many formats
                guard let date = dateFormatter.date(from: raw) else {
                    throw Error.dateNotSupported
                }

                self.createddate = date
            } else {
                createddate = Date()  // now
            }
            
            if let unix = node[Constants.submitteddate]?.double {
                // allow unix timestamps (easy to send this format from Paw)
                submitteddate = Date(timeIntervalSince1970: unix)
            } else if let raw = node[Constants.submitteddate]?.string {
                // if it's a string we assume it's in mysql date format
                // this could be expanded to support many formats
                guard let date = dateFormatter.date(from: raw) else {
                    throw Error.dateNotSupported
                }
                
                self.submitteddate = date
            } else {
                // leave as is
            }
            if let unix = node[Constants.acknowledgeddate]?.double {
                // allow unix timestamps (easy to send this format from Paw)
                acknowledgeddate = Date(timeIntervalSince1970: unix)
            } else if let raw = node[Constants.acknowledgeddate]?.string {
                // if it's a string we assume it's in mysql date format
                // this could be expanded to support many formats
                guard let date = dateFormatter.date(from: raw) else {
                    throw Error.dateNotSupported
                }

                self.acknowledgeddate = date
            } else {
                // leave as is
            }
            submitted = node[Constants.submitted]?.bool ?? false
            status = node[Constants.status]?.string ?? Status.new
        }
    // MARK: Merge


        mutating func merge(updates: Commentary) {
            id = updates.id ?? id
            document = updates.document ?? document 
            name = updates.name ?? name
            email = updates.email ?? email
            represents = updates.represents ?? represents
            organization = updates.organization ?? organization
            createddate = updates.createddate ?? createddate
            submitteddate = updates.submitteddate ?? submitteddate
            submitted = updates.submitted
            acknowledgeddate = updates.acknowledgeddate ?? acknowledgeddate
            status = updates.status ?? status
            
        }

    func submitReadiness() -> String? {
        if submitted {
            return SubmitStatus.submitted
        } else if (represents?.isEmpty)! {
            return SubmitStatus.missinginfo
        } else if createddate != nil && ((createddate?.timeIntervalSinceNow)! < TimeInterval(-180.0)) {
            return SubmitStatus.ready
        }
        return nil
    }
    func nodeForJSON()  -> Node? {
        var result:[String: Node] = [:]
        if let nm = name {result["name"] = Node(nm)}
        if let em = email?.value {result["email"] = Node(em)}
        if let rp = represents {result["represents"] = Node(rp)}
        if let or = organization {result["organization"] = Node(or)}
        if let sr = submitReadiness() {result["submitstatus"] = Node(sr)}
        return Node(result)
        }
}
// MARK: NodeRepresentable
extension Commentary: NodeRepresentable {
    func makeNode(context: Context) throws -> Node {
        // model won't always have value to allow proper merges,
        // database defaults to false
        return try Node.init(node:
            [
                Constants.id: id,
                Constants.documentId: document,
                Constants.name: name,
                Constants.email: email == nil ? nil : email!.value,
                Constants.represents: represents,
                Constants.organization: organization,
                Constants.createddate: createddate == nil ? nil : createddate!.timeIntervalSince1970,
                Constants.submitteddate: submitteddate == nil ? nil : submitteddate!.timeIntervalSince1970,
                Constants.submitted: submitted,
                Constants.acknowledgeddate: acknowledgeddate == nil ? nil : acknowledgeddate!.timeIntervalSince1970,
                Constants.status: status

            ]
        )
    }
}

// MARK: Database Preparations

extension Commentary: Preparation {
    static func prepare(_ database: Database) throws {
        try database.create(entity) { commentary in  //3hrs debug to find MySQL need 's' added to commentary not commentaries
            commentary.id()
            commentary.parent(Document.self, optional: false)
            commentary.string(Constants.name, optional: true)
            commentary.string(Constants.email, optional: true)
            commentary.string(Constants.represents, optional: true)
            commentary.string(Constants.organization, optional: true)
            commentary.double(Constants.createddate, optional: true)
            commentary.double(Constants.submitteddate, optional: true)
            commentary.bool(Constants.submitted)
            commentary.double(Constants.acknowledgeddate, optional: true)
            commentary.string(Constants.status, optional: true)

        }
    }

    static func revert(_ database: Database) throws {
        fatalError("unimplemented \(#function)")
    }
}

// MARK: Re-usable Date Formatter

private var _df: DateFormatter?
private var dateFormatter: DateFormatter {
    if let df = _df {
        return df
    }

    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    _df = df
    return df
}

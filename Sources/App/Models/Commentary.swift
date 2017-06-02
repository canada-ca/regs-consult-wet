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
// for Model
struct CommentaryConstants {
    static let id = "id"
    static let documentId = "document_id"
    static let document = "document"
    static let name = "name"
    static let email = "email"
    static let represents = "represents"
    static let organization = "organization"
    static let createddate = "createddate"
    static let submitteddate = "submitteddate"
    static let verification = "verification"
    static let submitted = "submitted"
    static let acknowledgeddate = "acknowledgeddate"
    static let status = "status"
}

// to store in database
struct CommentaryStatus {
    static let new = "new"
    static let attemptedsubmit = "attemptedsubmit"
    static let submitted = "submitted"
    static let notuseful = "notuseful"
    static let abuse = "abuse"
    static let analysis = "analysis"
}

// to report status
struct CommentarySubmitStatus {
    static let submitted = "submitted"
    static let missinginfo = "missing"
    static let ready = "ready"
}
// to report status
struct CommentaryJSONKeys {
    static let id = "id"
    static let name = "name"
    static let email = "email"
    static let represents = "represents"
    static let organization = "organization"
    static let createddate = "createddate"
    static let submitteddate = "submitteddate"
    static let submitstatus = "submitstatus"
    static let acknowledgeddate = "acknowledgeddate"
    static let status = "status"
}
final class Commentary: Model {
    var id: Node?
    var document: Node?
    var name: String?
    var email: Email?
    var represents: String?
    var organization: String?
    var createddate: Date?
    var submitteddate: Date?
    var verification: Bool
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
            if let suggestedId = node[CommentaryConstants.id]?.uint {
                if suggestedId < UInt(UInt32.max) &&  suggestedId != 0 {
                    id = Node(suggestedId)
                } else {
                    throw Error.idTooLarge
                }
            } else {
                id = Node(uniqueID32()) //conflict overwrite currently on caller
            }
            document = try node.extract(CommentaryConstants.documentId)
            name = node[CommentaryConstants.name]?.string
            if let em = node[CommentaryConstants.email]?.string {
                email = Email(value: em)
            }

            represents = node[CommentaryConstants.represents]?.string
            organization = node[CommentaryConstants.organization]?.string
            if let unix = node[CommentaryConstants.createddate]?.double {
                // allow unix timestamps (easy to send this format from Paw)
                createddate = Date(timeIntervalSince1970: unix)
            } else if let raw = node[CommentaryConstants.createddate]?.string {
                // if it's a string we assume it's in mysql date format
                // this could be expanded to support many formats
                guard let date = dateFormatter.date(from: raw) else {
                    throw Error.dateNotSupported
                }

                self.createddate = date
            } else {
                createddate = Date()  // now
            }

            if let unix = node[CommentaryConstants.submitteddate]?.double {
                // allow unix timestamps (easy to send this format from Paw)
                submitteddate = Date(timeIntervalSince1970: unix)
            } else if let raw = node[CommentaryConstants.submitteddate]?.string {
                // if it's a string we assume it's in mysql date format
                // this could be expanded to support many formats
                guard let date = dateFormatter.date(from: raw) else {
                    throw Error.dateNotSupported
                }
                self.submitteddate = date
            } else {
                // leave as is
            }
            if let unix = node[CommentaryConstants.acknowledgeddate]?.double {
                // allow unix timestamps (easy to send this format from Paw)
                acknowledgeddate = Date(timeIntervalSince1970: unix)
            } else if let raw = node[CommentaryConstants.acknowledgeddate]?.string {
                // if it's a string we assume it's in mysql date format
                // this could be expanded to support many formats
                guard let date = dateFormatter.date(from: raw) else {
                    throw Error.dateNotSupported
                }

                self.acknowledgeddate = date
            } else {
                // leave as is
            }
            verification = node[CommentaryConstants.verification]?.bool ?? false
            submitted = node[CommentaryConstants.submitted]?.bool ?? false
            status = node[CommentaryConstants.status]?.string ?? CommentaryStatus.new
        }
    // MARK: Merge

        func merge(updates: Commentary) {
            id = updates.id ?? id
            document = updates.document ?? document
            name = updates.name ?? name
            email = updates.email ?? email
            represents = updates.represents ?? represents
            organization = updates.organization ?? organization
            createddate = updates.createddate ?? createddate
            submitteddate = updates.submitteddate ?? submitteddate
            verification = updates.verification
            submitted = updates.submitted
            acknowledgeddate = updates.acknowledgeddate ?? acknowledgeddate
            status = updates.status ?? status
        }

    func submitReadiness() -> String? {
        if submitted {
            return CommentarySubmitStatus.submitted
        } else if (represents ?? "").isEmpty {
            return CommentarySubmitStatus.missinginfo
        } else if createddate != nil && ((createddate?.timeIntervalSinceNow)! < TimeInterval(-30.0)) {
            return CommentarySubmitStatus.ready
        }
        return nil
    }
    func updateStatus(to newStatus: String) {
        switch newStatus {
        case CommentaryStatus.new where status == nil:
            status = newStatus
        case CommentaryStatus.attemptedsubmit where status == CommentaryStatus.new:
            status = newStatus
        case CommentaryStatus.submitted, CommentaryStatus.notuseful, CommentaryStatus.abuse, CommentaryStatus.analysis:
            status = newStatus
        default:
            break  // not a recognized state string should log error.
        }
    }
    static let receiveSortOrder: [String: Int] =
        [CommentaryStatus.submitted: 1,
         CommentaryStatus.attemptedsubmit: 2,
         CommentaryStatus.new: 3,
         CommentaryStatus.analysis: 4,
         CommentaryStatus.notuseful: 5,
         CommentaryStatus.abuse: 6]
    static let analyzeSortOrder: [String: Int] =
        [CommentaryStatus.submitted: 2,
         CommentaryStatus.attemptedsubmit: 3,
         CommentaryStatus.new: 4,
         CommentaryStatus.analysis: 1,
         CommentaryStatus.notuseful: 5,
         CommentaryStatus.abuse: 6]

//swiftlint:disable:next identifier_name
    static func statusSort (_ a: Commentary, _ b: Commentary, _ sortOrder: [String: Int]) -> Bool {
        let aOrder = sortOrder[a.status ?? "none"] ?? 0
        let bOrder = sortOrder[b.status ?? "none"] ?? 0

        if bOrder > aOrder {
            return true
        } else if bOrder < aOrder {
            return false
        }
        if let adate = a.submitteddate {
            if let bdate = b.submitteddate, adate > bdate {
                return true
            }
            return false
        }
        if b.submitteddate != nil {
            return true
        }
        return false
    }
    //swiftlint:disable:next identifier_name
    static func receiveSort (_ a: Commentary, _ b: Commentary) -> Bool {
        return statusSort(a, b, Commentary.receiveSortOrder)

    }
    //swiftlint:disable:next identifier_name
    static func analyzeSort (_ a: Commentary, _ b: Commentary) -> Bool {
        return statusSort(a, b, Commentary.analyzeSortOrder)

    }
    //swiftlint:disable:next identifier_name
    static func reviewSort (_ a: Commentary, _ b: Commentary) -> Bool {
        let aOrder = a.represents ?? ""
        let bOrder = b.represents ?? ""

        if aOrder < bOrder {
            return true
        } else if bOrder < aOrder {
            return false
        }
        if let adate = a.submitteddate {
            if let bdate = b.submitteddate, adate > bdate {
                return true
            }
            return false
        }
        if b.submitteddate != nil {
            return true
        }
        return false

    }
//    dashboardOrder
//        CommentaryStatus.submitted
//         CommentaryStatus.attemptedsubmit
//         CommentaryStatus.analysis
//         CommentaryStatus.new
//         CommentaryStatus.notuseful
//         CommentaryStatus.abuse: 6
    static func dashboard(link: String, commentaryCounts: [Int?]) -> String {
        let buttonText = "View&nbsp;Commentaries"
        var nCounts: [Int?] = commentaryCounts
        for _ in 0..<(6 - commentaryCounts.count) {
            nCounts.append(nil)  //pad a short array in case states are added later
        }
        var statusList: String = "<p><ul class=\"list-unstyled\">"
        if let itemCount = nCounts[0] {
            statusList += "<li><samp>\(itemCount)&nbsp;</samp><span class=\"label label-info\">Submitted</span></li>"
        }
        if let itemCount = nCounts[1] {
            statusList += "<li><samp>\(itemCount)&nbsp;</samp><span class=\"label label-primary\">Attempted&nbsp;submit</span></li>"
        }
        if let itemCount = nCounts[2] {
            statusList += "<li><samp>\(itemCount)&nbsp;</samp><span class=\"label label-success\">Analysis</span></li>"
        }
        if let itemCount = nCounts[3] {
            statusList += "<li><samp>\(itemCount)&nbsp;</samp><span class=\"label label-primary\">New&nbsp;(in&nbsp;progress)</span></li>"
        }
        if let itemCount = nCounts[4] {
            statusList += "<li><samp>\(itemCount)&nbsp;</samp><span class=\"label label-default\">Not&nbsp;useful</span></li>"
        }
        if let itemCount = nCounts[5] {
            statusList += "<li><samp>\(itemCount)&nbsp;</samp><span class=\"label label-default\">Abuse</span></li>"
        }
        statusList += "</ul></p>"

        let output = "<a class=\"btn btn-default\" href=\"\(link)\">\(buttonText)</a>\(statusList)"
        return output
    }
    func htmlStatus() -> String {
        var statusOutput: String = ""
        switch status ?? "" {
        case CommentaryStatus.submitted:
            statusOutput += "<span class=\"label label-info\">Submitted</span>"
        case CommentaryStatus.attemptedsubmit:
            statusOutput += "<span class=\"label label-info\">Attempted&nbsp;submit</span>"
        case CommentaryStatus.analysis:
            statusOutput += "<span class=\"label label-success\">Analysis</span>"
        case CommentaryStatus.new:
            statusOutput += "<span class=\"label label-primary\">New&nbsp;(in&nbsp;progress)</span>"
        case CommentaryStatus.notuseful:
            statusOutput += "<span class=\"label label-default\">Not&nbsp;useful</span>"
        case CommentaryStatus.abuse:
            statusOutput += "</samp><span class=\"label label-default\">Abuse</span>"
        default:
            statusOutput += "</samp><span class=\"label label-default\">unknown</span>"
        }
        return statusOutput

    }
    func forJSON() -> [String: Node] {
        var result: [String: Node] = [:]
        if let em = id, let emu = em.uint {
            result[CommentaryJSONKeys.id] = Node(emu)
        }
        if let nm = name {result[CommentaryJSONKeys.name] = Node(nm)}
        if let em = email?.value {result[CommentaryJSONKeys.email] = Node(em)}
        if let rp = represents {result[CommentaryJSONKeys.represents] = Node(rp)}
        if let or = organization {result[CommentaryJSONKeys.organization] = Node(or)}
        if let st = status {
            result[CommentaryJSONKeys.status] = Node(htmlStatus())  //Node(st)
            result["commentarystatus" + st] = Node(true)
        }
        if let cd = createddate {result[CommentaryJSONKeys.createddate] = Node(dateFormatter.string(from: cd))}
        if let sd = submitteddate {result[CommentaryJSONKeys.submitteddate] = Node(dateFormatter.string(from: sd))}
        if let ad = acknowledgeddate {result[CommentaryJSONKeys.acknowledgeddate] = Node(dateFormatter.string(from: ad))}
        return result
    }

    func nodeForJSON() -> Node? {
        var result: [String: Node] = [:]
        if let nm = name {result[CommentaryJSONKeys.name] = Node(nm)}
        if let em = email?.value {result[CommentaryJSONKeys.email] = Node(em)}
        if let rp = represents {result[CommentaryJSONKeys.represents] = Node(rp)}
        if let or = organization {result[CommentaryJSONKeys.organization] = Node(or)}
        if let sr = submitReadiness() {result[CommentaryJSONKeys.submitstatus] = Node(sr)}
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
                CommentaryConstants.id: id,
                CommentaryConstants.documentId: document,
                CommentaryConstants.name: name,
                CommentaryConstants.email: email == nil ? nil : email!.value,
                CommentaryConstants.represents: represents,
                CommentaryConstants.organization: organization,
                CommentaryConstants.createddate: createddate == nil ? nil : createddate!.timeIntervalSince1970,
                CommentaryConstants.submitteddate: submitteddate == nil ? nil : submitteddate!.timeIntervalSince1970,
                CommentaryConstants.verification: verification,
                CommentaryConstants.submitted: submitted,
                CommentaryConstants.acknowledgeddate: acknowledgeddate == nil ? nil : acknowledgeddate!.timeIntervalSince1970,
                CommentaryConstants.status: status

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
            commentary.string(CommentaryConstants.name, optional: true)
            commentary.string(CommentaryConstants.email, optional: true)
            commentary.string(CommentaryConstants.represents, optional: true)
            commentary.string(CommentaryConstants.organization, optional: true)
            commentary.double(CommentaryConstants.createddate, optional: true)
            commentary.double(CommentaryConstants.submitteddate, optional: true)
            commentary.bool(CommentaryConstants.verification)
            commentary.bool(CommentaryConstants.submitted)
            commentary.double(CommentaryConstants.acknowledgeddate, optional: true)
            commentary.string(CommentaryConstants.status, optional: true)

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

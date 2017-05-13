import Vapor
import Fluent
import Foundation
// MARK: Model

struct Note: Model {
    struct Constants {
        static let id = "id"
        static let commentary = "commentary"
        static let documentId = "document_id"
        static let commentaryId = "commentary_id"
        static let userId = "user_id"
        static let document = "document"
        static let linenumber = "linenumber"
        static let reference = "reference"
        static let textshared = "textshared"
        static let statusshared = "statusshared"
        static let textuser = "textuser"
        static let statususer = "statususer"
        static let status = "status"

    }
    struct JSONKeys {
        static let id = "id"
        static let commentary = "commentary"
        static let documentId = "documentid"
        static let commentaryId = "commentaryid"
        static let document = "document"
        static let linenumber = "linenumber"
        static let reference = "reference"
        static let referenceCoded = "referencecoded"
        static let textshared = "textshared"
        static let statusshared = "statusshared"
        static let textuser = "textuser"
        static let statususer = "statususer"
        static let status = "status"

    }
    struct Status {
        static let analysis = "analysis"
        static let duplicate = "duplicate"
        static let notuseful = "notuseful"
        static let review = "review"
        static let disposition = "disposition"
    }
    var id: Node?
    var document: Node?
    var commentary: Node?
    var user: Node?
    var linenumber: Int
    var reference: String?
    var textshared: String?
    var statusshared: String?
    var textuser: String?
    var statususer: String?

    var status: String?

    // used by fluent internally
    var exists: Bool = false
    static var entity = "notes" //db table name
    enum Error: Swift.Error {
        case userNotSupplied
        case idTooLarge
    }

}

// MARK: NodeConvertible

extension Note: NodeConvertible {
    init(node: Node, in context: Context) throws {
        if let suggestedId = node[Constants.id]?.uint, suggestedId != 0 {
            if suggestedId < UInt(UInt32.max) {
                id = Node(suggestedId)
            } else {
                throw Error.idTooLarge
            }
        } else {
            id = nil
        }
        document = try node.extract(Constants.documentId)
        commentary = try node.extract(Constants.commentaryId)
        if let suggestedId = node[Constants.userId]?.uint {
            if suggestedId < UInt(UInt32.max) {
                user = Node(suggestedId)
            } else {
                throw Error.idTooLarge
            }
            
        } else {
            throw Error.userNotSupplied
        }
        if let suggestedId = node[Constants.linenumber]?.int {
             linenumber = suggestedId
        } else {
            linenumber = 0
        }

        reference = try node.extract(Constants.reference)
        textshared = try node.extract(Constants.textshared)
        statusshared = try node.extract(Constants.statusshared)
        textuser = try node.extract(Constants.textuser)
        statususer = try node.extract(Constants.statususer)

        status = try node.extract(Constants.status)
    }

    func makeNode(context: Context) throws -> Node {
        // model won't always have value to allow proper merges,
        // database defaults to false

        return try Node.init(node:
            [
                Constants.id: id,
                Constants.commentaryId: commentary,
                Constants.documentId: document,
                Constants.userId: user,
                Constants.linenumber: linenumber,
                Constants.reference: reference,
                Constants.textshared: textshared,
                Constants.statusshared: statusshared,
                Constants.textuser: textuser,
                Constants.statususer: statususer,
                Constants.status: status
            ]
        )
    }
}

// MARK: Database Preparations

extension Note: Preparation {
    static func prepare(_ database: Database) throws {
        try database.create(entity) { comment in
            comment.id()
            comment.parent(Document.self, optional: false)
            comment.parent(Commentary.self, optional: true)
            comment.parent(User.self, optional: false)
            comment.int(Constants.linenumber, optional: false)
            comment.string(Constants.reference, optional: true)
            comment.data(Constants.textshared, optional: true)
            comment.string(Constants.statusshared, optional: true)
            comment.data(Constants.textuser, optional: true)
            comment.string(Constants.statususer, optional: true)
            comment.string(Constants.status, optional: true)

        }
    }

    static func revert(_ database: Database) throws {
        fatalError("unimplemented \(#function)")
    }
}

// MARK: Merge

extension Note {
    mutating func merge(updates: Note) {
        id = updates.id ?? id
        commentary = updates.commentary ?? commentary
        document = updates.document ?? document
        user = updates.user ?? user
        linenumber = updates.linenumber  // more testing of 0 case needing
        reference = updates.reference ?? reference
        textshared = updates.textshared ?? textshared
        statusshared = updates.statusshared ?? statusshared
        textuser = updates.textuser ?? textuser
        statususer = updates.statususer ?? statususer
        status = updates.status ?? status

    }

    static let docSegSortOrder: [String: Int] =
        ["non": 1,
         "ris": 2,
         "reg": 3
    ]

    static func singleDocOrderSort (_ a: Note,_ b: Note) -> Bool {
        // not needed as all from same document assumed to speed up sort.
//        let aOrder = a.document?.int ?? 0
//        let bOrder = b.document?.int ?? 0
//        if bOrder > aOrder {
//            return true
//        } else if bOrder < aOrder {
//            return false
//        }

        let aOrd = docSegSortOrder[String((a.reference ?? "none").characters.prefix(3))] ?? 0
        let bOrd = docSegSortOrder[String((b.reference ?? "none").characters.prefix(3))] ?? 0

        if bOrd > aOrd {
            return true
        } else if bOrd < aOrd {
            return false
        }
        let aLine = a.linenumber
        let bLine = b.linenumber
        if bLine > aLine {
            return true
        } else {
            return false
        }
        
    }
    
    // shields user private component from leaking
    func forJSON(_ usr: User) -> [String: Node] {
        var result: [String: Node] = [:]
        if let em = id , let emu = em.uint {
            result[JSONKeys.id] = Node(emu)
        }
        result[JSONKeys.linenumber] = Node(linenumber)
        if let rf = reference {
            result[JSONKeys.reference] = Node(rf)
            let index4 = rf.index(rf.startIndex, offsetBy: 4)
            let from4 = String(rf.characters.suffix(from: index4))
            let thru4 = String(rf.characters.prefix(4))
            result[JSONKeys.referenceCoded] = Node(thru4 + String(self.linenumber) + " " + from4)
        }
        if let tx = textshared {result[JSONKeys.textshared] = Node(tx)}
        if let st = statusshared {result[JSONKeys.statusshared] = Node(st)}
        if let u = user?.int , let uinput = usr.id?.int, u == uinput {
            if let tx = textuser {result[JSONKeys.textuser] = Node(tx)}
            if let st = statususer {result[JSONKeys.statususer] = Node(st)}
        }
        if let st = status {result[JSONKeys.status] = Node(st)}

        return result

    }

    func forJSON() -> [String: Node] {
        var result: [String: Node] = [:]
        if let em = id , let emu = em.uint {
            result[JSONKeys.id] = Node(emu)
        }
        result[JSONKeys.linenumber] = Node(linenumber)
        if let rf = reference {
            result[JSONKeys.reference] = Node(rf)
            let index4 = rf.index(rf.startIndex, offsetBy: 4)
            let from4 = String(rf.characters.suffix(from: index4))
            let thru4 = String(rf.characters.prefix(4))
            result[JSONKeys.referenceCoded] = Node(thru4 + String(self.linenumber) + " " + from4)
        }
        if let tx = textshared {result[JSONKeys.textshared] = Node(tx)}
        if let st = statusshared {result[JSONKeys.statusshared] = Node(st)}
        if let tx = textuser {result[JSONKeys.textuser] = Node(tx)}
        if let st = statususer {result[JSONKeys.statususer] = Node(st)}
        if let st = status {result[JSONKeys.status] = Node(st)}

        return result
    }

//    func nodeForJSON() -> Node? {
//
//        return Node([
//            JSONKeys.linenumber: Node(linenumber),
//            JSONKeys.reference: Node(reference ?? ""),
//            JSONKeys.textshared: Node(textshared ?? ""),
//            JSONKeys.statusshared: Node(statusshared ?? ""),
//            JSONKeys.textuser: Node(textuser ?? ""),
//            JSONKeys.statususer: Node(statususer ?? ""),
//            JSONKeys.status: Node(status ?? "")
//            ])
//    }
    mutating func updateStatus(of item: String, to newStatus: String) {
        switch newStatus {
        case Status.analysis, Status.duplicate, Status.notuseful, Status.review, Status.disposition:
            status = newStatus
        default:
            break  // not a recognized state string should log error.
        }

    }
//    func nodeForReviewJSON() -> Node? {
//        guard let ref = self.reference else { return nil}
//        let tagType = String(ref.characters.prefix(4))
//
//        var commnode = Node(["reftext": Node(ref),
//                             "ref": Node(tagType + String(self.linenumber)),  //ex: reg-34
////                             "text": Node(self.text ?? ""),
//                             "status" :Node(self.status ?? "")
//            ])
//        do {
//            let cmty =  try self.commenter().get
//            commnode["commentary"] = try cmty()?.nodeForJSON()
//
//        } catch {
//
//            }
//        return  commnode
//    }
//
//}
//extension Note {
//    func commenter() throws -> Parent<Commentary> {
//        return try parent(commentary, Constants.commentaryId)
//    }
}

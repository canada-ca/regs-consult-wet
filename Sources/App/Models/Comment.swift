import Vapor
import Fluent
import Foundation
import SwiftMarkdown
// MARK: Model

struct Comment: Model {
    struct Constants {
        static let id = "id"
        static let commentary = "commentary"
        static let documentId = "document_id"
        static let commentaryId = "commentary_id"
        static let document = "document"
        static let linenumber = "linenumber"
        static let reference = "reference"
        static let text = "text"
        static let status = "status"

    }
    struct JSONKeys {
        static let id = "id"
        static let commentary = "commentary"
        static let documentId = "document_id"
        static let commentaryId = "commentary_id"
        static let document = "document"
        static let linenumber = "linenumber"
        static let reference = "reference"
        static let referenceCoded = "referencecoded"
        static let text = "text"
        static let status = "status"

    }
    struct Status {
        static let new = "new"
    }
    var id: Node?
    var commentary: Node?
    var document: Node?
    var linenumber: Int
    var reference: String?
    var text: String?
    var status: String?

    // used by fluent internally
    var exists: Bool = false
    static var entity = "comments" //db table name
    enum Error: Swift.Error {
        case dateNotSupported
        case idTooLarge
    }

}

// MARK: NodeConvertible

extension Comment: NodeConvertible {
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

        commentary = try node.extract(Constants.commentaryId)
        document = try node.extract(Constants.documentId)
        linenumber = try node.extract(Constants.linenumber)
        reference = try node.extract(Constants.reference)
        text = try node.extract(Constants.text)
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
                Constants.linenumber: linenumber,
                Constants.reference: reference,
                Constants.text: text,
                Constants.status: status
            ]
        )
    }
}

// MARK: Database Preparations

extension Comment: Preparation {
    static func prepare(_ database: Database) throws {
        try database.create(entity) { comment in
            comment.id()
            comment.parent(Commentary.self, optional: false)
            comment.parent(Document.self, optional: false)
            comment.int(Constants.linenumber, optional: false)
            comment.string(Constants.reference, optional: true)
            comment.data(Constants.text, optional: true)
            comment.string(Constants.status, optional: true)
        }
    }

    static func revert(_ database: Database) throws {
        fatalError("unimplemented \(#function)")
    }
}

// MARK: Merge

extension Comment {
    mutating func merge(updates: Comment) {
        id = updates.id ?? id
        commentary = updates.commentary ?? commentary
        document = updates.document ?? document
        linenumber = updates.linenumber
        reference = updates.reference ?? reference
        text = updates.text ?? text
        status = updates.status ?? status

    }
    static let docSegSortOrder: [String: Int] =
        ["non": 1,
         "ris": 2,
         "reg": 3
        ]
//swiftlint:disable:next identifier_name
    static func docOrderSort (_ a: Comment, _ b: Comment) -> Bool {
        let aOrder = a.document?.int ?? 0
        let bOrder = b.document?.int ?? 0
        if bOrder > aOrder {
            return true
        } else if bOrder < aOrder {
            return false
        }

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

    func forJSON() -> [String: Node] {
        var result: [String: Node] = [:]
        if let em = id, let emu = em.uint {
            result[Comment.JSONKeys.id] = Node(emu)
        }
        result[Comment.JSONKeys.linenumber] = Node(linenumber)
        if let rf = reference, rf.count >= 4 {
            result[Comment.JSONKeys.reference] = Node(rf)
            let index4 = rf.index(rf.startIndex, offsetBy: 4)
            let from4 = String(rf.characters.suffix(from: index4))
            let thru4 = String(rf.characters.prefix(4))
            result[Comment.JSONKeys.referenceCoded] = Node(thru4 + String(self.linenumber) + " " + from4)
        }
        if let st = status {result[Comment.JSONKeys.status] = Node(st)}
//        if let tx = text {result[Comment.JSONKeys.text] = Node(String("<div class=\"lc\">\(tx)</div>"))}
        if let txt = text {
            let out = try? markdownToHTML(txt)
            result[Comment.JSONKeys.text] = Node(String("<div class=\"lc\"><span style=\"white-space: pre-line\">\(String(describing: out ?? ""))</span></div>"))
//            noteList += "<div class=\"well well-sm\"><p>\(note.htmlStatus())</p>\(String(describing: out ?? ""))</div>"
        }

        return result
    }

    func nodeForJSON() -> Node? {
        guard let ref = self.reference else { return nil}
        let tagType = String(ref.characters.prefix(4))
        return Node(["reftext": Node(ref),
                     "ref": Node(tagType + String(self.linenumber)),  //ex: reg-34
            "text": Node(self.text ?? ""),
            "status": Node(self.status ?? "")
            ])
    }
//    func nodeForReviewJSON() -> Node? {
//        guard let ref = self.reference else { return nil}
//        let tagType = String(ref.characters.prefix(4))
//
//        var commnode = Node(["reftext": Node(ref),
//                             "ref": Node(tagType + String(self.linenumber)),  //ex: reg-34
//                             "text": Node(self.text ?? ""),
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

}
//extension Comment {
//    func commenter() throws -> Parent<Commentary> {
//        return try parent(commentary, Constants.commentaryId)
//    }
//    func commenterStatus() -> String {
//        do {
//            let comm: Parent<Commentary> = try parent(self.commentary, Constants.commentaryId)
//            let commreal = try comm.get()
//            return commreal?.status ?? "none"
//
//        } catch {
//            return "none"
//        }
//
//    }
//}

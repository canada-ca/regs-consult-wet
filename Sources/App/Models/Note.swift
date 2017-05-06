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
        static let documentId = "document_id"
        static let commentaryId = "commentary_id"
        static let document = "document"
        static let linenumber = "linenumber"
        static let reference = "reference"
        static let text = "text"
        static let status = "status"

    }
    struct Status {
        static let new = "new"
        static let status = "disposition"
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
        case dateNotSupported
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
        linenumber = try node.extract(Constants.linenumber)
        reference = try node.extract(Constants.reference)
//        text = try node.extract(Constants.text)
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
//                Constants.text: text,
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
    mutating func merge(updates: Comment) {
        id = updates.id ?? id
        commentary = updates.commentary ?? commentary
        document = updates.document ?? document
        linenumber = updates.linenumber
        reference = updates.reference ?? reference
//        text = updates.text ?? text
        status = updates.status ?? status

    }
    func forJSON() -> [String: Node] {
        var result: [String: Node] = [:]
        if let em = id , let emu = em.uint {
            result[Comment.JSONKeys.id] = Node(emu)
        }
        result[Comment.JSONKeys.linenumber] = Node(linenumber)
        if let rf = reference {result[Comment.JSONKeys.reference] = Node(rf)}
        if let st = status {result[CommentaryJSONKeys.status] = Node(st)}
//        if let tx = text {result[Comment.JSONKeys.text] = Node(tx)}

        return result
    }

    func nodeForJSON() -> Node? {
        guard let ref = self.reference else { return nil}
        let tagType = String(ref.characters.prefix(4))
        return Node(["reftext": Node(ref),
                     "ref": Node(tagType + String(self.linenumber)),  //ex: reg-34
//            "text": Node(self.text ?? ""),
            "status": Node(self.status ?? "")
            ])
    }
    func nodeForReviewJSON() -> Node? {
        guard let ref = self.reference else { return nil}
        let tagType = String(ref.characters.prefix(4))

        var commnode = Node(["reftext": Node(ref),
                             "ref": Node(tagType + String(self.linenumber)),  //ex: reg-34
//                             "text": Node(self.text ?? ""),
                             "status" :Node(self.status ?? "")
            ])
        do {
            let cmty =  try self.commenter().get
            commnode["commentary"] = try cmty()?.nodeForJSON()

        } catch {

            }
        return  commnode
    }

}
extension Note {
    func commenter() throws -> Parent<Commentary> {
        return try parent(commentary, Constants.commentaryId)
    }
}
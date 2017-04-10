import Vapor
import Fluent
import Foundation
import Base62
// MARK: Model

struct Document: Model {
    struct Constants {
        static let id = "id"
        static let knownas = "knownas"
        static let filepack = "filepack"
        static let publishingref = "publishingref"
        static let publishingdate = "publishingdate"
        static let publishingpath = "publishingpath"
        static let publishingpageprefix = "publishingpageprefix"
        static let archived = "archived"
    }
    // to report status
    struct JSONKeys {
        static let id = "id"
        static let idbase62 = "idbase62"
        static let knownas = "knownas"
    }


    var id: Node?
    var knownas: String?
    var filepack: String?
    var publishingref: String?
    var publishingdate: Date?
    var publishingpath: String?
    var publishingpageprefix: String?
    var archived: Bool?


    // used by fluent internally
    var exists: Bool = false
    static var entity = "documents"   //db table name

    enum Error: Swift.Error {
        case dateNotSupported
        case idTooLarge
    }
    
    func nodeForJSON() -> Node? {
        var result: [String: Node] = [:]
        if let nm = knownas {result[JSONKeys.knownas] = Node(nm)}
        if let em = id {result[JSONKeys.id] = Node(em)}
        return Node(result)
    }
    
    func forJSON() -> [String: Node] {
        var result: [String: Node] = [:]
        if let nm = knownas {result[JSONKeys.knownas] = Node(nm)}
        if let em = id , let emu = em.uint {
            result[JSONKeys.id] = Node(emu)
            result[JSONKeys.idbase62] = Node(Base62.encode(integer: UInt64(emu)))
        }
        return result
    }
}


// MARK: NodeConvertible

extension Document: NodeConvertible {
    init(node: Node, in context: Context) throws {
        if let suggestedId = node[Constants.id]?.uint, suggestedId != 0 {
            if suggestedId < UInt(UInt32.max) {
                id = Node(suggestedId)
            } else {
                throw Error.idTooLarge
            }
        } else {
            id = Node(uniqueID32())
        }
        knownas = node[Constants.knownas]?.string
        filepack = node[Constants.filepack]?.string
        publishingref = node[Constants.publishingref]?.string
        publishingpath = node[Constants.publishingpath]?.string
        publishingpageprefix = node[Constants.publishingpageprefix]?.string

        if let unix = node[Constants.publishingdate]?.double {
            // allow unix timestamps (easy to send this format from Paw)
            publishingdate = Date(timeIntervalSince1970: unix)
        } else if let raw = node[Constants.publishingdate]?.string {
            // if it's a string we assume it's in mysql date format
            // this could be expanded to support many formats
            guard let date = dateFormatter.date(from: raw) else {
                throw Error.dateNotSupported
            }

            self.publishingdate = date
        } else {
            publishingdate = Date(timeIntervalSinceNow: 70.0 * 24 * 3600)  //70 days from now
        }
        archived = node[Constants.archived]?.bool

    }

    func makeNode(context: Context) throws -> Node {
        // model won't always have value to allow proper merges,
        // database defaults to false
        let archive = archived ?? false
        return try Node.init(node:
            [
                Constants.id: id,
                Constants.knownas: knownas,
                Constants.filepack: filepack,
                Constants.publishingref: publishingref,
                Constants.publishingdate: publishingdate == nil ? nil : publishingdate!.timeIntervalSince1970,
                Constants.publishingpath: publishingpath,
                Constants.publishingpageprefix: publishingpageprefix,
                Constants.archived: archive

            ]
        )
    }
}

// MARK: Database Preparations

extension Document: Preparation {
    static func prepare(_ database: Database) throws {
        try database.create(entity) { document in
            document.id()
            document.string(Constants.knownas, optional: true)
            document.string(Constants.filepack, optional: true)
            document.string(Constants.publishingref, optional: true)
            document.double(Constants.publishingdate, optional: true)
            document.string(Constants.publishingpath, optional: true)
            document.string(Constants.publishingpageprefix, optional: true)
            document.bool(Constants.archived)

        }
    }

    static func revert(_ database: Database) throws {
        fatalError("unimplemented \(#function)")
    }
}

// MARK: Merge

extension Document {
    mutating func merge(updates: Document) {
        id = updates.id ?? id
        archived = updates.archived ?? archived
        knownas = updates.knownas ?? knownas
        publishingref = updates.publishingref ?? publishingref
        publishingdate = updates.publishingdate ?? publishingdate
        publishingpath = updates.publishingpath ?? publishingpath
        publishingpageprefix = updates.publishingpageprefix ?? publishingpageprefix

    }
    func publishedURL (languageStr: String?) -> URL? {
        let name = drop.config["app", "hosturl"]?.string ?? "/"
        return URL(string: (publishingpath ?? "") + (publishingpageprefix ?? "")
            + ((languageStr?.hasPrefix("fr"))! ? "-fra.html" : "-eng.html"), relativeTo: URL(string: name))
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

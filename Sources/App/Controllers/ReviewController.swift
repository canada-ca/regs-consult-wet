import HTTP
import JSON
import Vapor
import Auth
import Foundation
import JWT
import Node
import Cookies
import Fluent
import FluentMySQL

final class ReviewController{
    let pubDrop: Droplet
    let templateDir: String
    let filePackDir: String
    let fm = FileManager()

    init(to drop: Droplet, cookieSetter: AuthMiddlewareJWT, protect: RedirectAuthMiddlewareJWT) {
        pubDrop = drop
        templateDir = drop.workDir + "TemplatePacks/"
        filePackDir = drop.workDir + "FilePacks/"

        let role = drop.grouped("review").grouped(cookieSetter).grouped(protect)
        role.get(handler: receiverSummary)
        role.get("documents", handler: documentIndex)

        let documentrole = role.grouped("documents",":id")

        documentrole.get(handler: commentariesSummary)
        documentrole.get("load", handler: documentLoader)
        documentrole.get("commentaries", handler: commentaryIndex)
        documentrole.get("commentaries", ":commentaryId", handler: commentarySummary)
        role.get("commentaries", ":commentaryId","comments", handler: commentIndex)
        role.post("commentaries", ":commentaryId", ":command", handler: commentaryUpdate)
    }
    func documentIndex(_ request: Request)throws -> ResponseRepresentable {

        let documentsArray = try Document.query().filter("archived", .notEquals, true).all()
        var commentaryStatusCounts: [String:Int] = [:]
        let commentaryStatusArray = try Commentary.query().filter(CommentaryConstants.status, .in, [CommentaryStatus.new, CommentaryStatus.submitted, CommentaryStatus.analysis]).all()
        commentaryStatusArray.forEach { element in
            if let stat = element.status , let docid = element.document?.uint {
                let counthash = stat + String(docid)
                commentaryStatusCounts[counthash] = (commentaryStatusCounts[counthash] ?? 0) + 1
            }
        }

        var response: [String: Node] = [:]
        var results: [Node] = []

        for document in documentsArray {
            var result: [String: Node] = document.forJSON()
            //            if let mysql = pubDrop.database?.driver as? MySQLDriver {
            //                let version = try mysql.raw("SELECT status, COUNT(status) AS occurrence FROM commentaries GROUP BY status;")
            //                let aa = version.array
            //            }
            let docid = String(describing: document.id!.uint!)
            let countSubmitted: Int = commentaryStatusCounts[CommentaryStatus.submitted + docid] ?? 0
            let countNew: Int = commentaryStatusCounts[CommentaryStatus.new + docid] ?? 0
            let countAnalysis: Int = commentaryStatusCounts[CommentaryStatus.analysis + docid] ?? 0
            let buttonStyle = countAnalysis == 0 ? "btn-default" : "btn-primary"
            let doc = String((result[Document.JSONKeys.idbase62]?.string!)!)!
            result["newsubmit"] = Node("<p><a class=\"btn btn-block \(buttonStyle)\" href=\"/review/documents/\(doc)/\">Analysis <span class=\"badge\">\(countAnalysis)<span class=\"wb-inv\"> submissions to accept</span></span></a><a class=\"btn btn-block btn-default\" href=\"/receive/documents/\(doc)/\">Submissions <span class=\"badge\">\(countSubmitted)<span class=\"wb-inv\"> submissions to accept</span></span></a><a class=\"btn btn-default btn-block \" href=\"/receive/documents/\(doc)/\">Composition <span class=\"badge\">\(countNew)<span class=\"wb-inv\"> not submitted</span></span></a></p>")
            result["commentlink"] = Node("<p><a class=\"btn btn-block btn-default\" href=\"/review/documents/\(doc)/comments/summary/\">All <span class=\"badge\">\(countSubmitted)<span class=\"wb-inv\"> comments</span></span></a></p>")
            result["notelink"] = Node("<p><a class=\"btn btn-block btn-default\" href=\"/review/documents/\(doc)/notes/summary/\">All <span class=\"badge\">\(countSubmitted)<span class=\"wb-inv\"> comments</span></span></a></p>")
            results.append(Node(result))

        }
        response["data"] = Node(results)
        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(response))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
        return resp
    }

    func receiverSummary(_ request: Request)throws -> ResponseRepresentable {

        var parameters = try Node(node: [
            "review_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        return try   pubDrop.view.make("role/review/index", parameters)
    }
    func documentLoader(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        //TODO: document not found errors
        guard documentdata != nil else {throw Abort.badRequest}


    
        return try buildDocumentLoad(request, document: documentdata!, docId: documentId)
    }

    func buildDocumentLoad(_ request: Request, document: Document, docId: String)throws -> ResponseRepresentable {
        let filePackBaseDir = filePackDir + document.filepack!
        let filePack = filePackBaseDir + "/elements/"
        //TODO: need new document types in future
//        let templatePack = templateDir + "proposedregulation/elements/"
        var filejson: [String: Any] = [:]
        var sectionTags: [[[String: Any]]] = []

        //        let docRenderer = LeafRenderer(viewsDir: filePack)
//        let tempRenderer = LeafRenderer(viewsDir: templatePack)
        //find page language from referrer
//        var tagsDict: [String:[String: Any]] = [:]
//        var fileJson: JSON = JSON(.null)
        //get data from disk/network
        let sections = [("rias", "ris") , ("reg",  "reg")]
        if let data = fm.contents(atPath: filePackBaseDir + "/filepack.json") {
//            fileJson = try! JSON(serialized: data.makeBytes())
            if let fj =  try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                filejson = fj!
                for sectionType in sections {
                    if let thetags = filejson[sectionType.0 + "-tags"] as? [[String: Any]] {
                        // Finally we got the tags
                        sectionTags.append(thetags)
                    } else {
                        sectionTags.append([[:]])
                    }
                }
            }
        }

        var results: [Node] = []
// obviously with different languages this all need a refactor, brute force for Pilot trial - should use filepack data to drive.
        //could also cache this work.
        let languages =  [("eng", "-eng.html", "line-eng", "en-CA", "prompt-eng"), ("fra", "-fra.html", "line-fra", "fr-CA", "prompt-fra")]
        var sequencePosition: Int = 0
        var keyArray:[Node] = []
        for (sectionIndex, sectionType) in sections.enumerated() {
            var dataStrings: [[String]] = []
            var lastline: [Int] = []
            for lang in languages {
                if let section = fm.contents(atPath: filePack + sectionType.0 + lang.1),
                     let lines = String(data: section, encoding: String.Encoding.utf8)?.components(separatedBy: .newlines)
                {
                    dataStrings.append(lines)
                } else {
                    dataStrings.append([])
                }
                lastline.append(0)
            }
            let storageKeyPrefix = docId + "-" + sectionType.1 + "-"
//                substitutions["reftype"] = Node(String(describing: "ris"))
            for tag in sectionTags[sectionIndex] {
                var storageItem: [String:Node] = [:]
                if let keyLinenum = tag[languages[0].2] as? Int {
                    let storageKey = storageKeyPrefix + String(keyLinenum)
//                    guard linenum <= dataString.count else {continue}
                    storageItem["ref"] = Node(tag["ref"] as? String ?? "")
                    storageItem["seq"] = Node(sequencePosition)
                    sequencePosition += 1
                    storageItem["lineid"] = Node(keyLinenum)
                    keyArray.append(Node(storageKey))
                    for (langIndex,lang) in languages.enumerated() {
                        var endlinenum: Int = 0
                        if var linenum = tag[lang.2] as? Int {
                            if linenum > dataStrings[langIndex].count {
                                linenum = dataStrings[langIndex].count
                            }
                            endlinenum = linenum
                        }
                        let datatext = dataStrings[langIndex][lastline[langIndex] ..< endlinenum].joined(separator: "")
                        storageItem[lang.3] = Node(datatext) //escape ??
                        lastline[langIndex] = endlinenum
                    }
                    storageItem["key"] = Node(storageKey)
                    results.append(Node(storageItem))
                }

            }
            // need to add left over text
        } //for (sectionIndex, sectionType) in sections.enumerated()
        let keyForKeys = docId + "-" + "keys"
        results.append(Node(["key": Node(keyForKeys),
            keyForKeys: Node(keyArray)]))
        var response: [String: Node] = [:]
        response["document"] = Node(results)
        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(response))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
        return resp


//        return View(data: [UInt8](outDocument))
    }

    func commentariesSummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/review/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "review_page": Node(true),
            "role": Node("review")
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/review/")
        return try   pubDrop.view.make("role/review/commentaries", parameters)
    }
    func commentaryIndex(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {throw Abort.badRequest}  //go to list of all documents if not found


        var commentaryArray = try Commentary.query().filter(CommentaryConstants.documentId, documentdata!.id!).filter(CommentaryConstants.status, CommentaryStatus.analysis).all()
        commentaryArray.sort(by: Commentary.analyzeSort)

        var response: [String: Node] = [:]
        var results: [Node] = []

        for (index, commentary) in commentaryArray.enumerated() {
            var result: [String: Node] = commentary.forJSON()
            let commentstr = String(describing: commentary.id!.int!)
            result["order"] = Node(index)
            result["link"] = Node("<p><a class=\"btn btn-primary\" href=\"/review/documents/\(documentId)/commentaries/\(commentstr)\">View</a></p>")
            results.append(Node(result))

        }
        response["data"] = Node(results)
        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(response))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
        return resp
    }
    func commentarySummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        guard let commentaryId = request.parameters["commentaryId"]?.int, let commentary = try Commentary.find(commentaryId) else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/review/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "review_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/review/") //\(docjson[Document.JSONKeys.idbase62]!.string!)/
        parameters["commentarieshref"] = Node("/review/documents/\(docjson[Document.JSONKeys.idbase62]!.string!)/")
        parameters["commentary"] = Node(commentary.forJSON())
        return try   pubDrop.view.make("role/review/commentary", parameters)
    }
    func commentIndex(_ request: Request)throws -> ResponseRepresentable {
        guard let commentaryId = request.parameters["commentaryId"]?.int, let commentary = try Commentary.find(commentaryId) else {
            throw Abort.badRequest
        }
        guard let documentdata = try Document.find(commentary.document!) else {
            throw Abort.badRequest
        }

        //        let idInt = base62ToID(string: documentId)
        //        let documentdata = try Document.find(Node(idInt))
        //        guard documentdata != nil else {return Response(redirect: "/receive/")}  //go to list of all documents if not found


        let commentArray = try Comment.query().filter(Comment.Constants.commentaryId, commentaryId).all()

        var response: [String: Node] = [:]
        var results: [Node] = []

        for comment in commentArray {
            let result: [String: Node] = comment.forJSON()
            //            let commentstr = String(describing: commentary.id!.int!)
            //            result["link"] = Node("<p><a class=\"btn btn-primary\" href=\"/receive/documents/\(documentId)/commentaries/\(commentstr)\">View</a></p>")
            results.append(Node(result))

        }
        response["data"] = Node(results)
        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(response))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
        return resp
    }
    func commentaryUpdate(_ request: Request)throws -> ResponseRepresentable {
        guard let commentaryId = request.parameters["commentaryId"]?.int, var commentary = try Commentary.find(commentaryId) else {
            throw Abort.badRequest
        }
        guard let documentdata = try Document.find(commentary.document!) else {
            throw Abort.badRequest
        }
        if let commentator = request.data["commentary"]?.object {
            if let item = commentator["status"]?.string {
                let newitem = item.trimmingCharacters(in: .whitespacesAndNewlines)

                if !(newitem == commentary.status) {
                    commentary.updateStatus(to: newitem)
                    try commentary.save()
                }
            }
        }

        var response: [String: Node] = [:]

        response["commentary"] = Node(commentary.forJSON())
        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(response))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
        return resp
    }
    
    
}

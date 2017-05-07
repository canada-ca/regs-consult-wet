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

final class AnalyzeController {
    let pubDrop: Droplet

    init(to drop: Droplet, cookieSetter: AuthMiddlewareJWT, protect: RedirectAuthMiddlewareJWT) {
        pubDrop = drop

        let role = drop.grouped("analyze").grouped(cookieSetter).grouped(protect)
        role.get(handler: receiverSummary)
        role.get("documents", handler: documentIndex)

        let documentrole = role.grouped("documents")
        documentrole.get(":id", "comments", "summary", handler: allcommentsSummary)
        documentrole.get(":id", "comments", handler: allcommentsIndex)
        documentrole.get(":id", "comments", ":commentId", handler: commentSummary)
        documentrole.get(":id", handler: commentariesSummary)
        documentrole.get(":id","commentaries", handler: commentaryIndex)
        documentrole.get(":id","commentaries", ":commentaryId", handler: commentarySummary)
        role.get("commentaries", ":commentaryId","comments", handler: commentIndex)
        role.post("commentaries", ":commentaryId", ":command", handler: commentaryUpdate)
        documentrole.post(":id","notes", handler: notesUpdate)
    }
    func documentIndex(_ request: Request)throws -> ResponseRepresentable {

        let documentsArray = try Document.query().filter("archived", .notEquals, true).all()
        let commentaryStatusCounts = try Commentary.query().filter(CommentaryConstants.status, .in, [CommentaryStatus.new, CommentaryStatus.submitted, CommentaryStatus.analysis]).all().reduce([:]) {
            ( accu, element) in
            var accu2: [String: Int] = accu as! [String : Int]
            if let stat = element.status , let docid = element.document?.uint {
                let counthash = stat + String(docid)
                accu2[counthash] = (accu2[counthash] ?? 0) + 1
            }
            return accu2
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
            let countSubmitted: Int = commentaryStatusCounts[CommentaryStatus.submitted + docid] as? Int ?? 0
            let countNew: Int = commentaryStatusCounts[CommentaryStatus.new + docid]  as? Int ?? 0
            let countAnalysis: Int = commentaryStatusCounts[CommentaryStatus.analysis + docid] as? Int ?? 0
            let buttonStyle = countAnalysis == 0 ? "btn-default" : "btn-primary"
            let doc = String((result[Document.JSONKeys.idbase62]?.string!)!)!
            result["newsubmit"] = Node("<p><a class=\"btn btn-block \(buttonStyle)\" href=\"/analyze/documents/\(doc)/\">Analysis <span class=\"badge\">\(countAnalysis)<span class=\"wb-inv\"> submissions to accept</span></span></a><a class=\"btn btn-block btn-default\" href=\"/analyze/documents/\(doc)/\">Submissions <span class=\"badge\">\(countSubmitted)<span class=\"wb-inv\"> submissions to accept</span></span></a><a class=\"btn btn-default btn-block \" href=\"/analyze/documents/\(doc)/\">Composition <span class=\"badge\">\(countNew)<span class=\"wb-inv\"> not submitted</span></span></a></p>")
            result["commentlink"] = Node("<p><a class=\"btn btn-block btn-default\" href=\"/analyze/documents/\(doc)/comments/summary/\">All <span class=\"badge\">\(countSubmitted)<span class=\"wb-inv\"> comments</span></span></a></p>")
            result["notelink"] = Node("<p><a class=\"btn btn-block btn-default\" href=\"/analyze/documents/\(doc)/notes/summary/\">All <span class=\"badge\">\(countSubmitted)<span class=\"wb-inv\"> comments</span></span></a></p>")
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
            "analyze_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        return try   pubDrop.view.make("role/analyze/index", parameters)
    }

    func commentariesSummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "commentary_page": Node(true),
            "role": Node("analyze")
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/analyze/")
        return try   pubDrop.view.make("role/analyze/commentaries", parameters)
    }
    func commentaryIndex(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found


        var commentaryArray = try Commentary.query().filter(CommentaryConstants.documentId, documentdata!.id!).all()
        commentaryArray.sort(by: Commentary.analyzeSort)

        var response: [String: Node] = [:]
        var results: [Node] = []

        for (index, commentary) in commentaryArray.enumerated() {
            var result: [String: Node] = commentary.forJSON()
            let commentstr = String(describing: commentary.id!.int!)
            result["order"] = Node(index)
            result["link"] = Node("<p><a class=\"btn btn-primary\" href=\"/analyze/documents/\(documentId)/commentaries/\(commentstr)\">View</a></p>")
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
        guard documentdata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "commentary_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/analyze/") //\(docjson[Document.JSONKeys.idbase62]!.string!)/
        parameters["commentarieshref"] = Node("/analyze/documents/\(docjson[Document.JSONKeys.idbase62]!.string!)/")
        parameters["commentary"] = Node(commentary.forJSON())
        return try   pubDrop.view.make("role/analyze/commentary", parameters)
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


        var commentArray = try Comment.query().filter(Comment.Constants.commentaryId, commentaryId).all()
        commentArray.sort(by: Comment.docOrderSort)
        var response: [String: Node] = [:]
        var results: [Node] = []

        for (index, comment) in commentArray.enumerated() {
            var result: [String: Node] = comment.forJSON()
            result["order"] = Node(index)
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
    func allcommentsSummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }

        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "comments_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/analyze/") //\(docjson[Document.JSONKeys.idbase62]!.string!)/

        return try   pubDrop.view.make("role/analyze/comments", parameters)
    }

    func allcommentsIndex(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {throw Abort.badRequest}  //go to list of all documents if not found

        let commentaryStatus = try Commentary.query().filter(CommentaryConstants.documentId, idInt).filter(CommentaryConstants.status, .in, [CommentaryStatus.submitted, CommentaryStatus.analysis]).all()
        var commentarySet: Set<UInt> = []
        for  element in commentaryStatus {
            if let comm = element.id, let itemid = comm.uint {
                commentarySet.insert(itemid)
            }
        }
        let rawCommentArray = try Comment.query().filter(Comment.Constants.documentId, idInt).all()
        var commentArray = rawCommentArray.filter {
            if let comm = $0.commentary {
                return commentarySet.contains(comm.uint ?? 0)
            }
            return false
        }
        commentArray.sort(by: Comment.docOrderSort)
        var response: [String: Node] = [:]
        var results: [Node] = []

        for (index, comment) in commentArray.enumerated() {
            var result: [String: Node] = comment.forJSON()
            result["order"] = Node(index)
            let commentstr = String(describing: comment.id!.int!)
            result["link"] = Node("<p><a class=\"btn btn-default\" href=\"/analyze/documents/\(documentId)/comments/\(commentstr)\">Note</a></p>")
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
    func commentSummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        guard let commentId = request.parameters["commentId"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found
        
        let commentdata = try Comment.find(Node(commentId))
        guard commentdata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "comments_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        guard let usr = request.storage["userid"] as? User else {return Response(redirect: "/analyze/")}
        parameters["signedon"] = Node(true)
        parameters["activeuser"] = try usr.makeNode()


        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/analyze/")
        let commentjson = commentdata!.forJSON()
        parameters["comment"] = Node(commentjson)
        parameters["commentshref"] = Node("/analyze/documents/\(documentId)/comments/summary/")
        //\(docjson[Document.JSONKeys.idbase62]!.string!)/
        if let commentaryId = commentdata?.commentary, let commentary = try Commentary.find(commentaryId) {
            let commentstr = String(describing: commentary.id!.int!)
            parameters["commentaryhref"] = Node("/analyze/documents/\(docjson[Document.JSONKeys.idbase62]!.string!)/commentaries/\(commentstr)")
            parameters["commentary"] = Node(commentary.forJSON())
            let notesarray = try Note.query().filter(Note.Constants.commentaryId, commentary.id!).filter(Note.Constants.linenumber, commentdata!.linenumber).all()
            var otherNotes:[Node] = []
            for note in notesarray {
                if note.user == usr.id {
                    parameters["note"] = Node(note.forJSON())
                } else {
                    otherNotes.append(Node(note.forJSON()))
                }
            }
            parameters["notes"] = Node(otherNotes)
        }


        return try   pubDrop.view.make("role/analyze/noteedit", parameters)
    }

    func notesUpdate(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {throw Abort.custom(status: .conflict, message: "cannot locate document")}
        
        guard let usr = request.storage["userid"] as? User else {throw Abort.custom(status: .conflict, message: "cannot locate user")}

        if let notesarray = request.json?["notes"]?.array {
            for ind in 0..<notesarray.count {
                if let update = notesarray[ind].object {
                    var note: Note?
                    if let ref = update[Note.JSONKeys.id]?.int {
                        note = try Note.find(ref)
                    }
                    let lnum = update[Note.JSONKeys.linenumber]?.int ?? 0
                    if note == nil, let ref = update[Note.JSONKeys.commentaryId]?.int {
                        note = try Note.query().filter(Note.Constants.commentaryId, ref).filter(Note.Constants.userId, usr.id!).filter(Note.Constants.linenumber, lnum).first()
                        if note == nil {
                            let initNode:[String:Node] = [
                                Note.Constants.commentaryId: Node(ref),
                                Note.Constants.documentId: documentdata!.id!,
                                Note.Constants.userId: usr.id!,
                                Note.Constants.linenumber: Node(lnum)
                            ]
                            note = try Note(node: Node(initNode), in: [])
                        }
                        
                    }
                    guard note != nil, note!.user != usr.id! else { continue }
                    
                    if let item = update[Note.JSONKeys.linenumber]?.int {
                            note?.linenumber = item
                    }
                    if let item = update[Note.JSONKeys.status]?.string {
                        let newitem = item.trimmingCharacters(in: .whitespacesAndNewlines)
                        note?.status = newitem
                    }
                    if let item = update[Note.JSONKeys.statususer]?.string {
                        let newitem = item.trimmingCharacters(in: .whitespacesAndNewlines)
                        note?.statususer = newitem
                    }
                    if let item = update[Note.JSONKeys.statusshared]?.string {
                        let newitem = item.trimmingCharacters(in: .whitespacesAndNewlines)
                        note?.statusshared = newitem
                    }
                    if let item = update[Note.JSONKeys.textshared]?.string {
                        note?.textshared = item
                    }
                    if let item = update[Note.JSONKeys.textuser]?.string {
                        note?.textuser = item
                    }
                    try note!.save()

                }
            }
        }

        var response:[String: Node] = [:]

        response["note"] = Node(true)
        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(response))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
        return resp
    }

    
}

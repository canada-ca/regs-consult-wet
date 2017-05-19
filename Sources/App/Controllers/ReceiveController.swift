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

final class ReceiveController{
    let pubDrop: Droplet

    init(to drop: Droplet, cookieSetter: AuthMiddlewareJWT, protect: RedirectAuthMiddlewareJWT) {
        pubDrop = drop

        let role = drop.grouped("receive").grouped(cookieSetter).grouped(protect)
        role.get(handler: receiverSummary)
        role.get("documents", handler: documentIndex)

        let documentrole = role.grouped("documents", ":id")

        documentrole.get(handler: commentariesSummary)
        documentrole.get("commentaries", handler: commentaryIndex)
        documentrole.get("commentaries", ":commentaryId", handler: commentarySummary)
        documentrole.get("commentaries", "load", handler: commentaryLoad) //use to manually load commentaries
        documentrole.post("commentaries", "load", handler: commentaryLoader)
        role.get("commentaries", ":commentaryId","comments", handler: commentIndex)
        role.post("commentaries", ":commentaryId", ":command", handler: commentaryUpdate)
    }
    func documentIndex(_ request: Request)throws -> ResponseRepresentable {
       
        let documentsArray = try Document.query().filter("archived", .notEquals, true).all()

        var commentaryStatusCounts: [String:Int] = [:]
        let commentaryStatusArray = try Commentary.query().all()
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
            let docid = String(describing: document.id!.uint!)
            let doc = String((result[Document.JSONKeys.idbase62]?.string!)!)!
            result["newsubmit"] = Node( Commentary.dashboard(link: "/receive/documents/\(doc)/",
                commentaryCounts: [commentaryStatusCounts[CommentaryStatus.submitted + docid],
                                   commentaryStatusCounts[CommentaryStatus.attemptedsubmit + docid],
                                   commentaryStatusCounts[CommentaryStatus.analysis + docid],
                                   commentaryStatusCounts[CommentaryStatus.new + docid],
                                   commentaryStatusCounts[CommentaryStatus.notuseful + docid] ,
                                   commentaryStatusCounts[CommentaryStatus.abuse + docid]
                ]))


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
            "receive_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        return try   pubDrop.view.make("role/receive/index", parameters)
    }

    func commentariesSummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/receive/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "commentary_page": Node(true),
            "role": Node("receive"),
            "receive_page": Node(true)

            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/receive/") 
        return try   pubDrop.view.make("role/receive/commentaries", parameters)
    }
    func commentaryIndex(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/receive/")}  //go to list of all documents if not found


        var commentaryArray = try Commentary.query().filter(CommentaryConstants.documentId, documentdata!.id!).all()
        commentaryArray.sort(by: Commentary.receiveSort)

        var response: [String: Node] = [:]
        var results: [Node] = []

        for (index, commentary) in commentaryArray.enumerated() {
            var result: [String: Node] = commentary.forJSON()
            let commentstr = String(describing: commentary.id!.int!)
            result["order"] = Node(index)
            result["link"] = Node("<p><a class=\"btn btn-primary\" href=\"/receive/documents/\(documentId)/commentaries/\(commentstr)\">View</a></p>")
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
    func commentaryLoad(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/receive/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "commentary_page": Node(true),
            "role": Node("receive"),
            "receive_page": Node(true)

            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/receive/")
        return try   pubDrop.view.make("role/receive/commentaryload", parameters)
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
        guard documentdata != nil else {return Response(redirect: "/receive/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "commentary_page": Node(true),
            "receive_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/receive/")
        parameters["commentarieshref"] = Node("/receive/documents/\(docjson[Document.JSONKeys.idbase62]!.string!)/")
        parameters["commentary"] = Node(commentary.forJSON())
        return try   pubDrop.view.make("role/receive/commentary", parameters)
    }
    func commentIndex(_ request: Request)throws -> ResponseRepresentable {
        guard let commentaryId = request.parameters["commentaryId"]?.int, let commentary = try Commentary.find(commentaryId) else {
            throw Abort.badRequest
        }
        guard let _ = try Document.find(commentary.document!) else {
            throw Abort.badRequest
        }

        var commentArray = try Comment.query().filter(Comment.Constants.commentaryId, commentaryId).all()
        commentArray.sort(by: Comment.docOrderSort)
        var response: [String: Node] = [:]
        var results: [Node] = []

        for (index, comment) in commentArray.enumerated() {
            var result: [String: Node] = comment.forJSON()
            result["order"] = Node(index)
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
        guard let _ = try Document.find(commentary.document!) else {
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
    //needs generalization
    func commentaryLoader(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }

        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))

        if let commentaryFiles = request.data["commentaries"]?.array {
                for fileitem  in commentaryFiles {
                guard let file = fileitem as? JSON, let fn = file["filename"]?.string, let cmty = file["commentary"]?.object, let comments = file["comments"]?.array else {
                    continue
                }
                let lowBound = fn.index(fn.startIndex, offsetBy: 10)
                let hiBound = fn.index(fn.endIndex, offsetBy: -5)
                let midRange = lowBound ..< hiBound
                if let commid = Int(fn.substring(with: midRange)) {
                    guard try Commentary.find(commid) == nil else {
                        throw Abort.badRequest
                    }
                    var initial: Node = [CommentaryConstants.id: Node(commid)]
                    initial[CommentaryConstants.documentId] = documentdata!.id
                    
                    if let val = cmty[CommentaryConstants.name]?.string {
                        initial[CommentaryConstants.name] = Node(val)
                    }
                    if let val = cmty[CommentaryConstants.email]?.string {
                        initial[CommentaryConstants.email] = Node(val)
                    }
                    if let val = cmty[CommentaryConstants.represents]?.string {
                        initial[CommentaryConstants.represents] = Node(val)
                    }
                    if let val = cmty[CommentaryConstants.organization]?.string {
                        initial[CommentaryConstants.organization] = Node(val)
                    }
                    if let val = cmty["submitstatus"]?.string {
                        initial[CommentaryConstants.status] = Node(val)
                    }
                    guard var commentary = try? Commentary(node: initial, in: []) else {
                        throw Abort.badRequest
                    }
                    try commentary.save()
                    for comment in comments {
                        if let cmt = comment.object {
                        var initial: Node = [Comment.Constants.commentaryId: commentary.id!]
                        initial[Comment.Constants.documentId] = documentdata!.id

                        if let val = cmt["reftext"]?.string {
                            initial[Comment.Constants.reference] = Node(val)
                        }
                        if let val = cmt[Comment.Constants.text]?.string {
                            initial[Comment.Constants.text] = Node(val)
                        }
                        if let val = cmt[Comment.Constants.status]?.string {
                            initial[Comment.Constants.status] = Node(val)
                        }
                        if let val = cmt["ref"]?.string {
                            let lowBound = val.index(val.startIndex, offsetBy: 4)
                            let hiBound = val.index(val.endIndex, offsetBy: 0)
                            let midRange = lowBound ..< hiBound
                            let lineid = Int(val.substring(with: midRange)) ?? 0
                            initial[Comment.Constants.linenumber] = Node(lineid)
                        }

                        guard var newcomment = try? Comment(node: initial, in: []) else {
                            continue
                        }
                        try newcomment.save()
                        }
                    }
                }

            }
        }

        var response: [String: Node] = [:]

        response["commentary"] = Node(true)
        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(response))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
        return resp
    }

    

}

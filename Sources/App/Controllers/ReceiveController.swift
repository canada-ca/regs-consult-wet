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
//    let jwtSigner: Signer
//    let templateDir: String
//    let filePackDir: String
//    let fm = FileManager()
//    enum PreviewView {
//        case fullText
//        case onlyComments
//    }

    init(to drop: Droplet, cookieSetter: AuthMiddlewareJWT, protect: RedirectAuthMiddlewareJWT) {
        pubDrop = drop
//        templateDir = drop.workDir + "TemplatePacks/"
//        filePackDir = drop.workDir + "FilePacks/"

//        jwtSigner = HS256(key: (drop.config["crypto", "jwtuser","secret"]?.string ?? "secret").bytes)
        let receiver = drop.grouped("receive").grouped(cookieSetter).grouped(protect)
        receiver.get(handler: receiverSummary)
        receiver.get("documents", handler: documentIndex)
//        receiver.get("documents",":id", handler: commentariesSummary)
        let documentreceiver = receiver.grouped("documents")
//        documentreceiver.get(handler: documentIndex)
        documentreceiver.get(":id", handler: commentariesSummary)
        documentreceiver.get(":id","commentaries", handler: commentaryIndex)
        documentreceiver.get(":id","commentaries", ":commentaryId", handler: commentarySummary)
        receiver.get("commentaries", ":commentaryId","comments", handler: commentIndex)
    }
    func documentIndex(_ request: Request)throws -> ResponseRepresentable {
       
        let documentsArray = try Document.query().filter("archived", .notEquals, true).all()

        var response: [String: Node] = [:]
        var results: [Node] = []

        for document in documentsArray {
            var result: [String: Node] = document.forJSON()

            result["newsubmit"] = Node("<p><a class=\"btn btn-primary\" href=\"/receive/documents/\(String((result[Document.JSONKeys.idbase62]?.string!)!)!)/\">New <span class=\"badge\">42<span class=\"wb-inv\"> unread emails</span></span></a></p>")
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
            "commentary_page": Node(true)
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


        let commentaryArray = try Commentary.query().filter(CommentaryConstants.documentId, documentdata!.id!).all()

        var response: [String: Node] = [:]
        var results: [Node] = []

        for commentary in commentaryArray {
            var result: [String: Node] = commentary.forJSON()
            let commentstr = String(describing: commentary.id!.int!)
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
            "commentary_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/receive/") //\(docjson[Document.JSONKeys.idbase62]!.string!)/
        parameters["commentarieshref"] = Node("/receive/documents/\(docjson[Document.JSONKeys.idbase62]!.string!)/")
        parameters["commentary"] = Node(commentary.forJSON())
        return try   pubDrop.view.make("role/receive/commentary", parameters)
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
            var result: [String: Node] = comment.forJSON()
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

}

import HTTP
import JSON
import Vapor
import Auth
import Foundation
import JWT
import Node
import Cookies
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
        receiver.get("documents",":id", handler: commentarySummary)
        receiver.get("documents",":id","commentaries", handler: commentaryIndex)
        receiver.get("documents", handler: documentIndex)
        receiver.get(handler: receiverSummary)
    }
    func documentIndex(_ request: Request)throws -> ResponseRepresentable {
       
        let documentsArray = try Document.query().filter("archived", .notEquals, true).all()

        var response: [String: Node] = [:]
        var results: [Node] = []

        for document in documentsArray {
            var result: [String: Node] = document.forJSON()

            result["newsubmit"] = Node("<p><a class=\"btn btn-primary\" href=\"/receive/documents/\(String((result[Document.JSONKeys.idbase62]?.string!)!)!)/commentaries/\">New <span class=\"badge\">42<span class=\"wb-inv\"> unread emails</span></span></a></p>")
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

    func commentarySummary(_ request: Request)throws -> ResponseRepresentable {
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
        parameters["document"] = Node(documentdata!.forJSON())
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

            result["newsubmit"] = Node("<p><a class=\"btn btn-primary\" href=\"/receive/documents//commentaries/\">New <span class=\"badge\">42<span class=\"wb-inv\"> unread emails</span></span></a></p>")
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

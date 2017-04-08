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
        receiver.get("documents",":id","commentaries", handler: commentarySummary)
        receiver.get(handler: receiverSummary)
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
        var commid: UInt?
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/receive/documents/")}  //go to list of all documents if not found

         return try    pubDrop.view.make("receive", [
            "langeng": true,
            "signon": true,
            "signedon": true,
            "title": "Receive commentaries"

            ])
    }
}

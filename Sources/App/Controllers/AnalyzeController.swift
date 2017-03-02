import HTTP
import JSON
import Vapor
import Auth
import Foundation
import JWT
import Node
import Cookies
import FluentMySQL

final class AnalyzeController{
    let pubDrop: Droplet
    let jwtSigner: Signer
    let templateDir: String
    let filePackDir: String
    let fm = FileManager()
    enum PreviewView {
        case fullText
        case onlyComments
    }
    
    init(to drop: Droplet) {
        pubDrop = drop
        templateDir = drop.workDir + "TemplatePacks/"
        filePackDir = drop.workDir + "FilePacks/"

        jwtSigner = HS256(key: (drop.config["crypto", "jwtcommentary","secret"]?.string ?? "secret").bytes)
        let previewer = drop.grouped("analyze")
        previewer.get("documents",":id","commentaries", handler: commentarySummary)
        previewer.get("documents",":id","comments", handler: commentSummary)

        
    }

    func commentarySummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        var commid: UInt?
        let idInt = Base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/analyze/documents/")}  //go to list of all documents if not found

         return try    pubDrop.view.make("analyzecommentaries", [
            "langeng": true,
            "signon": true,
            "signedon": true,
            "title": "Analyze commentaries"

            ])
    }
    func commentSummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        var commid: UInt?
        let idInt = Base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/analyze/documents/")}  //go to list of all documents if not found
        var contextNode = Node([
            "langeng": true,
            "signon": true,
            "signedon": true,
            "title": "Analyze comments"

            ])
        contextNode["document"] = documentdata?.nodeForJSON()
        return try    pubDrop.view.make("analyzecomments",contextNode )
    }



}

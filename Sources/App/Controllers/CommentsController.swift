import HTTP
import JSON
import Vapor
import Auth
import Foundation
import JWT
import Node
import Cookies
import FluentMySQL

final class CommentsController{
    let pubDrop: Droplet
    let jwtSigner: Signer
    static let cookieComment = "consult-comment"
    init(to drop: Droplet) {
        pubDrop = drop
        jwtSigner = HS256(key: (drop.config["crypto", "jwtcommentary","secret"]?.string ?? "secret").bytes)
        drop.post("documents",":id","comments", handler: commentDocument)

    }


    func commentDocument(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }

        //locate document
        let idInt = Base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {throw Abort.custom(status: .notFound, message: "document unknown")}

        //try to find the commentary from the JSON Web Token
        var commentary: Commentary?
        var commid: UInt? //Commentary.id
        var commentJWT: JWT?
        if let incookie = request.cookies[CommentsController.cookieComment] {
            commentJWT = try? JWT(token: incookie)
        }

        if commentJWT != nil {
            do {
                try commentJWT!.verifySignature(using: jwtSigner)
                commid = commentJWT!.payload["commid"]?.uint
            } catch {
                commentJWT = nil  //did not pass - new one will be started
            }
        }
        // find the commentary in the token
        if  commid != nil {
            do{
                commentary = try Commentary.find(Node(commid!))
            } catch{
                pubDrop.console.info("Did not find \(commid)")
            }
        }
        // If we did not find it then we need to make one
        if  commentary == nil {

            var newDbId:Node = Node(UniqueID32())
            for i in 1...5 {
                if (try Commentary.find(newDbId)) != nil {
                    if i == 5 {
                       throw Abort.custom(status: .conflict, message: "cannot start a new commentary") // too hard to find a new random id!
                    } else {
                        newDbId = Node(UniqueID32())
                        continue
                    }
                }
            }

            commentary = try Commentary(node: [Commentary.Constants.id:newDbId,
                                               Commentary.Constants.documentId:documentdata?.id], in: [])
            try commentary!.save()
            commid = commentary?.id?.uint
            commentJWT = nil //need to force a new jwt cookie as old commentary not valid
            pubDrop.console.info("New Commentary \(commid)")

        }

        guard commentary != nil else {throw Abort.custom(status: .conflict, message: "cannot locate commentary")}

        var responseDict = ["updatestatus":Node(documentId)]
        //process update from tne commentator identity
        if let commentator = request.data["commentary"]?.object {
            if let item = commentator["email"]?.string  {
                let newitem = item.trimmingCharacters(in: .whitespacesAndNewlines)

                if !(newitem == commentary?.email?.value) {
                    do{
                        let updateem =  Email(value: newitem)
                        if !newitem.isEmpty {
                            try Email.validate(input: updateem)
                        }
                        commentary?.email = updateem
                    } catch {
                        //new value bad
                        pubDrop.console.info("New email value bad \(newitem)")
                    }
                }
            }
            if let item = commentator["name"]?.string  {
                let newitem = item.trimmingCharacters(in: .whitespacesAndNewlines)

                if !(newitem == commentary?.name) {
                    do{

                        commentary?.name = newitem
                    } catch {
                        //new value bad
                        pubDrop.console.info("New name value bad \(newitem)")
                    }
                }
            }
            if let item = commentator["organization"]?.string  {
                let newitem = item.trimmingCharacters(in: .whitespacesAndNewlines)

                if !(newitem == commentary?.organization) {
                    do{

                        commentary?.organization = newitem
                    } catch {
                        //new value bad
                        pubDrop.console.info("New organization value bad \(newitem)")
                    }
                }
            }
            if let item = commentator["represents"]?.string  {
                let newitem = item.trimmingCharacters(in: .whitespacesAndNewlines)

                if !(newitem == commentary?.represents) {
                    do{

                        commentary?.represents = newitem
                    } catch {
                        //new value bad
                        pubDrop.console.info("New represents value bad \(newitem)")
                    }
                }
            }
            responseDict["commentary"] = commentary!.nodeForJSON()

        }
        try commentary!.save()
        //update from tne array of comments
        if let commarray = request.json?["comments"]?.array {
            for ind in 0..<commarray.count {
                if let update = commarray[ind].object {
                    if let ref = update["ref"]?.string {
                        var comment = try Comment.query().filter("commentary_id", commentary!.id!).filter("reference", ref as NodeRepresentable).first()
                        if comment == nil {
                            comment = try Comment(node: [
                                Comment.Constants.documentId: documentdata!.id!,
                                Comment.Constants.commentaryId: commentary!.id!,
                                Comment.Constants.reference: ref,
                                Comment.Constants.text: update["text"]?.string,
                                Comment.Constants.status: Comment.Status.new

                                               ], in: [])
                        } else {
                            if documentdata?.id == comment?.document {
                                comment?.text = update["text"]?.string
                            }
                        }
                        try comment!.save()
                    }
                }
            }
        }


        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(responseDict))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
         if commentJWT == nil {
            commentJWT = try JWT(payload: Node.object(["commid":Node(commid!)]),
                                 signer: jwtSigner)
            if let token = try commentJWT?.createToken() {
                let myCookie = Cookie(name: CommentsController.cookieComment,value: token, expires: Date() + 7 * 24 * 3600, domain: pubDrop.config["app", "appdomain"]?.string ?? "example.com", httpOnly: true)
                resp.cookies.insert(myCookie)
            }
        }

        return resp
    }
}

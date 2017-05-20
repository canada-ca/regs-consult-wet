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
        documentrole.get("comments", "summary", handler: allCommentsSummary)
        documentrole.get("comments", handler: allCommentsIndex)
        documentrole.get("comments", ":commentId", handler: commentSummary)
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
        let commentaryStatusArray = try Commentary.query().filter(CommentaryConstants.status,  CommentaryStatus.analysis).all()
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
//            let countSubmitted: Int = commentaryStatusCounts[CommentaryStatus.submitted + docid] ?? 0
//            let countNew: Int = commentaryStatusCounts[CommentaryStatus.new + docid] ?? 0
//            let countAnalysis: Int = commentaryStatusCounts[CommentaryStatus.analysis + docid] ?? 0
//            let buttonStyle = countAnalysis == 0 ? "btn-default" : "btn-primary"
            let doc = String((result[Document.JSONKeys.idbase62]?.string!)!)!
//            result["newsubmit"] = Node("<p><a class=\"btn btn-block \(buttonStyle)\" href=\"/review/documents/\(doc)/\">Analysis <span class=\"badge\">\(countAnalysis)<span class=\"wb-inv\"> submissions to accept</span></span></a><a class=\"btn btn-block btn-default\" href=\"/receive/documents/\(doc)/\">Submissions <span class=\"badge\">\(countSubmitted)<span class=\"wb-inv\"> submissions to accept</span></span></a><a class=\"btn btn-default btn-block \" href=\"/receive/documents/\(doc)/\">Composition <span class=\"badge\">\(countNew)<span class=\"wb-inv\"> not submitted</span></span></a></p>")
            result["newsubmit"] = Node( Commentary.dashboard(link: "/review/documents/\(doc)/",
                commentaryCounts: [commentaryStatusCounts[CommentaryStatus.submitted + docid],
                                   commentaryStatusCounts[CommentaryStatus.attemptedsubmit + docid],
                                   commentaryStatusCounts[CommentaryStatus.analysis + docid],
                                   commentaryStatusCounts[CommentaryStatus.new + docid],
                                   commentaryStatusCounts[CommentaryStatus.notuseful + docid] ,
                                   commentaryStatusCounts[CommentaryStatus.abuse + docid]
                ]))
            result["commentlink"] = Node("<p><a class=\"btn btn-block btn-default\" href=\"/review/documents/\(doc)/comments/summary/\">Comments and decisions</p>")
            
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
        commentaryArray.sort(by: Commentary.reviewSort)

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
        let documentId = documentdata.docID()
        //        let idInt = base62ToID(string: documentId)
        //        let documentdata = try Document.find(Node(idInt))
        //        guard documentdata != nil else {return Response(redirect: "/receive/")}  //go to list of all documents if not found


        var commentArray = try Comment.query().filter(Comment.Constants.commentaryId, commentaryId).all()
        commentArray.sort(by: Comment.docOrderSort)

        guard let usr = request.storage["userid"] as? User else {throw Abort.badRequest}

        let rawNoteArray = try Note.query().filter(Note.Constants.commentaryId, commentaryId).all()
        var usersOwnNote: [String: Note] = [:]
        var accu2: [String: Int] = [:]
        var dispositionNote: [String: [Note]?] = [:]
        rawNoteArray.forEach { nte in

            let keyidx = "\(String(describing: nte.commentary?.uint ?? 0))\(String(describing: nte.reference!))\(nte.linenumber)"
            if nte.user == usr.id! {
                usersOwnNote[keyidx] = nte
            }
            accu2[keyidx] = (accu2[keyidx] ?? 0) + 1
            if let stat = nte.status, stat != "" { //subcount on status
                let key = keyidx + stat
                accu2[key] = (accu2[key] ?? 0) + 1
                if stat == Note.Status.decision {
                    if var arry = dispositionNote[keyidx] as? [Note] {
                        arry.append(nte)
                        dispositionNote[keyidx] = arry
                    } else {
                        dispositionNote[keyidx] = [nte]
                    }
                }
            }

        }

        var response: [String: Node] = [:]
        var results: [Node] = []

        for (index, comment) in commentArray.enumerated() {
            var result: [String: Node] = comment.forJSON()
            result["order"] = Node(index)
            let commentstr = String(describing: comment.id!.int!)
            let keyidx = "\(comment.commentary!.int!)\(String(describing: comment.reference!))\(comment.linenumber)"
            result["disposition"] = Node( Note.format(notes: dispositionNote[keyidx] ?? []))
            result["link"] = Node( Note.dashboard(link: "/analyze/documents/\(documentId)/comments/\(commentstr)",
                userNoteStatus: usersOwnNote[keyidx]?.status,
                noteCounts: [accu2[keyidx + Note.Status.decision],
                             accu2[keyidx + Note.Status.discard],
                             accu2[keyidx + Note.Status.ready],
                             accu2[keyidx + Note.Status.inprogress]   ]))


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
    func allCommentsSummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }

        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/review/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "comments_page": Node(true),
            "review_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/review/")

        return try   pubDrop.view.make("role/review/comments", parameters)
    }

    func allCommentsIndex(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {throw Abort.badRequest}  //go to list of all documents if not found

        let commentaryStatus = try Commentary.query().filter(CommentaryConstants.documentId, idInt).filter(CommentaryConstants.status, CommentaryStatus.analysis).all()
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

        guard let usr = request.storage["userid"] as? User else {return Response(redirect: "/review/")}
        let rawNoteArray = try Note.query().filter(Note.Constants.documentId, idInt).all()
        var usersOwnNote: [String: Note] = [:]
        var accu2: [String: Int] = [:]
        var decisionNote: [String: [Note]?] = [:]
        var discardNote: [String: [Note]?] = [:]
        var readyNote: [String: [Note]?] = [:]
        rawNoteArray.forEach { nte in
            if let comm = nte.commentary {
                if commentarySet.contains(comm.uint ?? 0) {
                    let keyidx = "\(String(describing: comm.uint ?? 0))\(String(describing: nte.reference!))\(nte.linenumber)"
                    if nte.user == usr.id! {
                        usersOwnNote[keyidx] = nte

                    }
                    accu2[keyidx] = (accu2[keyidx] ?? 0) + 1
                    if let stat = nte.status, stat != "" { //subcount on status
                        let key = keyidx + stat
                        accu2[key] = (accu2[key] ?? 0) + 1
                        switch stat {
                        case Note.Status.decision:
                            if var arry = decisionNote[keyidx] as? [Note] {
                                arry.append(nte)
                                decisionNote[keyidx] = arry
                            } else {
                                decisionNote[keyidx] = [nte]
                            }
                        case Note.Status.discard:
                            if var arry = discardNote[keyidx] as? [Note] {
                                arry.append(nte)
                                discardNote[keyidx] = arry
                            } else {
                                discardNote[keyidx] = [nte]
                            }
                        case Note.Status.ready:
                            if var arry = readyNote[keyidx] as? [Note] {
                                arry.append(nte)
                                readyNote[keyidx] = arry
                            } else {
                                readyNote[keyidx] = [nte]
                            }
                        default:
                            break
                        }
                    }
                }
            }
        }

        var response: [String: Node] = [:]
        var results: [Node] = []

        for (index, comment) in commentArray.enumerated() {
            var result: [String: Node] = comment.forJSON()
            result["order"] = Node(index)
            let commentstr = String(describing: comment.id!.int!)


            let keyidx = "\(comment.commentary!.int!)\(String(describing: comment.reference!))\(comment.linenumber)"
            var dispositionhtml = Note.format(notes: decisionNote[keyidx] ?? [])
            dispositionhtml += Note.format(notes: discardNote[keyidx] ?? [])
            dispositionhtml += Note.format(notes: readyNote[keyidx] ?? [])
            result["disposition"] = Node(dispositionhtml)

            result["link"] = Node( Note.dashboard(link: "/review/documents/\(documentId)/comments/\(commentstr)",
                userNoteStatus: usersOwnNote[keyidx]?.status,
                noteCounts: [accu2[keyidx + Note.Status.decision],
                             accu2[keyidx + Note.Status.discard],
                             accu2[keyidx + Note.Status.ready],
                             accu2[keyidx + Note.Status.inprogress]   ]))
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

    func commentSummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        guard let commentId = request.parameters["commentId"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/review/")}  //go to list of all documents if not found

        let commentdata = try Comment.find(Node(commentId))
        guard commentdata != nil else {return Response(redirect: "/review/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "comments_page": Node(true),
            "review_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        guard let usr = request.storage["userid"] as? User else {return Response(redirect: "/review/")}
        parameters["signedon"] = Node(true)
        parameters["activeuser"] = try usr.makeNode()


        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/review/")
        let commentjson = commentdata!.forJSON()
        parameters["comment"] = Node(commentjson)
        parameters["commentshref"] = Node("/review/documents/\(documentId)/comments/summary/")
        //\(docjson[Document.JSONKeys.idbase62]!.string!)/
        if let commentaryId = commentdata?.commentary, let commentary = try Commentary.find(commentaryId) {
            let commentstr = String(describing: commentary.id!.int!)
            parameters["commentaryhref"] = Node("/review/documents/\(docjson[Document.JSONKeys.idbase62]!.string!)/commentaries/\(commentstr)")
            parameters["commentary"] = Node(commentary.forJSON())
            var notesarray = try Note.query().filter(Note.Constants.commentaryId, commentary.id!).filter(Note.Constants.linenumber, commentdata!.linenumber).filter(Note.Constants.reference, commentdata!.reference!).all()
            var userIDsWithNotes: Set<Int> = []
            notesarray.forEach() {nte in
                if let usrId = nte.user?.int {
                    userIDsWithNotes.insert(usrId)
                }
            }
            notesarray.sort(by: Note.singleDocOrderSort)
            
            var usersWithNotes: [Int: User] = [:]
            if userIDsWithNotes.count > 0 {
                let usersFetched = try User.query().filter("id", .in, userIDsWithNotes.map{$0}).all()

                usersFetched.forEach() {usr in
                    if let usridx = usr.id?.int {
                        usersWithNotes[usridx] = usr
                    }
                }
            }
            var otherNotes:[Node] = []
            var usrlist:[Node] = []
            for note in notesarray {
                var thisNote = note.forJSON(usr)
                let usrname = Node(usersWithNotes[note.user?.int ?? 0]?.name ?? "unknown")
                thisNote["username"] = usrname
                if note.user == usr.id {
                    parameters["note"] = Node(thisNote)
                } else {
                    otherNotes.append(Node(thisNote))
                    usrlist.append(usrname)
                }
            }

            parameters["notescount"] = Node(otherNotes.count)
            if usrlist.count > 0 {parameters["notesusers"] = Node(usrlist)}
            if otherNotes.count > 0 {parameters["notes"] = Node(otherNotes)}
        }


        return try   pubDrop.view.make("role/review/noteedit", parameters)
    }
}

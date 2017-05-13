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
import SwiftMarkdown
import Base62

final class AnalyzeController {
    let pubDrop: Droplet

    init(to drop: Droplet, cookieSetter: AuthMiddlewareJWT, protect: RedirectAuthMiddlewareJWT) {
        pubDrop = drop

        let role = drop.grouped("analyze").grouped(cookieSetter).grouped(protect)
        role.get(handler: roleSummary)
        role.get("documents", handler: documentIndex)

        let documentrole = role.grouped("documents", ":id")
        documentrole.get("comments", "summary", handler: allCommentsSummary)
        documentrole.get("comments", handler: allCommentsIndex)
        documentrole.get("comments", ":commentId", handler: commentSummary)
        documentrole.get("notes", "summary", handler: allNotesSummary)
        documentrole.get("notes", handler: allNotesIndex)
        documentrole.get("notes", ":noteId", handler: noteSummary)
        documentrole.get("notes", ":noteId", ":command", handler: noteCommand)
        documentrole.get(handler: commentariesSummary)
        documentrole.get("commentaries", handler: commentaryIndex)
        documentrole.get("commentaries", ":commentaryId", handler: commentarySummary)
        role.get("commentaries", ":commentaryId","comments", handler: commentIndex)
        role.post("commentaries", ":commentaryId", ":command", handler: commentaryUpdate)
        documentrole.post("notes", handler: notesUpdate)
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

    func roleSummary(_ request: Request)throws -> ResponseRepresentable {

        var parameters = try Node(node: [
            "analyze_page": Node(true),
            "role": Node("analyze")
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
            "role": Node("analyze"),
            "analyze_page": Node(true)
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
        guard documentdata != nil else {throw Abort.badRequest}  //go to list of all documents if not found


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
            "commentary_page": Node(true),
            "analyze_page": Node(true)
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
        let docID = documentdata.docID()
        //        let idInt = base62ToID(string: documentId)
        //        let documentdata = try Document.find(Node(idInt))
        //        guard documentdata != nil else {return Response(redirect: "/receive/")}  //go to list of all documents if not found


        var commentArray = try Comment.query().filter(Comment.Constants.commentaryId, commentaryId).all()
        commentArray.sort(by: Comment.docOrderSort)

        guard let usr = request.storage["userid"] as? User else {throw Abort.badRequest}
        
        let rawNoteArray = try Note.query().filter(Note.Constants.commentaryId, commentaryId).all()
        var accu: [String: Int] = [:]
        var accu2: [String: Int] = [:]
        rawNoteArray.forEach { nte in

            let keyidx = "\(String(describing: nte.commentary?.uint ?? 0))\(String(describing: nte.reference!))\(nte.linenumber)"
            if nte.user == usr.id! {
                accu[keyidx] = (accu[keyidx] ?? 0) + 1
            } //else {
            accu2[keyidx] = (accu2[keyidx] ?? 0) + 1
            //}

        }

        var response: [String: Node] = [:]
        var results: [Node] = []

        for (index, comment) in commentArray.enumerated() {
            var result: [String: Node] = comment.forJSON()
            result["order"] = Node(index)
            let commentstr = String(describing: comment.id!.int!)
            let keyidx = "\(comment.commentary!.int!)\(String(describing: comment.reference!))\(comment.linenumber)"
            let buttonText = (accu[keyidx] == nil ? "Note&nbsp;+" : "Note")
            if let countOtherNotes = accu2[keyidx] {
                result["link"] = Node("<p><a class=\"btn btn-default\" href=\"/analyze/documents/\(docID)/comments/\(commentstr)\">\(buttonText) <span class=\"badge\">\(countOtherNotes)<span class=\"wb-inv\"> comments</span></span></a></p>")
            } else {
                result["link"] = Node("<p><a class=\"btn btn-default\" href=\"/analyze/documents/\(docID)/comments/\(commentstr)\">\(buttonText)</a></p>")
            }
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
    func allCommentsSummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }

        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "comments_page": Node(true),
            "analyze_page": Node(true)
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

    func allCommentsIndex(_ request: Request)throws -> ResponseRepresentable {
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

        guard let usr = request.storage["userid"] as? User else {return Response(redirect: "/analyze/")}
        let rawNoteArray = try Note.query().filter(Note.Constants.documentId, idInt).all()
        var usersOwnNote: [String: Note] = [:]
        var accu2: [String: Int] = [:]

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
            var buttonText = "Note&nbsp;+"
            if let usrNote = usersOwnNote[keyidx], let noteStatus = usrNote.status {
                switch noteStatus {
                case Note.Status.review:
                    buttonText = "<span class=\"bg-primary\">&nbsp;Note&nbsp;</span>"
                case Note.Status.disposition:
                    buttonText = "<span class=\"bg-success\">&nbsp;Note&nbsp;</span>"
                default:
                    break
                }
            }
          
            var notesInAnalysisBadge:String = ""

            if let notesInAnalysis = accu2[keyidx + Note.Status.analysis] {
                notesInAnalysisBadge = "<span class=\"badge badge-default\">\(notesInAnalysis)<span class=\"wb-inv\">notes in analysis</span></span>"
            }
            var notesInReviewBadge:String = ""
            if let notesInReview = accu2[keyidx + Note.Status.review] {
                notesInReviewBadge = "<span class=\"badge badge-primary\">\(notesInReview)<span class=\"wb-inv\">notes in review</span></span>"
            }
            var notesInDispositionBadge:String = ""
            if let notesInDisposition = accu2[keyidx + Note.Status.disposition] {
                notesInDispositionBadge = "<span class=\"badge badge-success\">\(notesInDisposition)<span class=\"wb-inv\">notes in disposition</span></span>"
            }

            result["link"] = Node("<p><a class=\"btn btn-default\" href=\"/analyze/documents/\(documentId)/comments/\(commentstr)\">\(buttonText) \(notesInAnalysisBadge)\(notesInReviewBadge)\(notesInDispositionBadge)</p>")

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
            "comments_page": Node(true),
            "analyze_page": Node(true)
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
            let notesarray = try Note.query().filter(Note.Constants.commentaryId, commentary.id!).filter(Note.Constants.linenumber, commentdata!.linenumber).filter(Note.Constants.reference, commentdata!.reference!).all()
            var userIDsWithNotes: Set<Int> = []
            notesarray.forEach() {nte in
                if let usrId = nte.user?.int {
                    userIDsWithNotes.insert(usrId)
                }
            }
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
                var thisNote = note.forJSON()
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


        return try   pubDrop.view.make("role/analyze/noteedit", parameters)
    }
    func noteCommand(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string, let command = request.parameters["command"]?.string else {
            throw Abort.badRequest
        }
        guard let noteId = request.parameters["noteId"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found
        var parameters = try Node(node: [
            "notes_page": Node(true),
            "analyze_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        guard let usr = request.storage["userid"] as? User else {return Response(redirect: "/analyze/")}

        parameters["signedon"] = Node(true)
        parameters["activeuser"] = try usr.makeNode()

        if let note = try Note.find(Node(noteId)) {
            if note.user == usr.id, documentdata!.id == note.document {
                switch command {
                case "delete":
                    try? note.delete()
                default:
                    break
                }

            }
        }

        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/analyze/") //\(docjson[Document.JSONKeys.idbase62]!.string!)/

        return try   pubDrop.view.make("role/analyze/notes", parameters)
    }


    func allNotesSummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }

        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "notes_page": Node(true),
            "analyze_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        if let usr = request.storage["userid"] as? User {
            parameters["signedon"] = Node(true)
            parameters["activeuser"] = try usr.makeNode()
        }
        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/analyze/") //\(docjson[Document.JSONKeys.idbase62]!.string!)/

        return try   pubDrop.view.make("role/analyze/notes", parameters)
    }

    func allNotesIndex(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {throw Abort.badRequest}  //go to list of all documents if not found

        let commentaryStatus = try Commentary.query().filter(CommentaryConstants.documentId, idInt).filter(CommentaryConstants.status, .in, [CommentaryStatus.submitted, CommentaryStatus.analysis]).all()
        var commentaryDict: [UInt:Commentary] = [:]
        for  element in commentaryStatus {
            if let comm = element.id, let itemid = comm.uint {
                commentaryDict[itemid] = element
            }
        }
        guard let usr = request.storage["userid"] as? User else {return Response(redirect: "/analyze/")}
        var rawNoteArray = try Note.query().filter(Note.Constants.documentId, idInt).filter(Note.Constants.userId, usr.id!).all()

        rawNoteArray.sort(by: Note.singleDocOrderSort)




        var response: [String: Node] = [:]
        var results: [Node] = []
        let notelead = "<div>"
        let noteseparator = "</div></section><section class=\"panel panel-info\"><header class=\"panel-heading\"><h5 class=\"panel-title\">Private Note</h5></header><div class=\"panel-body\">"
        let notetail = "</div></section>"
        for (index, note) in rawNoteArray.enumerated() {
            var result: [String: Node] = note.forJSON()
            result["order"] = Node(index)
            let sharedhtml = try? markdownToHTML(note.textshared ?? "")
            let userhtml =  try? markdownToHTML(note.textuser ?? "")
            if userhtml == "" {
                result["notehtml"] = Node(notelead + (sharedhtml ?? "") + notetail)
            } else {
                result["notehtml"] = Node(notelead + (sharedhtml ?? "") + noteseparator + (userhtml ?? "") + notetail)
            }
            if let cmty = note.commentary, let itemid = cmty.uint, let comm = commentaryDict[itemid] {
                result[CommentaryJSONKeys.represents] = Node(comm.represents ?? "")
            } else {
                result[CommentaryJSONKeys.represents] = Node("unknown")
            }
            let notestr = String(describing: note.id!.int!)
            result["link"] = Node("<p><a class=\"btn btn-default\" href=\"/analyze/documents/\(documentId)/notes/\(notestr)\"><i class=\"fa fa-edit\" aria-hidden=\"true\"></i> Edit Note</a></p><p><a class=\"btn btn-warning delete-note\" href=\"/analyze/documents/\(documentId)/notes/\(notestr)/delete\"><i class=\"fa fa-trash-o\" aria-hidden=\"true\"></i></a></p>")

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

    func noteSummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        guard let noteId = request.parameters["noteId"]?.string else {
            throw Abort.badRequest
        }
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found

        let notedata = try Note.find(Node(noteId))
        guard notedata != nil else {return Response(redirect: "/analyze/")}  //go to list of all documents if not found

        var parameters = try Node(node: [
            "notes_page": Node(true),
            "analyze_page": Node(true)
            ])
        parameters["signon"] = Node(true)
        guard let usr = request.storage["userid"] as? User, notedata?.user == usr.id else {return Response(redirect: "/analyze/")}
        parameters["signedon"] = Node(true)
        parameters["activeuser"] = try usr.makeNode()


        let docjson = documentdata!.forJSON()
        parameters["document"] = Node(docjson)
        parameters["documentshref"] = Node("/analyze/")

        parameters["commentshref"] = Node("/analyze/documents/\(documentId)/notes/summary/")
        //\(docjson[Document.JSONKeys.idbase62]!.string!)/
        if let commentaryId = notedata?.commentary, let commentary = try Commentary.find(commentaryId) {
            let commentstr = String(describing: commentary.id!.int!)
            parameters["commentaryhref"] = Node("/analyze/documents/\(docjson[Document.JSONKeys.idbase62]!.string!)/commentaries/\(commentstr)")
            parameters["commentary"] = Node(commentary.forJSON())
            if let commentdata = try Comment.query().filter(Comment.Constants.commentaryId, commentary.id!).filter(Comment.Constants.linenumber, notedata!.linenumber).filter(Comment.Constants.reference, notedata!.reference!).first() {
                let commentjson = commentdata.forJSON()
                parameters["comment"] = Node(commentjson)
            }
            let notesarray = try Note.query().filter(Note.Constants.commentaryId, commentary.id!).filter(Note.Constants.linenumber, notedata!.linenumber).filter(Note.Constants.reference, notedata!.reference!).all()
            var userIDsWithNotes: Set<Int> = []
            notesarray.forEach() {nte in
                if let usrId = nte.user?.int {
                    userIDsWithNotes.insert(usrId)
                }
            }
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
                var thisNote = note.forJSON()
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
                    var noteExisted: Bool = true
                    var noteHasContent: Bool = false
                    if let refID = update[Note.JSONKeys.id]?.int {
                        note = try Note.find(refID)
                    }
                    let lnum = update[Note.JSONKeys.linenumber]?.int ?? 0
                    let ref = update[Note.JSONKeys.reference]?.string ?? ""
                    if note == nil, let refID = update[Note.JSONKeys.commentaryId]?.int {
//                        note = try Note.query().filter(Note.Constants.commentaryId, refID).filter(Note.Constants.userId, usr.id!).filter(Note.Constants.linenumber, lnum).filter(Note.Constants.reference, ref).first()
                         note = try Note.query().filter(Note.Constants.commentaryId, Node(refID)).filter(Note.Constants.userId, usr.id!).filter(Note.Constants.linenumber, lnum).filter(Note.Constants.reference, ref).first()
                        if note == nil {
                            let initNode:[String:Node] = [
                                Note.Constants.commentaryId: Node(refID),
                                Note.Constants.documentId: documentdata!.id!,
                                Note.Constants.userId: usr.id!,
                                Note.Constants.reference: Node(ref),
                                Note.Constants.linenumber: Node(lnum)
                            ]
                            note = try Note(node: Node(initNode), in: [])
                            noteExisted = false
                        }
                        
                    }
                    guard note != nil, note!.user == usr.id! else { continue }
                    
                    if let item = update[Note.JSONKeys.linenumber]?.int {
                            note?.linenumber = item
                    }
                    if let item = update[Note.JSONKeys.reference]?.string {
                        note?.reference = item
                    }
                    if let item = update[Note.JSONKeys.status]?.string {
                        let newitem = item.trimmingCharacters(in: .whitespacesAndNewlines)
                        note?.updateStatus(of: Note.JSONKeys.status, to: newitem)
                        if let content = note?.status, content != Note.Status.analysis { noteHasContent = true }
                    }
                    if let item = update[Note.JSONKeys.statususer]?.string {
                        let newitem = item.trimmingCharacters(in: .whitespacesAndNewlines)
                        note?.statususer = newitem
                        if let content = note?.statususer, !content.isEmpty { noteHasContent = true }
                    }
                    if let item = update[Note.JSONKeys.statusshared]?.string {
                        let newitem = item.trimmingCharacters(in: .whitespacesAndNewlines)
                        note?.statusshared = newitem
                        if let content = note?.statusshared, !content.isEmpty { noteHasContent = true }
                    }
                    if let item = update[Note.JSONKeys.textshared]?.string {
                        note?.textshared = item
                        if let content = note?.textshared, !content.isEmpty { noteHasContent = true }
                    }
                    if let item = update[Note.JSONKeys.textuser]?.string {
                        note?.textuser = item
                         if let content = note?.textuser, !content.isEmpty { noteHasContent = true }
                    }
                    if noteHasContent {
                        try note!.save()
                    } else if noteExisted {
                        try note!.delete()   //Used to clean empty notes
                    }

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

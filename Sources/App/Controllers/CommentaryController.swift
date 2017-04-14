import HTTP
import JSON
import Vapor
import Auth
import Foundation
import JWT
import Node
import Cookies
import FluentMySQL
import Hedwig

enum MailStyle {
    case json
    case jsonbackup
    case html
}
final class CommentaryController{
    let pubDrop: Droplet
    let jwtSigner: Signer
    let templateDir: String
    let filePackDir: String
    let submitRender: LeafRenderer
    let hedwig: Hedwig
    let fm = FileManager()
    enum PreviewView {
        case fullText
        case onlyComments
    }

    init(to drop: Droplet) {
        hedwig = Hedwig(
            hostName: drop.config["mail", "smtp", "hostName"]?.string ?? "example.com",
            user:  drop.config["mail", "smtp", "user"]?.string ?? "foo@example.com",
            password: drop.config["mail", "smtp", "password"]?.string ?? "password",
            authMethods: [.plain, .login] // Default: [.plain, .cramMD5, .login, .xOauth2]
        )
        pubDrop = drop
        templateDir = drop.workDir + "TemplatePacks/"
        filePackDir = drop.workDir + "FilePacks/"
        submitRender = LeafRenderer(viewsDir: drop.viewsDir)
        jwtSigner = HS256(key: (drop.config["crypto", "jwtcommentary", "secret"]?.string ?? "secret").bytes)
        let previewer = drop.grouped("documents",":id", "commentaries")
        previewer.get("summary", handler: commentarySummary)
//        previewer.get("submit",":command", handler: commentarySubmit)
        previewer.post("submit", ":command", handler: commentarySubmit)

        previewer.get( handler: commentaryLoad)

    }
    func commentaryLoad(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        var commid: UInt?
        guard documentId != "undefined" else {throw Abort.custom(status: .badRequest, message: "document not specified")}
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {throw Abort.custom(status: .notFound, message: "document unknown")}
        var commentary: Commentary?
        var commentJWT: JWT?

        if let incookie = request.cookies[ConsultConstants.cookieComment] {
            commentJWT = try? JWT(token: incookie)
        }
        pubDrop.console.info("Headers \(request.headers)")
        if commentJWT != nil {
            do {
                try commentJWT!.verifySignature(using: jwtSigner)
                commid = commentJWT!.payload["commid"]?.uint
            } catch {
                            }
        }
        if  commid != nil {
            do {
                pubDrop.console.info("looking for \(commid!)")

                commentary = try Commentary.find(Node(commid!))
            } catch {
                throw Abort.custom(status: .internalServerError, message: "commentary lookup failure")
            }

        }
        var response: [String: Node] = [:]
        if commentary != nil {
            if documentdata?.id == commentary!.document {  //could have switched documents
                var results: [Node] = []
                if let cid = commentary?.id {
                    let comments = try Comment.query().filter("commentary_id", cid).all()
                    //make Json array of comments with Node bits
                    for comment in comments {
                        if let thisResult = comment.nodeForJSON() {
                            results.append(thisResult)
                        }
                    }
                }
                response["comments"] = Node(results)
                response["commentary"] = commentary!.nodeForJSON()
            } else {
                commentary = nil //will zap cookie
            }
        }
        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(response))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
        // cookie refresh if configuration specified
        if  let domname = pubDrop.config["app", "appdomain"]?.string {
            if commentary != nil {
                if commentJWT == nil {
                    commentJWT = try JWT(payload: Node.object(["commid": Node(commid!)]),
                                         signer: jwtSigner)
                }
                if let token = try commentJWT?.createToken() {
                    let myCookie = Cookie(name: ConsultConstants.cookieComment, value: token, expires: Date() + 7 * 24 * 3600, domain: domname, httpOnly: true)
                    resp.cookies.insert(myCookie)
                }
            } else {
                //need to kill the cookie for various reasons above
                let myCookie = Cookie(name: ConsultConstants.cookieComment, value: "", maxAge: 0, domain: domname, httpOnly: true)
                resp.cookies.insert(myCookie)
            }
        }
        return resp
    }

    func emailCommentary(_ request: Request, document: Document, commentary: Commentary, type: MailStyle) -> () {
        // You can also create attachment from raw data.
        guard let recipient = drop.config["mail", "mailto", "to"]?.string, !recipient.isEmpty else {return}
        var response: [String: Node] = [:]

        switch type {
        case .jsonbackup:  //send a raw json of the commentary as a disaster backup.
            var results: [Node] = []
            if let cid = commentary.id {
                if let comments = try? Comment.query().filter("commentary_id", cid).all() {
                    //make Json array of comments with Node bits
                    for comment in comments {
                        if let thisResult = comment.nodeForJSON() {
                            results.append(thisResult)
                        }
                    }
                }
            }
            response["comments"] = Node(results)
            response["commentary"] = commentary.nodeForJSON()
            let json = JSON(Node(response))

            let data = Data(bytes: try! json.serialize(prettyPrint: true))
            let mailjson = Attachment(
                data: data,
                mime: "application/json",
                name: "Commentary\(commentary.id?.int ?? 0).json",
                inline: false // Send as standalone attachment.
            )
            var mailtext: String = "Document: \(document.knownas ?? "")\n\nCommentary\nID: \(commentary.id?.int ?? 0)\n"
            mailtext   += "Name: \(commentary.name ?? "")\nOrganization: \(commentary.organization ?? "")\nEmail: \(commentary.email?.value ?? "")"
            let mail = Mail(
                text: mailtext,
                from: drop.config["mail", "mailto", "from"]?.string ?? "foo@example.com",
                to: recipient,
                cc: drop.config["mail", "mailto", "cc"]?.string,
                bcc: drop.config["mail", "mailto", "bcc"]?.string,
                subject: "\(document.knownas ?? "") - " + (drop.config["mail", "mailto", "subject"]?.string ?? "Submission copy"),
                attachments: [mailjson])

            hedwig.send(mail) { error in
                if error != nil {  self.pubDrop.console.info("email fail \(commentary)")}
            }
        default:
            return  //not implemented
        }

    }

    func commentarySubmit(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        guard let command = request.parameters["command"]?.string else {
            throw Abort.badRequest
        }
        var commid: UInt?
        guard documentId != "undefined" else {throw Abort.custom(status: .badRequest, message: "document not specified")}
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard documentdata != nil else {throw Abort.custom(status: .notFound, message: "document unknown")}
        var commentary: Commentary?
        var commentJWT: JWT?
        if let incookie = request.cookies[ConsultConstants.cookieComment] {
            commentJWT = try? JWT(token: incookie)
        }
        pubDrop.console.info("Headers \(request.headers)")
        let detectedLanguage = languageDetect(request)
        if command == "clear" {

            let resp = Response(status: .found)
            resp.headers["Location"] = documentdata?.publishedURL(languageStr: detectedLanguage)?.absoluteString ?? "/"

            //need to kill the cookie to do the clear
            if  let domname = pubDrop.config["app", "appdomain"]?.string {
                let myCookie = Cookie(name: ConsultConstants.cookieComment, value: "", maxAge: 0, domain: domname, httpOnly: true)
                resp.cookies.insert(myCookie)
            }
            return resp
        }
        if commentJWT != nil {
            do {
                try commentJWT!.verifySignature(using: jwtSigner)
                commid = commentJWT!.payload["commid"]?.uint
            } catch {
                            }
        }

        if commid != nil {
            do {
                pubDrop.console.info("looking for \(commid!)")

                commentary = try Commentary.find(Node(commid!))
//                pubDrop.console.info("found \(commentary!)")

            } catch {
                throw Abort.custom(status: .internalServerError, message: "commentary lookup failure")
            }

        }
        var stateOfCommentary: [String : NodeConvertible] = [ "document-id": documentId,
                                  "langeng": detectedLanguage == "eng" ? true : false,
                                 "langfra": detectedLanguage == "fra" ? true : false
        ]

        var responseDict: [String: Node] = [:]
        if commentary != nil {
            if (commentary!.email?.value ?? "").isEmpty {
                stateOfCommentary["emailoption"] = false
            } else {
                stateOfCommentary["emailoption"] = true
            }
            switch command {
                case "verify", "verifyemail":
                    if !(commentary!.submitted) { //prevent reversion from submit
                        commentary!.verification = command == "verify" ? false : true //true if email confirmations selected
                        commentary!.status = CommentaryStatus.attemptedsubmit //a special status to capture attempts that may not make it to full submit
                        if commentary!.submitReadiness() == CommentarySubmitStatus.ready {
                            commentary!.submitted = true
                            commentary!.submitteddate = Date()
                            commentary!.updateStatus(to: CommentaryStatus.submitted)
                            if let submittedalready = try? submitRender.make("submitconfirmation", stateOfCommentary) {
                                responseDict["overlayhtml"] = try? Node(submittedalready.data.string())
                            }
                            emailCommentary(request, document: documentdata!, commentary: commentary!, type: .jsonbackup)
                        } else {
                            if let submitverify = try? submitRender.make("submitrequest", stateOfCommentary) {
                                responseDict["overlayhtml"] = try? Node(submitverify.data.string())
                            }
                        }
                        try commentary!.save()

                    } else {
                        stateOfCommentary["startnewoption"] = true
                        if let submittedalready = try? submitRender.make("submittedalready", stateOfCommentary) {
                            responseDict["overlayhtml"] = try? Node(submittedalready.data.string())
                        }
                }
                case "new", "clear":
                    commentary = nil
                case "request":
                    fallthrough
                default:
                    if commentary!.submitted {
                        stateOfCommentary["startnewoption"] = true
                        if let submittedalready = try? submitRender.make("submittedalready", stateOfCommentary) {
                            responseDict["overlayhtml"] = try? Node(submittedalready.data.string())
                        }
                    } else {
                        switch commentary!.submitReadiness() {
                        case .some(CommentarySubmitStatus.missinginfo):
                            stateOfCommentary["missingselection"] = true
                        case .some(CommentarySubmitStatus.ready):
                            stateOfCommentary["ready"] = true
                        default:
                            break
                        }
                        if let submitverify = try? submitRender.make("submitrequest", stateOfCommentary) {
                            responseDict["overlayhtml"] = try? Node(submitverify.data.string())
                        }
                    }

            }
            responseDict["commentary"] = commentary!.nodeForJSON()
        }
        let headers: [HeaderKey: String] = [
            "Content-Type": "application/json; charset=utf-8"
        ]
        let json = JSON(Node(responseDict))
        let resp = Response(status: .ok, headers: headers, body: try Body(json))
        // cookie refresh if configuration specified
        if  let domname = pubDrop.config["app", "appdomain"]?.string {
            if commentary != nil {
                if commentJWT == nil {
                    commentJWT = try JWT(payload: Node.object(["commid": Node(commid!)]),
                                         signer: jwtSigner)
                }
                if let token = try commentJWT?.createToken() {
                    let myCookie = Cookie(name: ConsultConstants.cookieComment, value: token, expires: Date() + 7 * 24 * 3600, domain: domname, httpOnly: true)
                    resp.cookies.insert(myCookie)
                }
            } else {
                //need to kill the cookie for various reasons above
                let myCookie = Cookie(name: ConsultConstants.cookieComment, value: "", maxAge: 0, domain: domname, httpOnly: true)
                resp.cookies.insert(myCookie)
            }
        }
        return resp
    }

    func commentarySummary(_ request: Request)throws -> ResponseRepresentable {
        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }
        var commid: UInt?
        let idInt = base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        //TODO: document not found errors
        guard documentdata != nil else {return Response(redirect: "/")}
        var commentary: Commentary?
        var commentJWT: JWT?
        if let incookie = request.cookies[ConsultConstants.cookieComment] {
            commentJWT = try? JWT(token: incookie)
        }
        let detectedLanguage = languageDetect(request)
        guard commentJWT != nil else {return Response(redirect: documentdata?.publishedURL(languageStr: detectedLanguage)?.absoluteString ?? "/")}

        do {
            try commentJWT!.verifySignature(using: jwtSigner)
                commid = commentJWT!.payload["commid"]?.uint
        } catch {
            commentJWT = nil  //did not pass - new one will be started
        }

        if  commid != nil {
            do {
                pubDrop.console.info("looking for \(commid!)")
                commentary = try Commentary.find(Node(commid!))
            } catch {
                pubDrop.console.info("Did not find \(String(describing: commid))")
            }
        }

        guard commentary != nil else {return Response(redirect: documentdata?.publishedURL(languageStr: detectedLanguage)?.absoluteString ?? "/")}

        if documentdata?.id != commentary!.document {   //could have switched documents
            let resp = Response(status: .found)
            resp.headers["Location"] = documentdata?.publishedURL(languageStr: detectedLanguage)?.absoluteString ?? "/"

            //need to kill the cookie to do the clear
            if  let domname = pubDrop.config["app", "appdomain"]?.string {
                let myCookie = Cookie(name: ConsultConstants.cookieComment, value: "", maxAge: 0, domain: domname, httpOnly: true)
                resp.cookies.insert(myCookie)
            }
            return resp
        }
        return try buildCommentaryPreview(request, document: documentdata!, commentary: commentary!, type: .onlyComments)
    }

    func buildCommentaryPreview(_ request: Request, document: Document, commentary: Commentary, type: PreviewView)throws -> ResponseRepresentable {
        let filePackBaseDir = filePackDir + document.filepack!
        let filePack = filePackBaseDir + "/elements/"
        //TODO: need new document types in future
        let templatePack = templateDir + "proposedregulation/elements/"
        var filejson: [String: Any] = [:]
        var tagsA: [[String: Any]] = [[:]]
        var tags: [[String: Any]] = [[:]]
        //        let docRenderer = LeafRenderer(viewsDir: filePack)
        let tempRenderer = LeafRenderer(viewsDir: templatePack)
        //find page language from referrer
        var tagsDict: [String:[String: Any]] = [:]
        var fileJson: JSON = JSON(.null)
        //get data from disk/network
        if let data = fm.contents(atPath: filePackBaseDir + "/filepack.json") {
            fileJson = try! JSON(serialized: data.makeBytes())

            if let fj =  try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                filejson = fj!
                if let thetags = filejson["rias-tags"] as? [[String: Any]] {
                    // Finally we got the tags
                    tagsA = thetags
                }
                if let thetags = filejson["reg-tags"] as? [[String: Any]] {
                    // Finally we got the tags
                    tags = thetags
                    // need to unique the tags as they will need to be unique id elements in the html
                    //TODO: warn and clean step in preflight
//                    var tagset: Set<String> = []
//                    for (index, tag) in tags.enumerated() {
//                        var theref = tag["ref"] as? String
//                        if (theref ?? "").isEmpty {
//                            theref = "t-\(index)"
//                        }
//                        if tagset.contains(theref!) {
//                            theref = theref! + "-t-\(index)"
//                            guard !tagset.contains(theref!) else {
//                                return JSON(["prepare":"regulation","status":"failed"])
//                            }
//                        }
//                        tags[index]["ref"] = theref
//                        tagsDict["reg-" + theref!] = tags[index]
//                        tagset.insert(theref!)
//                    }
                }
            }
        }
        let pagePrefix = fileJson.node.nodeObject?["publishing-pageprefix"]?.string ?? "reg"
        var substitutions: [String:Node] = [:]

        let comments = try Comment.query().filter("commentary_id", commentary.id!).all()

        let lang = languageDetect(request) == "fra" ? ("fra", "line-fra", "line-eng", "fr-CA", "prompt-fra") : ("eng", "line-eng", "line-fra", "en-CA", "prompt-eng")

        var tempNode: [String: Node] = fileJson.node.nodeObject ?? [:]
        tempNode[lang.1] = Node(true) //use in template to select language
        tempNode["eng-page"] = Node(pagePrefix + "-eng.html")
        tempNode["fra-page"] = Node(pagePrefix + "-fra.html")
        tempNode["document-link"] = Node("/" + document.publishingpath!)
        if let langDict = tempNode[lang.3]?.nodeObject {
            for (item, nodeElement) in langDict {
                tempNode[item] = nodeElement

            }
        }
        tempNode["noformend"] = Node("noformend")

        let fnode = Node(tempNode)
        var outDocument = Data()

        if let meta = try? tempRenderer.make("commentpreviewbanner-" + lang.0, fnode) {
            outDocument.append(Data(meta.data))
        }
        if let meta = try? tempRenderer.make("summarylead-" + lang.0, fnode) {
            outDocument.append(Data(meta.data))
        }
        if let meta = try? tempRenderer.make("commentpreviewlistlead-" + lang.0, fnode) {
            outDocument.append(Data(meta.data))
        }
        switch type {
        case .fullText:
            // not tested yet
            if let section = fm.contents(atPath: filePack + "rias-" + lang.0 + ".html") {
                outDocument.append(section) }

            if let section = fm.contents(atPath: filePack + "reg-" + lang.0 + ".html") {
                if var dataString:[String] = String(data: section, encoding: String.Encoding.utf8)?.components(separatedBy: .newlines) {
                    substitutions["reftype"] = Node(String(describing: "reg"))

                    for comment in comments {
                        if let thisRef = comment.reference, let thisTag = tagsDict[thisRef] {
                            if let linenum = thisTag[lang.1] as? Int {
                                guard linenum <= dataString.count else {continue}
                                substitutions["ref"] = Node(thisTag["ref"] as! String) //tag["ref"] as? String
                                if let pmt = thisTag[lang.4] as? String {
                                    substitutions["prompt"] = Node(pmt) // as? String) // as? String
                                } else {
                                    substitutions["prompt"] = nil
                                }
                                if let txt = comment.text {
                                    substitutions["commenttext"] = Node(txt)
                                    let insertType = (thisTag["type"] as? String ?? "comment") + "preview-" + lang.0
                                    if let meta = try? tempRenderer.make(insertType, substitutions), let templstr = String(data: Data(meta.data), encoding: String.Encoding.utf8) {
                                        dataString[linenum - 1] = dataString[linenum - 1].appending(templstr)
                                    }
                                }
                            }
                        }
                    }

                    substitutions["ref"] = nil
                    substitutions["prompt"] = nil
                    substitutions["commenttext"] = nil
                    outDocument.append(dataString.joined(separator: "\n").data(using: .utf8)!)
                }
            }

        case .onlyComments:
            var commentDict: [String: Comment] = [:]
            for comment in comments {
                guard let cref = comment.reference else { continue}
                commentDict[cref] = comment
            }
            if let section = fm.contents(atPath: filePack + "rias-" + lang.0 + ".html") {
                if var dataString:[String] = String(data: section, encoding: String.Encoding.utf8)?.components(separatedBy: .newlines) {
                    var lastline: Int = 0

                    substitutions["reftype"] = Node(String(describing: "ris"))
                    for tag in tagsA {
                        if let linenum = tag[lang.1] as? Int {
                            guard linenum <= dataString.count else {continue}
                            substitutions["ref"] = Node(tag["ref"] as! String)
                            if let pmt = tag[lang.4] as? String {
                                substitutions["prompt"] = Node(pmt)
                            } else {
                                substitutions["prompt"] = nil
                            }
                            if let comm = commentDict["ris-" + (tag["ref"] as! String)], let txt = comm.text {
                                substitutions["emptycomment"] = false
                                substitutions["commenttext"] = Node(txt)

                            } else {
                                substitutions["emptycomment"] = true
                                substitutions["commenttext"] = nil
                            }
                            substitutions["lineid"] = Node(String(tag["line-eng"] as! Int))
                            let insertTypehead = (tag["type"] as? String ?? "comment") + "previewlisthead-" + lang.0
                            if let meta = try? tempRenderer.make(insertTypehead, substitutions), let templstr = String(data: Data(meta.data), encoding: String.Encoding.utf8) {
                                dataString[lastline] = templstr.appending(dataString[lastline])                            }
                            let insertType = (tag["type"] as? String ?? "comment") + "previewlist-" + lang.0
                            if let meta = try? tempRenderer.make(insertType, substitutions), let templstr = String(data: Data(meta.data), encoding: String.Encoding.utf8) {
                                dataString[linenum - 1] = dataString[linenum - 1].appending(templstr)
                            }
                            lastline = linenum

                        }
                    }
                    dataString.removeSubrange(lastline..<dataString.count)
                    substitutions["ref"] = nil
                    substitutions["prompt"] = nil
                    substitutions["commenttext"] = nil
                    outDocument.append(dataString.joined(separator: "\n").data(using: .utf8)!)
                }
            }
            if let section = fm.contents(atPath: filePack + "reg-" + lang.0 + ".html") {
                if var dataString:[String] = String(data: section, encoding: String.Encoding.utf8)?.components(separatedBy: .newlines) {
                    var lastline: Int = 0

                    substitutions["reftype"] = Node(String(describing: "reg"))
                    for tag in tags {
                        if let linenum = tag[lang.1] as? Int {
                            guard linenum <= dataString.count else {continue}
                            substitutions["ref"] = Node(tag["ref"] as! String) 
                            if let pmt = tag[lang.4] as? String {
                                substitutions["prompt"] = Node(pmt)
                            } else {
                                substitutions["prompt"] = nil
                            }
                            if let comm = commentDict["reg-" + (tag["ref"] as! String)], let txt = comm.text {
                                substitutions["emptycomment"] = false
                                substitutions["commenttext"] = Node(txt)

                            } else {
                                substitutions["emptycomment"] = true
                                substitutions["commenttext"] = nil
                            }
                            substitutions["lineid"] = Node(String(tag["line-eng"] as! Int))
                            let insertTypehead = (tag["type"] as? String ?? "comment") + "previewlisthead-" + lang.0
                            if let meta = try? tempRenderer.make(insertTypehead, substitutions), let templstr = String(data: Data(meta.data), encoding: String.Encoding.utf8) {
                                dataString[lastline] = templstr.appending(dataString[lastline])                            }
                            let insertType = (tag["type"] as? String ?? "comment") + "previewlist-" + lang.0
                            if let meta = try? tempRenderer.make(insertType, substitutions), let templstr = String(data: Data(meta.data), encoding: String.Encoding.utf8) {
                                dataString[linenum - 1] = dataString[linenum - 1].appending(templstr)
                            }
                            lastline = linenum

                        }
                    }
                    dataString.removeSubrange(lastline..<dataString.count)
                    substitutions["ref"] = nil
                    substitutions["prompt"] = nil
                    substitutions["commenttext"] = nil
                    outDocument.append(dataString.joined(separator: "\n").data(using: .utf8)!)
                }
            }

        } //switch
        if let meta = try? tempRenderer.make("commentpreviewlisttail-" + lang.0, fnode) {
            outDocument.append(Data(meta.data))
        }
        if let meta = try? tempRenderer.make("commentpreviewfoot-" + lang.0, fnode) {
            outDocument.append(Data(meta.data))
        }
        return View(data: [UInt8](outDocument))
    }

}

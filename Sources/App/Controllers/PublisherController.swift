import HTTP
import JWT
import JSON
import Vapor
import Auth
import Foundation


final class PublisherController {
    let pubDrop: Droplet
    let jwtSigner: Signer
    let templateDir: String
    let filePackDir: String
    let fm = FileManager()

    init(to drop: Droplet) {
        pubDrop = drop
        templateDir = drop.workDir + "TemplatePacks/"
        filePackDir = drop.workDir + "FilePacks/"
        jwtSigner = HS256(key: (drop.config["crypto", "jwtuser","secret"]?.string ?? "secret").bytes)
//        let protect = ProtectMiddleware(error:
//            Abort.custom(status: .forbidden, message: "Not authorized.")
//        )
        let prepare = drop.grouped("prepare")


        prepare.get { request in
            //TODO: list of docs
            return "document info"
        }
        prepare.post("publish",":id", handler: publishDocument)
        prepare.post("load",":filename", handler: loadDocument)
    }

    func getUserFromCookie(_ request: Request)throws -> User {
        var userJWT: JWT?
        do {
            if let incookie = request.cookies[ConsultConstants.cookieUser] {
                userJWT = try JWT(token: incookie)
            }
            if userJWT != nil {
                try userJWT!.verifySignature(using: jwtSigner)
                if let username = userJWT!.payload["user"]?.string {
                    if let user = try User.query().filter("username", username).first() {
                        return user
                    }
                }
            }
        }catch {

        }
        throw Abort.custom(status: .forbidden, message:  "Not authorized.")
    }

    func loadDocument(_ request: Request)throws -> ResponseRepresentable {
        let user = try getUserFromCookie(request)
        guard user.admin else {
            throw Abort.custom(status: .forbidden, message:  "Not authorized.")
        }
        guard let documentId = request.parameters["filename"]?.string else {
            throw Abort.badRequest
        }
        guard let data = fm.contents(atPath: filePackDir + documentId + "/filepack.json") else {
            throw Abort.custom(status: .notFound, message: "filepack.json not found.")

        }
        do  {
            let fileJson = try JSON(serialized: data.makeBytes())
            var adict: [String: Node] = [Document.Constants.id: Base62ToNode(string: fileJson["document-id"]?.string)]
            if let check = fileJson["known-as"], let checkstr = check.string { adict[Document.Constants.knownas] = Node(checkstr)}
            adict[Document.Constants.filepack] = Node(documentId)
            if let check = fileJson["publishing-ref"], let checkstr = check.string { adict[Document.Constants.publishingref] = Node(checkstr)}
            if let check = fileJson["publishing-date"], let checkstr = check.string { adict[Document.Constants.publishingdate] = Node(checkstr)}
            if let check = fileJson["publishing-folder-path"], let checkstr = check.string { adict[Document.Constants.publishingpath] = Node(checkstr)}
            if let check = fileJson["publishing-pageprefix"], let checkstr = check.string { adict[Document.Constants.publishingpageprefix] = Node(checkstr)}

            adict[Document.Constants.archived] = Node(fileJson["archived"]?.bool ?? false)

            var newDoc = try Document(node: adict, in: [])
            try newDoc.save()

            return JSON(["prepare":"regulation","status":"published"])
        } catch {
            throw Abort.custom(status: .notAcceptable, message: "filepack.json faulty.")
        }
    }
    func publishDocument(_ request: Request)throws -> ResponseRepresentable {
//        let user = try getUserFromCookie(request)
//        guard user.admin else {
//            throw Abort.custom(status: .forbidden, message:  "Not authorized.")
//        }

        guard let documentId = request.parameters["id"]?.string else {
            throw Abort.badRequest
        }

        //locate document
        let idInt = Base62ToID(string: documentId)
        let documentdata = try Document.find(Node(idInt))
        guard let document = documentdata else {throw Abort.custom(status: .notFound, message: "document unknown")}
        
        let filePackBaseDir = filePackDir + document.filepack!
        let filePack = filePackBaseDir + "/elements/"
        //TODO: need new document types in future
        let templatePack = templateDir + "proposedregulation/elements/"

        var filejson: [String: Any] = [:]
        var tags: [[String: Any]] = [[:]]
        let tempRenderer = LeafRenderer(viewsDir: templatePack)

        var fileJson: JSON = JSON(.null)
        //get data from disk/network
        if let data = fm.contents(atPath: filePackBaseDir + "/filepack.json") {
            fileJson = try! JSON(serialized: data.makeBytes())

            if let fj =  try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                filejson = fj!
                if let thetags = filejson["reg-tags"] as? [[String: Any]] {
                    // Finally we got the tags
                    tags = thetags
                    // need to unique the tags as they will need to be unique id elements in the html
                    //TODO: warn and clean step in preflight
                    var tagset: Set<String> = []
                    for (index, tag) in tags.enumerated() {
                        var theref = tag["ref"] as? String
                        if (theref ?? "").isEmpty {
                            theref = "t-\(index)"
                        }
                        if tagset.contains(theref!) {
                            theref = theref! + "-t-\(index)"
                            guard !tagset.contains(theref!) else {
                                throw Abort.custom(status: .conflict, message: "duplicate reference tags")
                            }
                        }
                        tags[index]["ref"] = theref
                        tagset.insert(theref!)
                    }
                }
            }
        }
        guard let pagePrefix = document.publishingpageprefix  else {throw Abort.custom(status: .expectationFailed, message: "document publishing name missing")}
        var substitutions: [String:Node] = [:]
        


        //cycle over 2 languages for now; handy tuples for loop language variation
        for lang in [("eng","line-eng","line-fra","en-CA","prompt-eng"),
        ("fra","line-fra","line-eng","fr-CA","prompt-fra")] {

            var tempNode: [String: Node] = fileJson.node.nodeObject ?? [:]
            tempNode[lang.0] = Node(true) //use in template to select language
            tempNode["eng-page"] = Node(pagePrefix + "-eng.html")
            tempNode["fra-page"] = Node(pagePrefix + "-fra.html")
            if let langDict = tempNode[lang.3]?.nodeObject {
                for (item, nodeElement) in langDict {
                    tempNode[item] = nodeElement

                }
            }
            let fnode = Node(tempNode)
            var outDocument = Data()

            if let meta = try? tempRenderer.make("top-" + lang.0, fnode) {
                outDocument.append(Data(meta.data))
            }
            if let meta = try? tempRenderer.make("metadata-" + lang.0, fnode) {
                outDocument.append(Data(meta.data))
            }
            if let meta = try? tempRenderer.make("lead-" + lang.0, fnode) {
                outDocument.append(Data(meta.data))
            }
            if let meta = try? tempRenderer.make("mainlead-" + lang.0, fnode) {
                outDocument.append(Data(meta.data))
            }
            if let section = fm.contents(atPath: filePack + "contenthead-" + lang.0 + ".html") {
                outDocument.append(section) }
            if let meta = try? tempRenderer.make("leadcontrols-" + lang.0, fnode) {
                outDocument.append(Data(meta.data))
            }
            if let section = fm.contents(atPath: filePack + "rias-" + lang.0 + ".html") {
                outDocument.append(section) }
            if let meta = try? tempRenderer.make("reglead-" + lang.0, fnode) {
                outDocument.append(Data(meta.data))
            }
            if let section = fm.contents(atPath: filePack + "reg-" + lang.0 + ".html") {
                if var dataString:[String] = String(data: section, encoding: String.Encoding.utf8)?.components(separatedBy: .newlines) {
                    substitutions["reftype"] = Node(String(describing: "reg"))
                    for tag in tags {
                        if let linenum = tag[lang.1] as? Int{
                            guard linenum <= dataString.count else {continue}
                            substitutions["ref"] = Node(tag["ref"] as! String) //tag["ref"] as? String
                            if let pmt = tag[lang.4] as? String {
                                substitutions["prompt"] = Node(pmt) // as? String) // as? String
                            } else {
                                substitutions["prompt"] = nil
                            }
                            substitutions["lineid"] = Node(String(tag["line-eng"] as! Int))
                            let insertType = (tag["type"] as? String ?? "comment") + "-" + lang.0
                            if let meta = try? tempRenderer.make(insertType, substitutions), let templstr = String(data: Data(meta.data), encoding: String.Encoding.utf8) {
                                dataString[linenum - 1] = dataString[linenum - 1].appending(templstr)
                            }

                        }
                    }
                    substitutions["ref"] = nil
                    substitutions["prompt"] = nil
                    outDocument.append(dataString.joined(separator: "\n").data(using: .utf8)!)
                }
            }
            if let meta = try? tempRenderer.make("formsubmit-" + lang.0, fnode) {
                outDocument.append(Data(meta.data))
            }
            if let meta = try? tempRenderer.make("bottom-" + lang.0, fnode) {
                outDocument.append(Data(meta.data))
            }
            do {
                guard let docpath = document.publishingpath  else {throw Abort.custom(status: .expectationFailed, message: "document publishing path missing")}
                let  dirPath = pubDrop.workDir + "Public/" + docpath
                try fm.createDirectory(atPath: dirPath , withIntermediateDirectories: true, attributes: nil)
                let filePath = dirPath + pagePrefix + "-" + lang.0 + ".html"
                do{
                    try fm.removeItem(atPath: filePath)
                } catch {
                    
                }
                fm.createFile(atPath: filePath, contents: outDocument, attributes: nil)
                
            } catch{
                throw Abort.custom(status: .methodNotAllowed, message: "failure saving published documants")
            }
        }
        return JSON(["prepare":"regulation","status":"published"])
    }

    
}

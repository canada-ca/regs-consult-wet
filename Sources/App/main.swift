import Vapor
import VaporMySQL
import Sessions
import JWT
import LeafMarkdown

let drop = Droplet()

let jwtUserSigner: Signer = HS256(key: (drop.config["crypto", "jwtuser", "secret"]?.string ?? "secret").bytes)

drop.middleware.append(CorsMiddleware())

try drop.addProvider(VaporMySQL.Provider.self)
//let uac = UACompatibleMiddleware()
//drop.middleware.append(uac)  // added instead to nginx server config: add_header "X-UA-Compatible" "IE=Edge";
try drop.addProvider(LeafMarkdown.Provider.self)

drop.preparations.append(User.self)
drop.preparations.append(Document.self)
drop.preparations.append(Commentary.self)
drop.preparations.append(Comment.self)
drop.preparations.append(Note.self)

let cookieSetter = AuthMiddlewareJWT(for: drop, jwtSigner: jwtUserSigner)
let protect = RedirectAuthMiddlewareJWT(for: drop, jwtSigner: jwtUserSigner)

let adminController = AdminController(to: drop, cookieSetter: cookieSetter, protect: protect)
let pubController = PublisherController(to: drop, cookieSetter: cookieSetter, protect: protect)

let receiveController = ReceiveController(to: drop, cookieSetter: cookieSetter, protect: protect)
let analyzeController = AnalyzeController(to: drop, cookieSetter: cookieSetter, protect: protect)
let reviewController = ReviewController(to: drop, cookieSetter: cookieSetter, protect: protect)

let commentController = CommentsController(to: drop)

let commentaryController = CommentaryController(to: drop)

//TODO: show last edited document?
drop.get { _ in
    return try drop.view.make("splashpage.html")
}

drop.run()

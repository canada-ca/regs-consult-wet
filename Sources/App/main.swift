import Vapor
import VaporMySQL
//import Auth
import Sessions
import JWT

let drop = Droplet()

let jwtUserSigner: Signer = HS256(key: (drop.config["crypto", "jwtuser","secret"]?.string ?? "secret").bytes)

drop.middleware.append(CorsMiddleware())

try drop.addProvider(VaporMySQL.Provider.self)
//let auth = AuthMiddleware(user: User.self)
//drop.middleware.append(auth)

drop.preparations.append(User.self)
drop.preparations.append(Document.self)
drop.preparations.append(Commentary.self)
drop.preparations.append(Comment.self)
let cookieSetter = AuthMiddlewareJWT(for: drop, jwtSigner: jwtUserSigner)
let protect = RedirectAuthMiddlewareJWT(for: drop, jwtSigner: jwtUserSigner)

let adminController = AdminController(to: drop, cookieSetter: cookieSetter, protect: protect)
let pubController = PublisherController(to: drop, cookieSetter: cookieSetter, protect: protect)

let receiveController = ReceiveController(to: drop, cookieSetter: cookieSetter, protect: protect)


//let loginController = LoginController(to: drop)


let commentController = CommentsController(to: drop)

let commentaryController = CommentaryController(to: drop)

//let receiveController = ReceiveController(to: drop)
//let analyzeController = AnalyzeController(to: drop)

//TODO: show last edited document?
drop.get { req in
    return try drop.view.make("splashpage.html")
}

drop.run()

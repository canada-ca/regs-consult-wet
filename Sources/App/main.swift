import Vapor
import VaporMySQL
import Auth
import Sessions


let drop = Droplet()
drop.middleware.append(CorsMiddleware())

try drop.addProvider(VaporMySQL.Provider.self)
let auth = AuthMiddleware(user: User.self)
drop.middleware.append(auth)


drop.preparations.append(User.self)
drop.preparations.append(Document.self)
drop.preparations.append(Commentary.self)
drop.preparations.append(Comment.self)


let loginController = LoginController(to: drop)

let pubController = PublisherController(to: drop)

let commentController = CommentsController(to: drop)

let commentaryController = CommentaryController(to: drop)

let receiveController = ReceiveController(to: drop)
let analyzeController = AnalyzeController(to: drop)

//TODO: show last edited document?
drop.get { req in
    return try drop.view.make("splashpage.html")
}


drop.run()

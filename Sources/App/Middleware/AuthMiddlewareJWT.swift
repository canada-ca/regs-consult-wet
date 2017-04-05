//import Turnstile
import HTTP
import Cookies
import Foundation
//import Cache
//import Auth
import Vapor
import JWT

private let cookieTime: TimeInterval = 7 * 24 * 60 * 60 // 7 days

public class AuthMiddlewareJWT: Middleware {
    var jwtSigner: Signer
    let authDomainName: String
    let domname: String

    public init(for drop: Droplet, jwtSigner: Signer) {
        self.jwtSigner = jwtSigner
        authDomainName = drop.config["crypto", "jwtuser","authuserdomain"]?.string ?? "domain"
        domname = drop.config["app", "appdomain"]?.string  ?? "example.com"
    }

    public func respond(to request: Request, chainingTo next: Responder) throws -> Response {

        let response = try next.respond(to: request)
        if request.storage["resetcookie"] != nil {
                let myCookie = Cookie(name: ConsultConstants.cookieUser, value: "", maxAge: 0, domain: domname, httpOnly: true)
                response.cookies.insert(myCookie)
        }
        if let usr = request.storage["setcookie"] as? User {
            if let commentJWT = try? JWT(payload: Node.object(["userid": usr.id!,
                                                               "domain": Node(authDomainName)]),
                                         signer: jwtSigner) {
                let token = try commentJWT.createToken()
                let myCookie = Cookie(name: ConsultConstants.cookieUser,value: token, expires: Date().addingTimeInterval(cookieTime), domain: domname, httpOnly: true)
                response.cookies.insert(myCookie)
            }
        }

        return response
    }
}

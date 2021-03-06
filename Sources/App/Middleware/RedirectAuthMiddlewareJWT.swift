import HTTP
import Vapor
import Cookies
import JWT

public class RedirectAuthMiddlewareJWT: Middleware {

    var jwtSigner: Signer
    let authDomainName: String
    init(for drop: Droplet, jwtSigner: Signer) {
        self.jwtSigner = jwtSigner
        authDomainName = drop.config["crypto", "jwtuser", "authuserdomain"]?.string ?? "domain"
    }
    public func respond(to request: Request, chainingTo next: Responder) throws -> Response {
        if let cookieUser = request.cookies[ConsultConstants.cookieUser] {
            request.storage["resetcookie"] = true
            if let inboundJWT = try? JWT(token: cookieUser) {
                do {
                    try inboundJWT.verifySignature(using: jwtSigner)
                } catch {
                    return Response(redirect: "/admin/login?loginRequired")
                }
                if inboundJWT.payload["domain"]?.string != authDomainName {
                    return Response(redirect: "/admin/login?loginRequired")
                }
                if let userID = inboundJWT.payload["userid"]?.uint {
                    if let userincookie = try User.find(Node(userID)) {
                        request.storage["resetcookie"] = nil //false equivalent
                        if userincookie.resetPasswordRequired && !request.uri.path.hasPrefix("/admin/resetPassword") {
                            return Response(redirect: "/admin/resetPassword")
                        }

                        request.storage["userid"] = userincookie
                        return try next.respond(to: request)
                    }
                }
            }
        }
        return Response(redirect: "/admin/login?loginRequired")
    }
}

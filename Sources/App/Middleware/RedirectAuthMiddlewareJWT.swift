import HTTP
import Vapor
import JWT

public class RedirectAuthMiddlewareJWT: Middleware {
    
    var jwtSigner: Signer
    let authDomainName: String
    init(for drop: Droplet, jwtSigner: Signer) {
        self.jwtSigner = jwtSigner
        authDomainName = drop.config["crypto", "jwtuser","authuserdomain"]?.string ?? "domain"
    }
    public func respond(to request: Request, chainingTo next: Responder) throws -> Response {
        
        guard let cookieValue = request.cookies[ConsultConstants.cookieUser] else {
            return Response(redirect: "/admin/login?loginRequired")
        }
        guard let inboundJWT = try? JWT(token: cookieValue)  else {
            request.storage["resetcookie"] = true
            return Response(redirect: "/admin/login?loginRequired")
        }
        do {
            try inboundJWT.verifySignature(using: jwtSigner)

            if inboundJWT.payload["domain"]?.string != authDomainName {
                request.storage["resetcookie"] = true
                return Response(redirect: "/admin/login?loginRequired")
            }
            if let userID = inboundJWT.payload["user"]?.uint {
                if let userincookie = try User.find(Node(userID)) {
                    if userincookie.resetPasswordRequired && request.uri.path != "/admin/resetPassword" {
                        return Response(redirect: "/admin/resetPassword")
                    }
                    request.storage["userid"] = userincookie
                    return try next.respond(to: request)
                }
            }
        } catch {
            request.storage["resetcookie"] = true
            return Response(redirect: "/admin/login?loginRequired")
        }
        request.storage["resetcookie"] = true
        return Response(redirect: "/admin/login?loginRequired")
    }
}

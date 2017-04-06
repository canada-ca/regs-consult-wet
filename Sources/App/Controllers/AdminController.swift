import Vapor
import URI
import HTTP
import Routing
import Auth
import Foundation
import JWT
import Fluent

struct AdminController {

    // MARK: - Properties
    fileprivate let drop: Droplet
    let jwtSigner: Signer

    // MARK: - Initialiser
    init(to drop: Droplet) {
        self.drop = drop
        jwtSigner = HS256(key: (drop.config["crypto", "jwtuser","secret"]?.string ?? "secret").bytes)


        let cookieSetter = AuthMiddlewareJWT(for: drop, jwtSigner: self.jwtSigner)
//        let routerLogin = router.grouped(cookieSetter)
        let routerLogin = drop.grouped("admin").grouped(cookieSetter)
        routerLogin.get("login", handler: loginHandler)
        routerLogin.post("login", handler: loginPostHandler)
        routerLogin.get("logout", handler: logoutHandler)

        let protect = RedirectAuthMiddlewareJWT(for: drop, jwtSigner: self.jwtSigner)
        let routerSecure = routerLogin.grouped(protect)
        routerSecure.get(handler: adminHandler)
        //        routerSecure.get("createPost", handler: createPostHandler)
        //        routerSecure.post("createPost", handler: createPostPostHandler)
        routerSecure.get("createUser", handler: createUserHandler)
        routerSecure.post("createUser", handler: createUserPostHandler)
        //        router.get("profile", handler: profileHandler)
        //        routerSecure.get("posts", BlogPost.self, "delete", handler: deletePostHandler)
        //        routerSecure.get("posts", BlogPost.self, "edit", handler: editPostHandler)
        //        routerSecure.post("posts", BlogPost.self, "edit", handler: editPostPostHandler)
        routerSecure.get("users", User.self, "edit", handler: editUserHandler)
        routerSecure.post("users", User.self, "edit", handler: editUserPostHandler)
        routerSecure.get("users", User.self, "delete", handler: deleteUserPostHandler)
        routerSecure.get("resetPassword", handler: resetPasswordHandler)
        routerSecure.post("resetPassword", handler: resetPasswordPostHandler)

    }

    // MARK: - User handlers
    func createUserHandler(_ request: Request) throws -> ResponseRepresentable {
        return try createUserView(editing: false, errors: nil, name: nil, username: nil, passwordError: nil, confirmPasswordError: nil, resetPasswordRequired: nil, userId: nil)
    }

    func createUserPostHandler(_ request: Request) throws -> ResponseRepresentable {

        let rawName = request.data["inputName"]?.string
        let rawUsername = request.data["inputUsername"]?.string
        let rawPassword = request.data["inputPassword"]?.string
        let rawConfirmPassword = request.data["inputConfirmPassword"]?.string
        let rawPasswordResetRequired = request.data["inputResetPasswordOnLogin"]?.string
        let resetPasswordRequired = rawPasswordResetRequired != nil

        let (createUserRawErrors, passwordRawError, confirmPasswordRawError) = validateUserSaveDataExists(edit: false, name: rawName, username: rawUsername, password: rawPassword, confirmPassword: rawConfirmPassword)

        // Return if we have any missing fields
        if (createUserRawErrors?.count)! > 0 {
            return try createUserView(editing: false, errors: createUserRawErrors, name: rawName, username: rawUsername, passwordError: passwordRawError, confirmPasswordError: confirmPasswordRawError, resetPasswordRequired: resetPasswordRequired, userId: nil)
        }

        guard let name = rawName, let username = rawUsername?.lowercased(), let password = rawPassword, let confirmPassword = rawConfirmPassword else {
            throw Abort.badRequest
        }

        let (createUserErrors, passwordError, confirmPasswordError) = validateUserSaveData(edit: false, name: name, username: username, password: password, confirmPassword: confirmPassword)

        if (createUserErrors?.count)! > 0 {
            return try createUserView(editing: false, errors: createUserErrors, name: name, username: username, passwordError: passwordError, confirmPasswordError: confirmPasswordError, resetPasswordRequired: resetPasswordRequired,userId: nil)
        }

        // We now have valid data
        let creds = UserCredentials(username: username.lowercased(), password: password, name: name)
        if var user = try User.register(credentials: creds) as? User {
            if resetPasswordRequired {
                user.resetPasswordRequired = true
            }
            try user.save()
            return Response(redirect: "/admin")
        }
        else {
            return try createUserView(editing: false, errors: ["There was an error creating the user. Please try again"], name: name, username: username, passwordError: passwordError, confirmPasswordError: confirmPasswordError, resetPasswordRequired: resetPasswordRequired, userId: nil)
        }
    }

    func editUserHandler(request: Request, user: User) throws -> ResponseRepresentable {
        return try createUserView(editing: true, errors: nil, name: user.name, username: user.username, passwordError: nil, confirmPasswordError: nil, resetPasswordRequired: nil, userId: user.id)
    }

    func editUserPostHandler(request: Request, user: User) throws -> ResponseRepresentable {
        let rawName = request.data["inputName"]?.string
        let rawUsername = request.data["inputUsername"]?.string
        let rawPassword = request.data["inputPassword"]?.string
        let rawConfirmPassword = request.data["inputConfirmPassword"]?.string
        let rawPasswordResetRequired = request.data["inputResetPasswordOnLogin"]?.string
        let resetPasswordRequired = rawPasswordResetRequired != nil

        let (saveUserRawErrors, passwordRawError, confirmPasswordRawError) = validateUserSaveDataExists(edit: true, name: rawName, username: rawUsername, password: rawPassword, confirmPassword: rawConfirmPassword)

        // Return if we have any missing fields
        if (saveUserRawErrors?.count)! > 0 {
            return try createUserView(editing: true, errors: saveUserRawErrors, name: rawName, username: rawUsername, passwordError: passwordRawError, confirmPasswordError: confirmPasswordRawError, resetPasswordRequired: resetPasswordRequired, userId: user.id)
        }

        guard let name = rawName, let username = rawUsername else {
            throw Abort.badRequest
        }

        let (saveUserErrors, passwordError, confirmPasswordError) = validateUserSaveData(edit: true, name: name, username: username, password: rawPassword, confirmPassword: rawConfirmPassword, previousUsername: user.username)

        if (saveUserErrors?.count)! > 0 {
            return try createUserView(editing: true, errors: saveUserErrors, name: name, username: username, passwordError: passwordError, confirmPasswordError: confirmPasswordError, resetPasswordRequired: resetPasswordRequired, userId: user.id)
        }

        // We now have valid data
        guard let userId = user.id, var userToUpdate = try User.query().filter("id", userId).first() else {
            throw Abort.badRequest
        }
        userToUpdate.name = name
        userToUpdate.username = username

        if resetPasswordRequired {
            userToUpdate.resetPasswordRequired = true
        }

        if let password = rawPassword {
            let newCreds = UserCredentials(username: username, password: password, name: name)
            let newUserPassword = try User(credentials: newCreds)
            userToUpdate.password = newUserPassword.password
        }

        try userToUpdate.save()
        return Response(redirect: "/admin")
    }

    func deleteUserPostHandler(request: Request, user: User) throws -> ResponseRepresentable {
        guard let currentUser = request.storage["userid"] as? User else {
            throw Abort.badRequest
        }

        if user.admin  {
            return try createAdminView(errors: ["You cannot delete admin users"])
        }
            // Make sure we aren't deleting ourselves!
        else if currentUser.id == user.id {
            return try createAdminView(errors: ["You cannot delete yourself whilst logged in"])
        }
        else {
            try user.delete()
            return Response(redirect: "admin")
        }
    }
    func createAdminView(errors: [String]? = nil) throws -> View {
//        let publishedBlogPosts = try BlogPost.query().filter("published", true).sort("created", .descending).all()
//        let draftBlogPosts = try BlogPost.query().filter("published", false).sort("created", .descending).all()
        let users = try User.all()

//        var parameters = try Node(node: [
//            "users": users.makeNode()
//            ])
        var parameters = try Node(node: [
            "adminPage": Node(true)
            ])
//        parameters["users"] =  Node(users.map{try! $0.makeNode()})
parameters["users"] = try users.makeNode(context: EmptyNode)
//        if publishedBlogPosts.count > 0 {
//            parameters["published_posts"] = try publishedBlogPosts.makeNode(context: BlogPostContext.all)
//        }
//
//        if draftBlogPosts.count > 0 {
//            parameters["draft_posts"] = try draftBlogPosts.makeNode(context: BlogPostContext.all)
//        }

        if let errors = errors {
            parameters["errors"] = try errors.makeNode()
        }

//        parameters["adminPage"] = true

        return try drop.view.make("role/admin/index", parameters)
    }

    func createUserView(editing: Bool = false, errors: [String]? = nil, name: String? = nil, username: String? = nil, passwordError: Bool? = nil, confirmPasswordError: Bool? = nil, resetPasswordRequired: Bool? = nil, userId: Vapor.Node? = nil) throws -> View {
        let nameError = name == nil && errors != nil
        let usernameError = username == nil && errors != nil

        var parameters = [
            "name_error": nameError.makeNode(),
            "username_error": usernameError.makeNode(),
            ]

        if let createUserErrors = errors {
            parameters["errors"] = try createUserErrors.makeNode()
        }

        if let nameSupplied = name {
            parameters["name_supplied"] = nameSupplied.makeNode()
        }

        if let usernameSupplied = username {
            parameters["username_supplied"] = usernameSupplied.makeNode()
        }

        if let passwordError = passwordError {
            parameters["password_error"] = passwordError.makeNode()
        }

        if let confirmPasswordError = confirmPasswordError {
            parameters["confirm_password_error"] = confirmPasswordError.makeNode()
        }

        if let _ = resetPasswordRequired {
            parameters["reset_password_on_login_supplied"] = true
        }

        if editing {
            parameters["editing"] = true
            guard let userId = userId else {
                throw Abort.badRequest
            }
            parameters["user_id"] = userId
        }

        return try drop.view.make("role/admin/createUser", parameters)
    }

    // MARK: - Login Handlers
    func loginHandler(_ request: Request) throws -> ResponseRepresentable {
        // See if we need to create an admin user on first login
        do {
            let adminName = drop.config["crypto", "adminuser", "user"]?.string ?? "admin"
            let users = try User.query().filter("username", adminName).all()
            if users.count == 0 {
                let password = String.random()
                let creds = UserCredentials(username: adminName, password: password, name: "Admin")
                if var user = try User.register(credentials: creds) as? User {
                    user.resetPasswordRequired = true
                    user.admin = true
                    try user.save()
                    print("An Admin user been created for you - the username is \(adminName) and the password is \(password)")
                    print("You will be asked to change your password once you have logged in, please do this immediately!")
                }
            }
        }
        catch {
            print("There was an error creating a new admin user: \(error)")
        }
        
        let loginRequired = request.uri.rawQuery == "loginRequired"
        return try createLoginView(loginWarning: loginRequired, errors: nil, username: nil, password: nil)
    }
    
    func loginPostHandler(_ request: Request) throws -> ResponseRepresentable {
        
        let rawUsername = request.data["inputUsername"]?.string
        let rawPassword = request.data["inputPassword"]?.string
        let rememberMe = request.data["remember-me"]?.string != nil
        
        var loginErrors: [String] = []
        
        if rawUsername == nil {
            loginErrors.append("You must supply your username")
        }
        
        if rawPassword == nil {
            loginErrors.append("You must supply your password")
        }
        
        if loginErrors.count > 0 {
            return try createLoginView(loginWarning: false, errors: loginErrors, username: rawUsername, password: rawPassword)
        }
        
        guard let username = rawUsername, let password = rawPassword else {
            throw Abort.badRequest
        }
        
        let credentials = UserCredentials(username: username.lowercased(), password: password)
        
        if rememberMe {
            request.storage["remember_me"] = true
        }
        else {
            request.storage.removeValue(forKey: "remember_me")
        }
        
        do {
            guard let usr = try User.authenticate(credentials: credentials)as? User else {
                throw Abort.badRequest
            }
            request.storage["setcookie"] = usr
            return Response(redirect: "/admin")
        }
        catch {
            print("Got error logging in \(error)")
            let loginError = ["Your username or password was incorrect"]
            
            return try createLoginView(loginWarning: false, errors: loginError, username: username, password: "")
        }
    }

    func logoutHandler(_ request: Request) throws -> ResponseRepresentable {
        request.storage["resetcookie"] = true
        return Response(redirect: "admin")
    }
    func createLoginView(loginWarning: Bool = false, errors: [String]? = nil, username: String? = nil, password: String? = nil) throws -> View {
        let usernameError = username == nil && errors != nil
        let passwordError = password == nil && errors != nil

        var parameters = [
            "usernameError": usernameError.makeNode(),
            "passwordError": passwordError.makeNode()
        ]

        if let usernameSupplied = username {
            parameters["usernameSupplied"] = usernameSupplied.makeNode()
        }

        if let loginErrors = errors {
            parameters["errors"] = try loginErrors.makeNode()
        }

        if loginWarning {
            parameters["loginWarning"] = true
        }

        return try drop.view.make("role/admin/login", parameters)
    }

    // MARK: Admin Handler
    func adminHandler(_ request: Request) throws -> ResponseRepresentable {
        return try createAdminView(errors: nil)
    }

    // MARK: - Profile Handler
//    func profileHandler(_ request: Request) throws -> ResponseRepresentable {
//
//        guard let user = try request.auth.user() as? User else {
//            throw Abort.badRequest
//        }
//
//        return try createProfileView(uri: request.uri, author: user, isMyProfile: true, posts: try user.posts(), loggedInUser: user, disqusName: nil, siteTwitterHandle: nil)
//    }
//    func createProfileView(uri: URI, author: User, isMyProfile: Bool, posts: [BlogPost], loggedInUser: User?, disqusName: String?, siteTwitterHandle: String?) throws -> View {
//        func createProfileView(uri: URI, author: User, isMyProfile: Bool, posts: [], loggedInUser: User?, disqusName: String?, siteTwitterHandle: String?) throws -> View {
//
//        var parameters: [String: Vapor.Node] = [
//            "author": try author.makeNode(),
//            ]
//
//        if isMyProfile {
//            parameters["myProfile"] = true.makeNode()
//        }
//        else {
//            parameters["profilePage"] = true.makeNode()
//        }
//
//        if posts.count > 0 {
//            parameters["posts"] = []  //try posts.makeNode(context: BlogPostContext.shortSnippet)
//        }
//
//        return try createPublicView(template: "blog/profile", uri: uri, parameters: parameters, user: loggedInUser, disqusName: disqusName, siteTwitterHandle: siteTwitterHandle)
//    }

    // MARK: - Password handlers
    func resetPasswordHandler(_ request: Request) throws -> ResponseRepresentable {
        return try createResetPasswordView(errors: nil, passwordError: nil, confirmPasswordError: nil)
    }

    func resetPasswordPostHandler(_ request: Request) throws -> ResponseRepresentable {
        let rawPassword = request.data["inputPassword"]?.string
        let rawConfirmPassword = request.data["inputConfirmPassword"]?.string
        var resetPasswordErrors: [String] = []
        var passwordError: Bool?
        var confirmPasswordError: Bool?

        if rawPassword == nil {
            resetPasswordErrors.append("You must specify a password")
            passwordError = true
        }

        if rawConfirmPassword == nil {
            resetPasswordErrors.append("You must confirm your password")
            confirmPasswordError = true
        }

        // Return if we have any missing fields
        if resetPasswordErrors.count > 0 {
            return try createResetPasswordView(errors: resetPasswordErrors, passwordError: passwordError, confirmPasswordError: confirmPasswordError)
        }

        guard let password = rawPassword, let confirmPassword = rawConfirmPassword else {
            throw Abort.badRequest
        }

        if password != confirmPassword {
            resetPasswordErrors.append("Your passwords must match!")
            passwordError = true
            confirmPasswordError = true
        }

        // Check password is valid
        let validPassword = password.passes(PasswordValidator.self)
        if !validPassword {
            resetPasswordErrors.append("Your password must contain a lowercase letter, an upperacase letter, a number and a symbol")
            passwordError = true
        }

        if resetPasswordErrors.count > 0 {
            return try createResetPasswordView(errors: resetPasswordErrors, passwordError: passwordError, confirmPasswordError: confirmPasswordError)
        }

        guard var user = request.storage["userid"] as? User else {
            throw Abort.badRequest
        }

        // Use the credentials class to hash the password
        let newCreds = UserCredentials(username: user.username, password: password, name: user.name)
        let updatedUser = try User(credentials: newCreds)
        user.password = updatedUser.password
        user.resetPasswordRequired = false
        try user.save()

        return Response(redirect: "/admin")
    }
    func createResetPasswordView(errors: [String]? = nil, passwordError: Bool? = nil, confirmPasswordError: Bool? = nil) throws -> View {

        var parameters: [String: Vapor.Node] = [:]

        if let resetPasswordErrors = errors {
            parameters["errors"] = try resetPasswordErrors.makeNode()
        }

        if let passwordError = passwordError {
            parameters["passwordError"] = passwordError.makeNode()
        }

        if let confirmPasswordError = confirmPasswordError {
            parameters["confirmPasswordError"] = confirmPasswordError.makeNode()
        }

        return try drop.view.make("role/admin/resetPassword", parameters)
    }
    // MARK: - Validators
    private func validatePostCreation(title: String?, contents: String?, slugUrl: String?) -> [String]? {
        var createPostErrors: [String] = []

        if title == nil || (title?.isWhitespace())! {
            createPostErrors.append("You must specify a blog post title")
        }

        if contents == nil || (contents?.isWhitespace())! {
            createPostErrors.append("You must have some content in your blog post")
        }

        if (slugUrl == nil || (slugUrl?.isWhitespace())!) && (!(title == nil || (title?.isWhitespace())!)) {
            // The user can't manually edit this so if the title wasn't empty, we should never hit here
            createPostErrors.append("There was an error with your request, please try again")
        }

        if createPostErrors.count == 0 {
            return nil
        }

        return createPostErrors
    }

    private func validateUserSaveDataExists(edit: Bool, name: String?, username: String?, password: String?, confirmPassword: String?) -> ([String]?, Bool?, Bool?) {
        var userSaveErrors: [String] = []
        var passwordError: Bool?
        var confirmPasswordError: Bool?

        if name == nil || (name?.isWhitespace())! {
            userSaveErrors.append("You must specify a name")
        }

        if username == nil || (username?.isWhitespace())! {
            userSaveErrors.append("You must specify a username")
        }

        if !edit {
            if password == nil {
                userSaveErrors.append("You must specify a password")
                passwordError = true
            }

            if confirmPassword == nil {
                userSaveErrors.append("You must confirm your password")
                confirmPasswordError = true
            }
        }

        return (userSaveErrors, passwordError, confirmPasswordError)
    }

    private func validateUserSaveData(edit: Bool, name: String, username: String, password: String?, confirmPassword: String?, previousUsername: String? = nil) -> ([String]?, Bool?, Bool?) {

        var userSaveErrors: [String] = []
        var passwordError: Bool?
        var confirmPasswordError: Bool?

        if password != confirmPassword {
            userSaveErrors.append("Your passwords must match!")
            passwordError = true
            confirmPasswordError = true
        }

        // Check name is valid
        let validName = name.passes(NameValidator.self)
        if !validName {
            userSaveErrors.append("The name provided is not valid")
        }

        // Check username is valid
        let validUsername = username.passes(UsernameValidator.self)
        if !validUsername {
            userSaveErrors.append("The username provided is not valid")
        }

        // Check password is valid
        if !edit || password != nil {
            guard let actualPassword = password else {
                fatalError()
            }
            let validPassword = actualPassword.passes(PasswordValidator.self)
            if !validPassword {
                userSaveErrors.append("Your password must contain a lowercase letter, an upperacase letter, a number and a symbol")
                passwordError = true
            }
        }

        // Check username unique
        do {
            if username != previousUsername {
                let usernames = try User.all().map { $0.username.lowercased() }
                if usernames.contains(username.lowercased()) {
                    userSaveErrors.append("Sorry that username has already been taken")
                }
            }
        }
        catch {
            userSaveErrors.append("Unable to validate username")
        }

        return (userSaveErrors, passwordError, confirmPasswordError)
    }

}

// MARK: - Extensions
extension String {

    // TODO Could probably improve this
    static func random(length: Int = 8) -> String {
        let base = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        var randomString: String = ""

        for _ in 0..<length {
            let randomValue = Int.random(min: 0, max: base.characters.count-1)
            randomString += "\(base[base.index(base.startIndex, offsetBy: Int(randomValue))])"
        }
        return randomString
    }

    func isWhitespace() -> Bool {
        let whitespaceSet = CharacterSet.whitespacesAndNewlines
        if isEmpty || self.trimmingCharacters(in: whitespaceSet).isEmpty {
            return true
        }
        else {
            return false
        }
    }
}

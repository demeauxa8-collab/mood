import Observation
import Foundation
#if os(iOS)
import SwiftUI
import PhotosUI
#endif

enum OnboardingStep: String, CaseIterable, Codable, Identifiable {
    case welcome
    case email
    case account
    case confirmation
    case displayName
    case username
    case trust
    case server
    case notifications
    case friends
    case avatar
    case signIn

    var id: String { rawValue }
}

enum OnboardingTemplate: String, CaseIterable, Codable, Identifiable {
    case friends = "Amis"
    case games = "Jeux"
    case studies = "Études"
    case blank = "Créer de zéro"

    var id: String { rawValue }

    var channelNames: [String] {
        switch self {
        case .friends: ["général", "discussions"]
        case .games: ["général", "parties", "entraide"]
        case .studies: ["général", "devoirs", "ressources"]
        case .blank: ["général"]
        }
    }
}

@MainActor
protocol OnboardingActions {
    func resumeConfirmation(email: String)
    func register(email: String, password: String) async throws
    func confirmCode(_ code: String) async throws -> String
    func resendCode() async throws
    func login(email: String, password: String) async throws -> String
    func resetPassword(email: String) async throws
    func checkUsername(_ username: String) async throws -> Bool
    func setUsername(_ username: String) async throws
    func setDisplayName(_ name: String) async throws
    func setAvatar(_ data: Data) async throws
    func setAvatarEmoji(_ emoji: String) async throws
    func searchUser(username: String) async throws -> MoodUser?
    func addFriend(_ user: MoodUser) async throws
    func openDM(with user: MoodUser) async throws
    func joinServer(code: String) async throws
    func createServer(name: String, template: OnboardingTemplate) async throws
    func requestNotifications() async throws
    func finish() async throws
}

enum OnboardingError: LocalizedError, Equatable {
    case network
    case usernameTaken
    case invalidCode
    case friendNotFound
    case invalidServer
    case invalidLogin
    case finishFailed

    var errorDescription: String? {
        switch self {
        case .network:
            "La connexion a été interrompue. Réessaie."
        case .usernameTaken:
            "Ce nom d'utilisateur est déjà pris."
        case .invalidCode:
            "Ce code ne correspond pas. Vérifie ton e-mail."
        case .friendNotFound:
            "Aucun compte ne porte ce nom. Vérifie l’orthographe."
        case .invalidServer:
            "Entre un nom ou un code d’invitation valide."
        case .invalidLogin:
            "Cette adresse e-mail ou ce mot de passe ne fonctionne pas."
        case .finishFailed:
            "Mood n’a pas pu enregistrer cette étape. Réessaie."
        }
    }
}

@Observable
@MainActor
final class OnboardingModel {
    private struct Draft: Codable {
        var step: OnboardingStep
        var email: String
        var username: String
        var displayName: String
        var friendUsername: String
        var inviteCode: String
        var serverName: String
        var template: OnboardingTemplate
        var isCreatingServer: Bool
        var avatarEmoji: String?
        var usernameSaved: Bool?
    }

    private(set) var step: OnboardingStep
    var email = "" { didSet { saveDraft() } }
    var code = ""
    var username = "" {
        didSet {
            if username != oldValue {
                usernameCheckGeneration += 1
                isCheckingUsername = false
                usernameAvailability = nil
                fieldError = nil
            }
            saveDraft()
        }
    }
    var password = ""
    var displayName = "" { didSet { saveDraft() } }
    var friendUsername = "" { didSet { saveDraft() } }
    var inviteCode = "" { didSet { saveDraft() } }
    var serverName = "" { didSet { saveDraft() } }
    var template: OnboardingTemplate = .friends { didSet { saveDraft() } }
    var isCreatingServer = false { didSet { saveDraft() } }
    var showsPassword = false
#if os(iOS)
    var selectedPhotoItem: PhotosPickerItem?
#elseif os(macOS)
    var isShowingImageImporter = false
#endif

    private(set) var isBusy = false
    private(set) var isCheckingUsername = false
    private(set) var isResendingCode = false
    private(set) var isResettingPassword = false
    private(set) var fieldError: String?
    private(set) var networkError: String?
    private(set) var usernameAvailability: Bool?
    private(set) var accountID: String?
    private(set) var avatarData: Data?
    private(set) var avatarEmoji: String?
    private(set) var didFinish = false
    private(set) var passwordResetSent = false

    @ObservationIgnored private let actions: any OnboardingActions
    @ObservationIgnored private let defaults: UserDefaults
    private var usernameCheckGeneration = 0
    private var activeUserID: String?
    private var usernameSaved = false
    private var isRestoringDraft = false
    private var progressKey: String { Self.progressKey(for: activeUserID) }

    init(
        actions: any OnboardingActions,
        defaults: UserDefaults = .standard,
        userID: String? = nil
    ) {
        self.actions = actions
        self.defaults = defaults
        self.activeUserID = userID
        self.accountID = userID
        self.step = userID == nil ? .welcome : .username
        self.didFinish = userID.map { defaults.bool(forKey: Self.completionKey(for: $0)) } ?? false

        let key = Self.progressKey(for: userID)
        let data = defaults.data(forKey: key)
            ?? (userID == nil ? defaults.data(forKey: Self.progressKey(for: nil)) : nil)
        if let data, let draft = try? JSONDecoder().decode(Draft.self, from: data) {
            restore(draft)
        }
    }

    static func completionKey(for userID: String) -> String {
        "mood.onboarding.done.\(userID)"
    }

    static func progressKey(for userID: String?) -> String {
        userID.map { "mood.onboarding.progress.\($0)" } ?? "mood.onboarding.progress"
    }

    static func isComplete(for userID: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: completionKey(for: userID))
    }

    /// Recover an OTP session saved just before the process exited, before the model adopted it.
    static func recoverConfirmation(for userID: String, email: String?, defaults: UserDefaults = .standard) {
        guard let email,
              defaults.data(forKey: progressKey(for: userID)) == nil,
              let data = defaults.data(forKey: progressKey(for: nil)),
              var draft = try? JSONDecoder().decode(Draft.self, from: data),
              draft.step == .confirmation,
              draft.email.lowercased() == email.lowercased() else { return }
        draft.step = .username
        draft.usernameSaved = false
        guard let migrated = try? JSONEncoder().encode(draft) else { return }
        defaults.set(migrated, forKey: progressKey(for: userID))
        defaults.removeObject(forKey: progressKey(for: nil))
    }

    var emailIsValid: Bool {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.range(
            of: #"\A[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\z"#,
            options: .regularExpression
        ) != nil
    }

    var usernameIsValid: Bool {
        let length = username.utf8.count
        return (2...32).contains(length)
            && username.utf8.allSatisfy { byte in
                (byte >= 97 && byte <= 122)
                    || (byte >= 48 && byte <= 57)
                    || byte == 95
                    || byte == 46
            }
            && !username.contains("..")
    }

    var passwordIsValid: Bool { password.count >= 8 }

    var canContinue: Bool {
        switch step {
        case .welcome, .trust, .notifications:
            true
        case .email:
            emailIsValid
        case .account:
            passwordIsValid
        case .username:
            accountID != nil && usernameIsValid && usernameAvailability == true && !isCheckingUsername
        case .confirmation:
            code.count == 6 && code.allSatisfy { $0 >= "0" && $0 <= "9" }
        case .displayName:
            !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .server:
            isCreatingServer
                ? !serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                : !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .friends:
            !friendUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .avatar:
            avatarData != nil || avatarEmoji != nil
        case .signIn:
            emailIsValid && passwordIsValid
        }
    }

    var title: String {
        switch step {
        case .welcome: "Bienvenue sur Mood"
        case .email: "Ton adresse e-mail"
        case .account: "Crée ton mot de passe"
        case .confirmation: "Confirme ton adresse"
        case .displayName: "Comment tu t’appelles ?"
        case .username: "Ton nom d’utilisateur"
        case .trust: "Ce qui est à toi"
        case .server: "Ton premier serveur"
        case .notifications: "Ne rate pas un message"
        case .friends: "Trouve tes amis"
        case .avatar: "Choisis ta photo"
        case .signIn: "Ha, te revoilà !"
        }
    }

    func go(_ destination: OnboardingStep) {
        guard !didFinish else { return }
        if destination != .account && destination != .signIn { password = "" }
        step = destination
        usernameCheckGeneration += 1
        isCheckingUsername = false
        usernameAvailability = nil
        fieldError = nil
        networkError = nil
        code = ""
        saveDraft()
    }

    func back() {
        guard !isBusy else { return }
        let previous: OnboardingStep?
        switch step {
        case .welcome: previous = nil
        case .email, .signIn: previous = .welcome
        case .account: previous = .email
        case .confirmation: previous = .account
        case .displayName: previous = nil
        case .username: previous = .displayName
        case .trust: previous = .username
        case .server: previous = .trust
        case .notifications: previous = .server
        case .friends: previous = .notifications
        case .avatar: previous = .friends
        }
        if let previous { go(previous) }
    }

    func skip() async {
        guard !isBusy else { return }
        switch step {
        case .displayName: go(.username)
        case .server: go(.notifications)
        case .notifications: go(.friends)
        case .friends: go(.avatar)
        case .avatar: await finishOnboarding()
        default: break
        }
    }

    func continueWithoutNotifications() {
        guard step == .notifications, !isBusy else { return }
        go(.friends)
    }

    func submit() async {
        guard !isBusy else { return }
        guard canContinue else {
            fieldError = validationMessage
            return
        }

        isBusy = true
        fieldError = nil
        networkError = nil
        defer { isBusy = false }

        do {
            switch step {
            case .welcome:
                go(.email)
            case .email:
                email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                go(.account)
            case .account:
                try await actions.register(email: email, password: password)
                password = ""
                go(.confirmation)
            case .confirmation:
                actions.resumeConfirmation(email: email)
                let userID = try await actions.confirmCode(code)
                code = ""
                password = ""
                adoptAccount(userID)
                go(.displayName)
            case .displayName:
                let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { try await actions.setDisplayName(name) }
                go(.username)
            case .username:
                try await actions.setUsername(username)
                usernameSaved = true
                go(.trust)
            case .trust:
                go(.server)
            case .server:
                if isCreatingServer {
                    try await actions.createServer(
                        name: serverName.trimmingCharacters(in: .whitespacesAndNewlines),
                        template: template
                    )
                } else {
                    try await actions.joinServer(code: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                go(.notifications)
            case .notifications:
                try await actions.requestNotifications()
                go(.friends)
            case .friends:
                let name = friendUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let user = try await actions.searchUser(username: name) else {
                    fieldError = OnboardingError.friendNotFound.localizedDescription
                    return
                }
                try await actions.addFriend(user)
                try await actions.openDM(with: user)
                go(.avatar)
            case .avatar:
                if let avatarData {
                    try await actions.setAvatar(avatarData)
                } else if let avatarEmoji {
                    try await actions.setAvatarEmoji(avatarEmoji)
                }
                try await completeAccount()
            case .signIn:
                email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let userID = try await actions.login(email: email, password: password)
                password = ""
                adoptAccount(userID, migrateGuest: false)
                if Self.isComplete(for: userID, defaults: defaults) {
                    didFinish = true
                    clearDrafts()
                } else if !loadAccountDraft(userID) {
                    go(.username)
                }
            }
        } catch let error as OnboardingError {
            if error == .usernameTaken { usernameAvailability = false }
            if [.usernameTaken, .invalidCode, .friendNotFound, .invalidServer, .invalidLogin].contains(error) {
                fieldError = error.localizedDescription
            } else {
                networkError = error.localizedDescription
            }
        } catch {
            networkError = error.localizedDescription
        }
    }

    func acceptConfirmedSession() async {
        guard accountID == nil, !isBusy, step == .confirmation else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            actions.resumeConfirmation(email: email)
            let id = try await actions.confirmCode("")
            adoptAccount(id)
            go(.displayName)
        } catch { networkError = error.localizedDescription }
    }

    func checkUsername() async {
        guard accountID != nil, step == .username else { return }
        guard usernameIsValid else {
            usernameAvailability = nil
            fieldError = username.isEmpty ? nil : "2 à 32 caractères : a-z, 0-9, _ ou ."
            return
        }
        guard !isBusy else { return }
        usernameCheckGeneration += 1
        let generation = usernameCheckGeneration
        let candidate = username
        isCheckingUsername = true
        usernameAvailability = nil
        fieldError = nil
        networkError = nil
        defer { if generation == usernameCheckGeneration { isCheckingUsername = false } }
        do {
            let available = try await actions.checkUsername(candidate)
            guard generation == usernameCheckGeneration, username == candidate, !Task.isCancelled else { return }
            usernameAvailability = available
            if !available { fieldError = OnboardingError.usernameTaken.localizedDescription }
        } catch {
            guard generation == usernameCheckGeneration, username == candidate, !Task.isCancelled else { return }
            networkError = error.localizedDescription
        }
    }

    func resendCode() async {
        guard !isResendingCode else { return }
        isResendingCode = true
        networkError = nil
        defer { isResendingCode = false }
        do {
            actions.resumeConfirmation(email: email)
            try await actions.resendCode()
        } catch {
            networkError = error.localizedDescription
        }
    }

    func resetPassword() async {
        guard emailIsValid, !isResettingPassword else {
            fieldError = "Entre une adresse e-mail valide pour recevoir un code."
            return
        }
        isResettingPassword = true
        passwordResetSent = false
        fieldError = nil
        networkError = nil
        defer { isResettingPassword = false }
        do {
            try await actions.resetPassword(email: email)
            password = ""
            code = ""
            passwordResetSent = true
        } catch {
            networkError = error.localizedDescription
        }
    }

    func setAvatarData(_ data: Data?) {
        if let data, data.count > 20 * 1024 * 1024 {
            fieldError = "Choisis une photo de moins de 20 Mo."
            return
        }
        avatarData = data
        if data != nil { avatarEmoji = nil }
        fieldError = nil
        networkError = nil
        saveDraft()
    }

    func selectAvatarEmoji(_ emoji: String) {
        avatarEmoji = emoji
        avatarData = nil
        fieldError = nil
        networkError = nil
        saveDraft()
    }

    func showFieldError(_ message: String?) {
        fieldError = message
    }

    private func finishOnboarding() async {
        guard !isBusy else { return }
        guard accountID != nil else {
            networkError = "Connecte-toi pour terminer la création de ton espace."
            return
        }
        isBusy = true
        fieldError = nil
        networkError = nil
        defer { isBusy = false }
        do {
            try await completeAccount()
        } catch {
            networkError = error.localizedDescription
        }
    }

    private func completeAccount() async throws {
        guard let accountID else { throw OnboardingError.invalidLogin }
        try await actions.finish()
        defaults.set(true, forKey: Self.completionKey(for: accountID))
        clearDrafts()
        password = ""
        code = ""
        avatarData = nil
        didFinish = true
    }

    /// Discard private drafts on sign-out; completion stays scoped to its account.
    static func discardProgress(for userID: String?, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: progressKey(for: userID))
        defaults.removeObject(forKey: progressKey(for: nil))
    }

    private var validationMessage: String? {
        switch step {
        case .email: "Entre une adresse e-mail valide."
        case .account:
            "Choisis un mot de passe de 8 caractères minimum."
        case .username:
            if !usernameIsValid { "2 à 32 caractères : a-z, 0-9, _ ou ." }
            else if usernameAvailability != true { "Vérifie d’abord si ce nom est libre."
            } else { nil }
        case .confirmation: "Entre les 6 chiffres reçus par e-mail."
        case .displayName: "Entre le nom que tes amis verront, ou passe cette étape."
        case .server: isCreatingServer ? "Entre un nom pour ton serveur." : "Entre un code ou un lien d’invitation."
        case .friends: "Entre un nom d’utilisateur Mood."
        case .avatar: "Choisis une photo ou un emoji."
        case .signIn: "Vérifie ton adresse e-mail et ton mot de passe."
        default: nil
        }
    }

    private func adoptAccount(_ userID: String, migrateGuest: Bool = true) {
        let previousKey = progressKey
        activeUserID = userID
        accountID = userID
        if migrateGuest, previousKey != progressKey, let data = defaults.data(forKey: previousKey) {
            defaults.set(data, forKey: progressKey)
        }
        if previousKey != progressKey { defaults.removeObject(forKey: previousKey) }
        if !migrateGuest {
            // Sign-in must not carry another account's guest form into the restored account.
            isRestoringDraft = true
            username = ""
            usernameSaved = false
            displayName = ""
            friendUsername = ""
            inviteCode = ""
            serverName = ""
            template = .friends
            isCreatingServer = false
            avatarEmoji = nil
            avatarData = nil
            isRestoringDraft = false
        }
    }

    @discardableResult
    private func loadAccountDraft(_ userID: String) -> Bool {
        guard let data = defaults.data(forKey: Self.progressKey(for: userID)),
              let draft = try? JSONDecoder().decode(Draft.self, from: data) else { return false }
        restore(draft)
        return true
    }

    private func restore(_ draft: Draft) {
        isRestoringDraft = true
        usernameSaved = draft.usernameSaved ?? false
        step = activeUserID != nil && (!usernameSaved || [.welcome, .email, .account, .confirmation, .signIn].contains(draft.step))
            ? .username : draft.step
        email = draft.email
        username = draft.username
        displayName = draft.displayName
        friendUsername = draft.friendUsername
        inviteCode = draft.inviteCode
        serverName = draft.serverName
        template = draft.template
        isCreatingServer = draft.isCreatingServer
        avatarEmoji = draft.avatarEmoji
        isRestoringDraft = false
    }

    private func clearDrafts() {
        defaults.removeObject(forKey: progressKey)
        defaults.removeObject(forKey: Self.progressKey(for: nil))
    }

    private func saveDraft() {
        guard !isRestoringDraft,
              step != .welcome,
              step != .signIn,
              !didFinish else { return }
        let draft = Draft(
            step: step,
            email: email,
            username: username,
            displayName: displayName,
            friendUsername: friendUsername,
            inviteCode: inviteCode,
            serverName: serverName,
            template: template,
            isCreatingServer: isCreatingServer,
            avatarEmoji: avatarEmoji,
            usernameSaved: usernameSaved
        )
        if let data = try? JSONEncoder().encode(draft) {
            defaults.set(data, forKey: progressKey)
        }
    }
}

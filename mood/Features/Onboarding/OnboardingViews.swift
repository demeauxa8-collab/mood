import ImageIO
#if os(iOS)
import PhotosUI
#elseif os(macOS)
import UniformTypeIdentifiers
#endif
import SwiftUI

struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    var mode: LayoutMode = .compact
    var onPasswordReset: (() -> Void)? = nil
    var usesScrollContainer = true
    var usesNativeTextInputs = true
    var usesNativeProgressIndicator = true

    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var labelSize: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var avatarTopSpacing: CGFloat = 28
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email
        case username
        case password
        case code
        case displayName
        case friend
        case invite
        case server
    }

    var body: some View {
        Group {
            if mode == .regular {
                ZStack {
                    MoodTheme.windowBackground.ignoresSafeArea()
                    GeometryReader { geometry in
                        ScrollView {
                            card
                                .frame(maxWidth: LayoutMetrics.onboardingCardWidth)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(LayoutMetrics.mobile(24))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: geometry.size.height)
                        }
                    }
                }
            } else {
                ZStack {
                    MoodTheme.mobileSurface.ignoresSafeArea()
                    card
                }
            }
        }
        .disabled(model.isBusy)
        .environment(\.layoutMode, mode)
        .preferredColorScheme(.dark)
        .onChange(of: model.step) { _, step in
            focusedField = nil
            guard mode == .compact else { return }
            Task { @MainActor in
                await Task.yield()
                guard model.step == step else { return }
                switch step {
                case .email: focusedField = .email
                case .account: focusedField = .password
                case .username: focusedField = .username
                case .confirmation: focusedField = .code
                case .displayName: focusedField = .displayName
                case .friends: focusedField = .friend
                case .server: focusedField = model.isCreatingServer ? .server : .invite
                case .signIn: focusedField = .email
                default: break
                }
            }
        }
        .onChange(of: focusedField) { oldField, newField in
            guard oldField != newField else { return }
            if oldField == .email && !model.emailIsValid {
                model.showFieldError("Entre une adresse e-mail valide.")
            } else if oldField == .displayName && model.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.showFieldError("Entre le nom que tes amis verront, ou passe cette étape.")
            }
        }
        .onChange(of: model.email) { _, _ in
            if model.emailIsValid { model.showFieldError(nil) }
        }
        .task(id: "\(model.step.rawValue)-\(model.username)") {
            guard model.step == .username, model.usernameIsValid, model.usernameAvailability == nil else { return }
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled, model.step == .username, model.usernameIsValid else { return }
            await model.checkUsername()
        }
        #if os(iOS)
        .onChange(of: model.selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        model.setAvatarData(data)
                    } else {
                        model.showFieldError("Cette photo n’a pas pu être ouverte. Choisis-en une autre.")
                    }
                } catch {
                    model.showFieldError("Cette photo n’a pas pu être ouverte. Choisis-en une autre.")
                }
                model.selectedPhotoItem = nil
            }
        }
        #elseif os(macOS)
        .fileImporter(
            isPresented: $model.isShowingImageImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                    model.setAvatarData(try Data(contentsOf: url))
                } catch {
                    model.showFieldError("Cette photo n’a pas pu être ouverte. Choisis-en une autre.")
                }
            case .failure:
                model.showFieldError("Aucune photo n’a été ajoutée.")
            }
        }
        #endif

    }

    @ViewBuilder
    private var card: some View {
        if mode == .regular {
            VStack(spacing: LayoutMetrics.mobile(0)) {
                navigationBar
                if let error = model.networkError {
                    networkNotice(error).padding(.horizontal, horizontalInset)
                }
                page
            }
            .padding(.bottom, LayoutMetrics.mobile(28))
            .foregroundStyle(MoodTheme.textPrimary)
            .background(MoodTheme.chatBackground)
            .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.mobile(18), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LayoutMetrics.mobile(18), style: .continuous)
                    .stroke(MoodTheme.composerBorder, lineWidth: LayoutMetrics.mobile(1))
                    .allowsHitTesting(false)
            }
        } else {
            VStack(spacing: LayoutMetrics.mobile(0)) {
                navigationBar
                if let error = model.networkError {
                    networkNotice(error)
                        .padding(.horizontal, horizontalInset)
                        .padding(.top, LayoutMetrics.mobile(6))
                }
                page
            }
            .foregroundStyle(MoodTheme.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MoodTheme.mobileSurface)
        }
    }

    @ViewBuilder
    private var page: some View {
        switch model.step {
        case .welcome: welcomeScreen
        case .notifications:
            if mode == .compact { ScrollView { notificationScreen } } else { notificationScreen }
        case .avatar:
            if mode == .compact { ScrollView { avatarScreen } } else { avatarScreen }
        default: standardScreen
        }
    }

    private var horizontalInset: CGFloat { mode == .compact ? 16 : 32 }

    private var navigationBar: some View {
        HStack(spacing: LayoutMetrics.mobile(0)) {
            if showsBackButton {
                Button(action: model.back) {
                    Image(systemName: "chevron.left")
                        .font(.mood(17, weight: .semibold))
                        .frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(MoodTheme.textPrimary)
                .accessibilityLabel("Retour")
            } else {
                Color.clear.frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44))
            }

            Spacer()

            if canSkipCurrentStep {
                Button("Passer") {
                    Task { await model.skip() }
                }
                .font(.mood(16, weight: .medium))
                .foregroundStyle(MoodTheme.textSecondary)
                .frame(minWidth: LayoutMetrics.mobile(56), minHeight: LayoutMetrics.mobile(44))
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityLabel("Passer cette étape")
            } else if model.step == .signIn {
                Button("Créer un compte") { model.go(.email) }
                    .font(.mood(14, weight: .medium))
                    .foregroundStyle(MoodTheme.brandAccent)
                    .frame(minWidth: LayoutMetrics.mobile(44), minHeight: LayoutMetrics.mobile(44))
                    .buttonStyle(.plain)
                    .accessibilityLabel("Créer un compte")
            } else {
                Color.clear.frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44))
            }
        }
        .padding(.horizontal, LayoutMetrics.mobile(mode == .compact ? 8 : 18))
        .padding(.top, LayoutMetrics.mobile(mode == .compact ? 0 : 8))
        .frame(height: mode == .compact ? 48 : 54)
    }

    private var standardScreen: some View {
        Group {
            if mode == .regular || !usesScrollContainer {
                standardScreenContent
            } else {
                ScrollView(showsIndicators: false) {
                    standardScreenContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: mode == .compact ? .infinity : nil, alignment: .top)
    }

    private var standardScreenContent: some View {
        VStack(spacing: LayoutMetrics.mobile(0)) {
            titleBlock
                .padding(.top, LayoutMetrics.mobile(mode == .compact ? 14 : 20))

            screenContent
                .padding(.top, contentTopSpacing)

            if showsPrimaryButton {
                primaryButton
                    .padding(.top, buttonTopSpacing)
            }

            if model.step == .confirmation {
                resendCodeButton
                    .padding(.top, LayoutMetrics.mobile(4))
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, LayoutMetrics.mobile(mode == .compact ? 20 : 0))
        .frame(maxWidth: mode == .regular ? 416 : 620)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var welcomeScreen: some View {
        VStack(spacing: LayoutMetrics.mobile(0)) {
            if mode == .compact { Spacer(minLength: LayoutMetrics.mobile(112)) } else { Color.clear.frame(height: LayoutMetrics.mobile(28)) }

            MoodInfinitySymbol(size: LayoutMetrics.mobile(mode == .compact ? 120 : 96))
                .padding(.bottom, LayoutMetrics.mobile(26))

            Text("Bienvenue sur\nMood")
                .font(.mood(titleSize + 4, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Retrouve tes amis et tes conversations au même endroit.")
                .font(.mood(bodySize))
                .foregroundStyle(MoodTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, LayoutMetrics.mobile(12))
                .padding(.horizontal, LayoutMetrics.mobile(18))

            if mode == .compact { Spacer(minLength: LayoutMetrics.mobile(86)) } else { Color.clear.frame(height: LayoutMetrics.mobile(30)) }

            VStack(spacing: LayoutMetrics.mobile(12)) {
                Button { model.go(.email) } label: { Text("Créer mon compte") }
                    .buttonStyle(MobilePrimaryButtonStyle())
                    .accessibilityHint("Commence la création de ton compte Mood")

                Button { model.go(.signIn) } label: { Text("J’ai déjà un compte") }
                    .buttonStyle(MobilePrimaryButtonStyle(secondary: true))
                    .accessibilityHint("Ouvre une session avec ton adresse e-mail")
            }
            .padding(.horizontal, LayoutMetrics.mobile(mode == .compact ? 28 : 8))
            .padding(.bottom, LayoutMetrics.mobile(mode == .compact ? 16 : 0))
        }
        .padding(.horizontal, horizontalInset)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: mode == .compact ? .infinity : nil)
    }

    private var notificationScreen: some View {
        VStack(spacing: LayoutMetrics.mobile(0)) {
            if mode == .compact { Spacer(minLength: LayoutMetrics.mobile(130)) }

            MoodInfinitySymbol(size: 128)
                .padding(.bottom, LayoutMetrics.mobile(-8))
                .accessibilityHidden(true)

            VStack(spacing: LayoutMetrics.mobile(12)) {
                Text("Ne rate pas un message")
                    .font(.mood(22, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("Reçois un signal quand quelqu’un t’écrit, même si son message attendait ton retour en ligne.")
                    .font(.mood(15))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: LayoutMetrics.mobile(10)) {
                    Button("Plus tard", action: model.continueWithoutNotifications)
                        .buttonStyle(MobilePrimaryButtonStyle(secondary: true))
                    Button {
                        Task { await model.submit() }
                    } label: {
                        if model.isBusy && usesNativeProgressIndicator {
                            ProgressView().tint(MoodTheme.mobileIndicator)
                        } else {
                            Text("Autoriser")
                        }
                    }
                    .buttonStyle(MobilePrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .accessibilityHint("Affiche la demande de notifications")
                }
                .frame(minHeight: LayoutMetrics.mobile(50))
                .padding(.top, LayoutMetrics.mobile(2))
            }
            .padding(.horizontal, LayoutMetrics.mobile(20))
            .padding(.vertical, LayoutMetrics.mobile(22))
            .frame(maxWidth: mode == .compact ? 332 : 416)
            .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(24), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LayoutMetrics.mobile(24), style: .continuous)
                    .stroke(MoodTheme.composerBorder, lineWidth: LayoutMetrics.mobile(1))
            }
            .shadow(color: MoodTheme.windowBackground.opacity(0.24), radius: LayoutMetrics.mobile(18), y: LayoutMetrics.mobile(8))

            if mode == .compact { Spacer(minLength: LayoutMetrics.mobile(80)) }
        }
        .padding(.horizontal, LayoutMetrics.mobile(mode == .compact ? 24 : 32))
        .frame(maxWidth: .infinity, maxHeight: mode == .compact ? .infinity : nil)
    }

    private var avatarScreen: some View {
        VStack(spacing: LayoutMetrics.mobile(0)) {
            VStack(spacing: LayoutMetrics.mobile(0)) {
                titleBlock
                    .padding(.top, LayoutMetrics.mobile(mode == .compact ? 2 : 12))
                avatarContent
                    .padding(.top, LayoutMetrics.mobile(avatarTopSpacing))
                if let error = model.fieldError { fieldErrorLabel(error) }

            }

            if mode == .compact { Spacer(minLength: LayoutMetrics.mobile(20)) } else { Color.clear.frame(height: LayoutMetrics.mobile(24)) }

            primaryButton
                .padding(.horizontal, LayoutMetrics.mobile(mode == .compact ? -8 : 0))
                .padding(.bottom, LayoutMetrics.mobile(mode == .compact ? 16 : 0))
        }
        .padding(.horizontal, horizontalInset)
        .frame(maxWidth: mode == .regular ? 416 : .infinity, maxHeight: mode == .compact ? .infinity : nil)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var titleBlock: some View {
        VStack(spacing: LayoutMetrics.mobile(10)) {
            Text(model.title)
                .font(.mood(model.step == .avatar ? 24 : titleSize, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                Text(subtitle)
                    .font(.mood(bodySize))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, LayoutMetrics.mobile(8))
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var screenContent: some View {
        switch model.step {
        case .welcome, .notifications, .avatar:
            EmptyView()
        case .email:
            textField(
                label: "E-mail",
                placeholder: "toi@exemple.fr",
                text: $model.email,
                field: .email,
                inputKind: .email,
                contentHint: .email,
                error: model.fieldError
            )
        case .account:
            VStack(alignment: .leading, spacing: LayoutMetrics.mobile(14)) {
                securePasswordField(label: "Mot de passe", error: passwordFieldError, contentHint: .newPassword)
                Text("8 caractères minimum. Pas besoin d’ajouter d’autres règles.")
                    .font(.mood(14))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .username:
            VStack(alignment: .leading, spacing: LayoutMetrics.mobile(14)) {
                textField(
                    label: "Nom d’utilisateur",
                    placeholder: "ex. alex_7",
                    text: $model.username,
                    field: .username,
                    inputKind: .username,
                    contentHint: .username,
                    error: model.fieldError
                )
                if model.usernameAvailability == true {
                    // Lookup is advisory: the unique constraint arbitrates the final save.
                    Label("Nom vérifié. Tu peux continuer.", systemImage: "checkmark.circle.fill")
                        .font(.mood(14, weight: .medium))
                        .foregroundStyle(MoodTheme.onlineGreen)
                        .accessibilityLabel("Nom d’utilisateur vérifié par le serveur")
                } else if model.isCheckingUsername {
                    Text("Vérification du nom…")
                        .font(.mood(14))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
                if model.networkError != nil || model.usernameAvailability == false {
                    Button("Vérifier à nouveau") { Task { await model.checkUsername() } }
                        .font(.mood(14, weight: .medium))
                        .foregroundStyle(MoodTheme.brandAccent)
                        .frame(minHeight: LayoutMetrics.mobile(44))
                        .disabled(model.isCheckingUsername)
                }
                Text("2 à 32 caractères : a-z, 0-9, _ ou . Pas de points consécutifs.")
                    .font(.mood(14))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .confirmation:
            textField(
                label: "",
                placeholder: "000000",
                text: $model.code,
                field: .code,
                inputKind: .numeric,
                contentHint: .oneTimeCode,
                error: model.fieldError
            )
            .onChange(of: model.code) { _, value in
                let digits = String(value.filter { $0 >= "0" && $0 <= "9" }.prefix(6))
                if digits != value { model.code = digits }
            }
        case .displayName:
            VStack(alignment: .leading, spacing: LayoutMetrics.mobile(8)) {
                textField(
                    label: "Nom affiché",
                    placeholder: "Ton nom",
                    text: $model.displayName,
                    field: .displayName,
                    inputKind: .text,
                    error: model.fieldError
                )
                Text("Le nom que tes amis verront. Tu pourras le changer.")
                    .font(.mood(14))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .trust:
            trustContent
        case .server:
            serverContent
        case .friends:
            VStack(alignment: .leading, spacing: LayoutMetrics.mobile(14)) {
                textField(
                    label: "Nom d’utilisateur Mood",
                    placeholder: "ex. sam_2",
                    text: $model.friendUsername,
                    field: .friend,
                    inputKind: .username,
                    error: model.fieldError
                )
                Label("On ne synchronise pas tes contacts. Tu choisis qui tu retrouves.", systemImage: "hand.raised")
                    .font(.mood(14))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }
        case .signIn:
            signInContent
        }
    }

    private var trustContent: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(16)) {
            trustLine("server.rack", title: "Tes messages passent par les serveurs Mood.")
            trustLine("person.crop.circle", title: "Ton compte et ton profil sont stockés séparément des messages.")
            trustLine("arrow.up.circle", title: "Dans une conversation déjà ouverte, tes envois attendent le retour du réseau.")
            trustLine("info.circle", title: "Le chiffrement de bout en bout est en route. Il n’est pas encore activé.")
        }
        .padding(LayoutMetrics.mobile(18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(18), style: .continuous))
    }

    private var serverContent: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(16)) {
            HStack(spacing: LayoutMetrics.mobile(10)) {
                serverChoice("Rejoindre un serveur", selected: !model.isCreatingServer) {
                    model.isCreatingServer = false
                    model.showFieldError(nil)
                }
                serverChoice("Créer le mien", selected: model.isCreatingServer) {
                    model.isCreatingServer = true
                    model.showFieldError(nil)
                }
            }

            if model.isCreatingServer {
                textField(
                    label: "Nom du serveur",
                    placeholder: "Notre serveur",
                    text: $model.serverName,
                    field: .server,
                    inputKind: .text,
                    error: model.fieldError
                )

                VStack(alignment: .leading, spacing: LayoutMetrics.mobile(9)) {
                    Text("Choisis un modèle")
                        .font(.mood(labelSize, weight: .medium))
                        .foregroundStyle(MoodTheme.textSecondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: LayoutMetrics.mobile(8)) {
                        ForEach(OnboardingTemplate.allCases) { item in
                            templateChoice(item)
                        }
                    }
                }
            } else {
                textField(
                    label: "Code ou lien d’invitation",
                    placeholder: "Colle une invitation",
                    text: $model.inviteCode,
                    field: .invite,
                    inputKind: .text,
                    error: model.fieldError
                )
                Text("Tu pourras aussi rejoindre un serveur plus tard.")
                    .font(.mood(14))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var signInContent: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(18)) {
            textField(
                label: "E-mail",
                placeholder: "toi@exemple.fr",
                text: $model.email,
                field: .email,
                inputKind: .email,
                contentHint: .email,
                error: model.fieldError
            )
            securePasswordField(label: "Mot de passe", error: nil, contentHint: .password)
            Button {
                Task {
                    await model.resetPassword()
                    if model.passwordResetSent { onPasswordReset?() }
                }
            } label: {
                HStack(spacing: LayoutMetrics.mobile(8)) {
                    if model.isResettingPassword { ProgressView().controlSize(.small) }
                    Text("Mot de passe oublié ?")
                    Spacer(minLength: LayoutMetrics.mobile(0))
                }
                .font(.mood(14, weight: .medium))
                .foregroundStyle(MoodTheme.brandAccent)
                .frame(minHeight: LayoutMetrics.mobile(44))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Envoie un code de réinitialisation à cette adresse e-mail")
            if model.passwordResetSent {
                Label("Un code de réinitialisation a été envoyé.", systemImage: "checkmark.circle.fill")
                    .font(.mood(14))
                    .foregroundStyle(MoodTheme.onlineGreen)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var avatarContent: some View {
        VStack(spacing: LayoutMetrics.mobile(20)) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(MoodTheme.inputBg)
                    .frame(width: LayoutMetrics.mobile(200), height: LayoutMetrics.mobile(200))
                    .overlay {
                        if let image = selectedAvatarImage {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .scaledToFill()
                                .frame(width: LayoutMetrics.mobile(200), height: LayoutMetrics.mobile(200))
                                .clipShape(Circle())
                                .accessibilityHidden(true)
                        } else {
                            Text(model.avatarEmoji ?? defaultAvatarCharacter)
                                .font(.mood(76, weight: .medium))
                                .frame(width: LayoutMetrics.mobile(200), height: LayoutMetrics.mobile(200))
                                .accessibilityLabel("Aperçu de ton avatar")
                        }
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(
                                MoodTheme.divider,
                                style: StrokeStyle(lineWidth: LayoutMetrics.mobile(2), dash: model.avatarEmoji == nil && model.avatarData == nil ? [6, 6] : [])
                            )
                    }
                    .accessibilityElement(children: .combine)

                photoPickerButton
            }

            VStack(spacing: LayoutMetrics.mobile(14)) {
                Text("ou choisis un emoji")
                    .font(.mood(16))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .frame(maxWidth: .infinity)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: LayoutMetrics.mobile(12)), count: 4), spacing: LayoutMetrics.mobile(14)) {
                    ForEach(Self.avatarEmojis, id: \.self) { emoji in
                        avatarEmojiButton(emoji)
                    }
                }
                .frame(maxWidth: 312)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private static let avatarEmojis = ["🙂", "😎", "🐸", "⭐️", "🐱", "🌙", "🦋", "🐼"]

    @ViewBuilder
    private var photoPickerButton: some View {
        #if os(iOS)
        PhotosPicker(selection: $model.selectedPhotoItem, matching: .images) {
            photoPickerLabel
        }
        .accessibilityLabel("Choisir une photo de profil")
        .offset(x: LayoutMetrics.mobile(5), y: LayoutMetrics.mobile(-5))
        #elseif os(macOS)
        Button { model.isShowingImageImporter = true } label: {
            photoPickerLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choisir une photo de profil")
        .offset(x: LayoutMetrics.mobile(5), y: LayoutMetrics.mobile(-5))
        #endif
    }

    private var photoPickerLabel: some View {
        Image(systemName: "plus")
            .font(.mood(20, weight: .semibold))
            .foregroundStyle(MoodTheme.mobileIndicator)
            .frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44))
            .background(MoodTheme.brandAccent, in: Circle())
            .contentShape(Circle())
    }

    private var defaultAvatarCharacter: String {
        model.displayName.first.map(String.init) ?? model.username.first.map(String.init) ?? "🙂"
    }

    private var selectedAvatarImage: CGImage? {
        guard let data = model.avatarData,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary)
    }

    private func avatarEmojiButton(_ emoji: String) -> some View {
        let selected = model.avatarEmoji == emoji
        return Button { model.selectAvatarEmoji(emoji) } label: {
            Text(emoji)
                .font(.mood(28))
                .frame(width: LayoutMetrics.mobile(48), height: LayoutMetrics.mobile(48))
                .background(MoodTheme.inputBg, in: Circle())
                .overlay {
                    Circle().stroke(selected ? MoodTheme.brandAccent : MoodTheme.composerBorder, lineWidth: selected ? 2 : 1)
                }
                .overlay {
                    if selected {
                        Circle().stroke(MoodTheme.textPrimary, lineWidth: LayoutMetrics.mobile(1)).padding(LayoutMetrics.mobile(3))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: LayoutMetrics.mobile(48), minHeight: LayoutMetrics.mobile(48))
        .accessibilityLabel("Avatar \(emoji)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func trustLine(_ symbol: String, title: String) -> some View {
        HStack(alignment: .top, spacing: LayoutMetrics.mobile(12)) {
            Image(systemName: symbol)
                .font(.mood(17, weight: .semibold))
                .foregroundStyle(MoodTheme.brandAccent)
                .frame(width: LayoutMetrics.mobile(24), height: LayoutMetrics.mobile(24))
                .accessibilityHidden(true)
            Text(title)
                .font(.mood(15, weight: .medium))
                .foregroundStyle(MoodTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func serverChoice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.mood(14, weight: .semibold))
                .foregroundStyle(selected ? MoodTheme.textPrimary : MoodTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: LayoutMetrics.mobile(56))
                .background(selected ? MoodTheme.brandAccent.opacity(0.18) : MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16), style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16), style: .continuous)
                        .stroke(selected ? MoodTheme.brandAccent : MoodTheme.composerBorder, lineWidth: selected ? 1.5 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func templateChoice(_ item: OnboardingTemplate) -> some View {
        let selected = model.template == item
        return Button { model.template = item } label: {
            Text(item.rawValue)
                .font(.mood(14, weight: .medium))
                .foregroundStyle(selected ? MoodTheme.textPrimary : MoodTheme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: LayoutMetrics.mobile(44))
                .background(selected ? MoodTheme.brandAccent.opacity(0.18) : MoodTheme.inputBg, in: Capsule())
                .overlay(Capsule().stroke(selected ? MoodTheme.brandAccent : MoodTheme.composerBorder, lineWidth: LayoutMetrics.mobile(1)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func textField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        inputKind: InputKind,
        contentHint: ContentHint? = nil,
        error: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(7)) {
            if !label.isEmpty {
                Text(label)
                    .font(.mood(labelSize, weight: .medium))
                    .foregroundStyle(MoodTheme.textSecondary)
            }

            Group {
                if usesNativeTextInputs {
                    TextField(placeholder, text: text)
                        .focused($focusedField, equals: field)
                        .onboardingInputTraits(inputKind)
                        .applyTextContentType(contentHint)
                        .onSubmit { submitFromKeyboard() }
                        .foregroundStyle(MoodTheme.textPrimary)
                } else {
                    Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                        .foregroundStyle(text.wrappedValue.isEmpty ? MoodTheme.textMuted : MoodTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.mood(17))
            .padding(.horizontal, LayoutMetrics.mobile(16))
            .frame(height: LayoutMetrics.mobile(50))
            .background(MoodTheme.inputBg, in: Capsule())
            .overlay {
                Capsule().stroke(error == nil ? MoodTheme.composerBorder : MoodTheme.mentionBadge, lineWidth: error == nil ? 1 : 1.5)
            }
            .accessibilityLabel(label.isEmpty ? placeholder : label)
            .accessibilityHint(inputKind.accessibilityHint)

            if let error, !error.isEmpty { fieldErrorLabel(error) }
        }
    }

    private func securePasswordField(label: String, error: String?, contentHint: ContentHint) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(7)) {
            Text(label)
                .font(.mood(labelSize, weight: .medium))
                .foregroundStyle(MoodTheme.textSecondary)

            HStack(spacing: LayoutMetrics.mobile(0)) {
                if usesNativeTextInputs {
                    Group {
                        if model.showsPassword {
                            TextField("Mot de passe", text: $model.password)
                        } else {
                            SecureField("Mot de passe", text: $model.password)
                        }
                    }
                    .font(.mood(17))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .focused($focusedField, equals: .password)
                    .applyTextContentType(contentHint)
                    .onSubmit { submitFromKeyboard() }
                    .padding(.leading, LayoutMetrics.mobile(16))
                    .frame(height: LayoutMetrics.mobile(50))
                } else {
                    Text(model.password.isEmpty ? "Mot de passe" : String(repeating: "•", count: model.password.count))
                        .font(.mood(17))
                        .foregroundStyle(model.password.isEmpty ? MoodTheme.textMuted : MoodTheme.textPrimary)
                        .padding(.leading, LayoutMetrics.mobile(16))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: LayoutMetrics.mobile(50))
                }

                Button { model.showsPassword.toggle() } label: {
                    Image(systemName: model.showsPassword ? "eye.slash" : "eye")
                        .font(.mood(16, weight: .medium))
                        .foregroundStyle(MoodTheme.textSecondary)
                        .frame(width: LayoutMetrics.mobile(48), height: LayoutMetrics.mobile(50))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.showsPassword ? "Masquer le mot de passe" : "Afficher le mot de passe")
            }
            .background(MoodTheme.inputBg, in: Capsule())
            .overlay {
                Capsule().stroke(error == nil ? MoodTheme.composerBorder : MoodTheme.mentionBadge, lineWidth: error == nil ? 1 : 1.5)
            }

            if let error, !error.isEmpty { fieldErrorLabel(error) }
        }
    }

    private func fieldErrorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.mood(13, weight: .medium))
            .foregroundStyle(MoodTheme.mentionBadge)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }

    private func networkNotice(_ message: String) -> some View {
        MoodNotice(title: "La connexion a été interrompue", detail: message,
            symbol: "wifi.exclamationmark", actionTitle: "Réessayer",
            action: { Task { await model.submit() } }, busy: model.isBusy)

    }

    private var primaryButton: some View {
        Button {
            Task { await model.submit() }
        } label: {
            HStack(spacing: LayoutMetrics.mobile(10)) {
                if model.isBusy {
                    if usesNativeProgressIndicator {
                        ProgressView().tint(MoodTheme.mobileIndicator)
                    } else {
                        Circle()
                            .trim(from: 0.08, to: 0.74)
                            .stroke(MoodTheme.mobileIndicator, style: StrokeStyle(lineWidth: LayoutMetrics.mobile(2), lineCap: .round))
                            .frame(width: LayoutMetrics.mobile(16), height: LayoutMetrics.mobile(16))
                    }
                }
                Text(buttonTitle)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
        .buttonStyle(MobilePrimaryButtonStyle())
        .frame(minHeight: LayoutMetrics.mobile(50))
        .disabled(!model.canContinue || model.isBusy)
        .accessibilityHint(model.isBusy ? "Patiente un instant" : "Continue vers l’étape suivante")
    }

    private var resendCodeButton: some View {
        Button {
            Task { await model.resendCode() }
        } label: {
            HStack(spacing: LayoutMetrics.mobile(8)) {
                if model.isResendingCode { ProgressView().controlSize(.small) }
                Text("Renvoyer le code")
            }
            .font(.mood(15, weight: .medium))
            .foregroundStyle(MoodTheme.brandAccent)
            .frame(minHeight: LayoutMetrics.mobile(44))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isResendingCode)
        .accessibilityHint("Envoie un nouveau code à ton adresse e-mail")
    }

    private var showsPrimaryButton: Bool { true }

    private var canSkipCurrentStep: Bool {
        // Notifications keep their skip inside the card, like Discord: no second one in the corner.
        [.displayName, .server, .friends, .avatar].contains(model.step)
    }

    private var showsBackButton: Bool {
        [.email, .account, .confirmation, .username, .trust, .server, .signIn].contains(model.step)
    }

    private var buttonTitle: String {
        switch model.step {
        case .email: "Continuer"
        case .account: "Créer mon compte"
        case .confirmation: "Confirmer"
        case .displayName, .username: "Continuer"
        case .trust: "Continuer"
        case .server: model.isCreatingServer ? "Créer mon serveur" : "Rejoindre"
        case .notifications: "Autoriser"
        case .friends: "Trouver"
        case .avatar: "Suivant"
        case .signIn: "Connexion"
        case .welcome: "Continuer"
        }
    }

    private var contentTopSpacing: CGFloat {
        switch model.step {
        case .email: 41
        case .confirmation: 22
        case .displayName, .account, .username: 21
        case .avatar: 8
        case .trust, .server, .friends: 26
        case .signIn: 24
        default: 20
        }
    }

    private var buttonTopSpacing: CGFloat {
        switch model.step {
        case .email: 28
        case .confirmation: 11
        case .account: model.password.isEmpty ? 29 : 37
        case .displayName, .username: 22
        case .trust: 24
        case .server: 24
        case .friends: 28
        case .signIn: 24
        default: 22
        }
    }

    private var subtitle: String? {
        switch model.step {
        case .welcome: nil
        case .email: "On t’enverra un code pour confirmer ton e-mail."
        case .account, .username: nil
        case .confirmation: "Code envoyé à \(model.email)."
        case .displayName: nil
        case .trust: nil
        case .server: "Rejoins un serveur ou crée le tien."
        case .notifications: nil
        case .friends: "Ajoute quelqu’un avec son nom d’utilisateur Mood."
        case .avatar: "Choisis une photo ou un emoji pour ton profil."
        case .signIn: "Nous sommes si heureux de te revoir !"
        }
    }

    private var passwordFieldError: String? {
        model.fieldError
    }

    private func submitFromKeyboard() {
        if model.canContinue { Task { await model.submit() } }
    }
}

struct OnboardingHomeEmptyState: View {
    var onAddFriends: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 20

    var body: some View {
        VStack(spacing: LayoutMetrics.mobile(0)) {
            Spacer(minLength: LayoutMetrics.mobile(16))
            MoodInfinitySymbol(size: LayoutMetrics.mobile(118))
                .frame(width: LayoutMetrics.mobile(172), height: LayoutMetrics.mobile(172))
                .background(MoodTheme.inputBg, in: Circle())
                .accessibilityHidden(true)

            Text("Tes messages commencent ici")
                .font(.mood(titleSize, weight: .bold))
                .foregroundStyle(MoodTheme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, LayoutMetrics.mobile(20))
                .accessibilityAddTraits(.isHeader)

            Text("Retrouve ici tes conversations privées. Ajoute tes amis avec leur nom Mood pour commencer.")
                .font(.mood(16))
                .foregroundStyle(MoodTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, LayoutMetrics.mobile(10))

            Button(action: onAddFriends) {
                Text("Ajouter des amis")
            }
            .buttonStyle(MobilePrimaryButtonStyle())
            .padding(.top, LayoutMetrics.mobile(24))

            Spacer(minLength: LayoutMetrics.mobile(16))
        }
        .padding(.horizontal, LayoutMetrics.mobile(16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(MoodTheme.textPrimary)
    }
}

private enum InputKind {
    case email
    case username
    case numeric
    case text

    var accessibilityHint: String {
        switch self {
        case .email: "Entre une adresse e-mail valide."
        case .username: "2 à 32 caractères : lettres minuscules, chiffres, point ou souligné."
        case .numeric: "Entre les 6 chiffres reçus par e-mail."
        case .text: ""
        }
    }
}

private enum ContentHint {
    case email
    case username
    case oneTimeCode
    case password
    case newPassword
}

private extension View {
    @ViewBuilder
    func onboardingInputTraits(_ kind: InputKind) -> some View {
        #if os(iOS)
        switch kind {
        case .email:
            self.keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
        case .username:
            self.keyboardType(.asciiCapable).textInputAutocapitalization(.never).autocorrectionDisabled()
        case .numeric:
            self.keyboardType(.numberPad).textInputAutocapitalization(.never).autocorrectionDisabled()
        case .text:
            self.textInputAutocapitalization(.sentences)
        }
        #else
        self.autocorrectionDisabled()
        #endif
    }

    @ViewBuilder
    func applyTextContentType(_ hint: ContentHint?) -> some View {
        #if os(iOS)
        switch hint {
        case .email: self.textContentType(.emailAddress)
        case .username: self.textContentType(.username)
        case .oneTimeCode: self.textContentType(.oneTimeCode)
        case .password: self.textContentType(.password)
        case .newPassword: self.textContentType(.newPassword)
        case nil: self
        }
        #else
        self
        #endif
    }
}

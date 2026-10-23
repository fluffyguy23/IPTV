import AppKit

/// Shown when no session is active: manage saved profiles and connect. Handles
/// create / edit / delete / connect, with inline validation and error display.
final class ConnectionViewController: NSViewController {
    private let scroll = NSScrollView()
    private let formStack = NSStackView()
    private let profilesStack = NSStackView()

    private let nameField = ConnectionViewController.makeField(placeholder: "e.g. Living Room")
    private let urlField = ConnectionViewController.makeField(placeholder: "http://server-address:port")
    private let userField = ConnectionViewController.makeField(placeholder: "Username")
    private let passField = ConnectionViewController.makeSecureField(placeholder: "Password")
    private let xmltvField = ConnectionViewController.makeField(placeholder: "Optional XMLTV EPG URL")
    private let formatControl = NSSegmentedControl(labels: ["TS", "M3U8"], trackingMode: .selectOne, target: nil, action: nil)

    private let errorLabel = makeLabel(font: Theme.Font.medium(12.5), color: Theme.negative, align: .left, lines: 3)
    private let connectButton = PillButton(title: "Save & Connect")
    private let saveButton = PillButton(title: "Save Only", filled: false)
    private let spinner = NSProgressIndicator()
    private let formTitle = makeLabel("Add a Profile", font: Theme.Font.semibold(16))

    private var editingProfile: Profile?

    override func loadView() {
        view = NSView()
        view.fill(Theme.background)
        build()
        reloadProfiles()
    }

    // MARK: Build

    private func build() {
        // Centered scroll container
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.automaticallyAdjustsContentInsets = false
        view.addSubview(scroll)

        let content = NSStackView()
        content.orientation = .vertical
        content.spacing = 24
        content.alignment = .centerX
        content.translatesAutoresizingMaskIntoConstraints = false
        let flipped = FlippedView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(content)
        scroll.documentView = flipped

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            flipped.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            content.topAnchor.constraint(equalTo: flipped.topAnchor, constant: 48),
            content.bottomAnchor.constraint(equalTo: flipped.bottomAnchor, constant: -48),
            content.centerXAnchor.constraint(equalTo: flipped.centerXAnchor),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 560)
        ])

        // Header
        let brand = makeLabel("IPTVXtremePlayer", font: Theme.Font.bold(26), color: Theme.textPrimary, align: .center)
        let tagline = makeLabel("Connect to your Xtream Codes service", font: Theme.Font.regular(14), color: Theme.textSecondary, align: .center)
        content.addArrangedSubview(brand)
        content.addArrangedSubview(tagline)
        content.setCustomSpacing(6, after: brand)

        // Offline Downloads work without signing in (e.g. no internet).
        let offline = PillButton(title: "Offline Downloads (\(DownloadManager.shared.completedCount))", filled: false)
        offline.onClick = { DownloadsWindowController.show() }
        content.addArrangedSubview(offline)

        // Saved profiles
        profilesStack.orientation = .vertical
        profilesStack.spacing = 10
        profilesStack.alignment = .leading
        profilesStack.translatesAutoresizingMaskIntoConstraints = false
        let profilesCard = card(containing: profilesStack, title: "Saved Profiles")
        content.addArrangedSubview(profilesCard)
        profilesCard.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        // Form
        formStack.orientation = .vertical
        formStack.spacing = 14
        formStack.alignment = .leading
        formStack.translatesAutoresizingMaskIntoConstraints = false
        buildForm()
        let formCard = card(containing: formStack, titleView: formTitle)
        content.addArrangedSubview(formCard)
        formCard.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }

    private func buildForm() {
        formatControl.selectedSegment = 0
        formatControl.translatesAutoresizingMaskIntoConstraints = false

        formStack.addArrangedSubview(fieldRow("Profile Name", nameField))
        formStack.addArrangedSubview(fieldRow("Server URL", urlField))
        formStack.addArrangedSubview(fieldRow("Username", userField))
        formStack.addArrangedSubview(fieldRow("Password", passField))
        formStack.addArrangedSubview(fieldRow("Live Stream Format", formatControl))
        formStack.addArrangedSubview(fieldRow("XMLTV EPG (optional)", xmltvField))

        errorLabel.isHidden = true
        formStack.addArrangedSubview(errorLabel)

        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.controlSize = .small
        spinner.appearance = NSAppearance(named: .darkAqua)
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false

        connectButton.onClick = { [weak self] in self?.submit(connect: true) }
        saveButton.onClick = { [weak self] in self?.submit(connect: false) }

        let buttons = NSStackView(views: [connectButton, saveButton, spinner])
        buttons.spacing = 12
        buttons.alignment = .centerY
        formStack.addArrangedSubview(buttons)

        for f in [nameField, urlField, userField, passField, xmltvField] {
            f.widthAnchor.constraint(equalToConstant: 496).isActive = true
        }
        formatControl.widthAnchor.constraint(equalToConstant: 200).isActive = true
    }

    // MARK: Profiles list

    private func reloadProfiles() {
        profilesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let profiles = ProfileStore.shared.profiles
        if profiles.isEmpty {
            let empty = makeLabel("No profiles yet. Add one below to get started.",
                                  font: Theme.Font.regular(13), color: Theme.textTertiary)
            profilesStack.addArrangedSubview(empty)
            return
        }
        for profile in profiles {
            let row = ProfileRow(profile: profile)
            row.onConnect = { [weak self] in self?.connect(profile) }
            row.onEdit = { [weak self] in self?.beginEdit(profile) }
            row.onDelete = { [weak self] in self?.delete(profile) }
            profilesStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: profilesStack.widthAnchor).isActive = true
        }
    }

    // MARK: Actions

    private func beginEdit(_ profile: Profile) {
        editingProfile = profile
        formTitle.stringValue = "Edit Profile"
        nameField.stringValue = profile.name
        urlField.stringValue = profile.baseURL
        userField.stringValue = profile.username
        passField.stringValue = ProfileStore.shared.password(for: profile) ?? ""
        xmltvField.stringValue = profile.xmltvURL ?? ""
        formatControl.selectedSegment = (profile.liveFormat == "m3u8") ? 1 : 0
        (saveButton.subviews.compactMap { $0 as? NSTextField }.first)?.stringValue = "Save Changes"
    }

    private func delete(_ profile: Profile) {
        let alert = NSAlert()
        alert.messageText = "Delete \"\(profile.name)\"?"
        alert.informativeText = "This removes the profile and its stored password from the Keychain."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            ProfileStore.shared.delete(profile)
            if editingProfile?.id == profile.id { resetForm() }
            reloadProfiles()
        }
    }

    private func resetForm() {
        editingProfile = nil
        formTitle.stringValue = "Add a Profile"
        [nameField, urlField, userField, passField, xmltvField].forEach { $0.stringValue = "" }
        formatControl.selectedSegment = 0
        errorLabel.isHidden = true
    }

    private func submit(connect: Bool) {
        errorLabel.isHidden = true
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let base = URLNormalizer.normalizeBase(urlField.stringValue) else {
            return showError("Please enter a valid server URL, like http://example.com:8080")
        }
        let user = userField.stringValue.trimmingCharacters(in: .whitespaces)
        let pass = passField.stringValue
        guard !user.isEmpty else { return showError("Username is required.") }
        let existingPassword = editingProfile.flatMap { ProfileStore.shared.password(for: $0) }
        guard !pass.isEmpty || existingPassword != nil else { return showError("Password is required.") }

        let profile = Profile(
            id: editingProfile?.id ?? UUID(),
            name: name.isEmpty ? (URL(string: base)?.host ?? "Profile") : name,
            baseURL: base,
            username: user,
            liveFormat: formatControl.selectedSegment == 1 ? "m3u8" : "ts",
            xmltvURL: xmltvField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ? nil : xmltvField.stringValue,
            createdAt: editingProfile?.createdAt ?? Date()
        )
        ProfileStore.shared.save(profile, password: pass.isEmpty ? nil : pass)
        reloadProfiles()

        if connect {
            self.connect(profile)
        } else {
            resetForm()
        }
    }

    private func connect(_ profile: Profile) {
        setBusy(true)
        errorLabel.isHidden = true
        Task { @MainActor in
            do {
                try await AppState.shared.connect(profile: profile)
                // Session change notification swaps the whole view; nothing else to do.
            } catch {
                setBusy(false)
                let message = (error as? XtreamError)?.errorDescription ?? error.localizedDescription
                showError(message)
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        spinner.isHidden = !busy
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
    }

    // MARK: Builders

    private func fieldRow(_ label: String, _ field: NSView) -> NSView {
        let caption = makeLabel(label, font: Theme.Font.medium(12), color: Theme.textSecondary)
        let stack = NSStackView(views: [caption, field])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        return stack
    }

    private func card(containing inner: NSView, title: String? = nil, titleView: NSView? = nil) -> NSView {
        let box = NSView()
        box.fill(Theme.surface, corner: 14)
        box.wantsLayer = true
        box.layer?.borderWidth = 1
        box.layer?.borderColor = Theme.border.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let titleView = titleView {
            stack.addArrangedSubview(titleView)
        } else if let title = title {
            stack.addArrangedSubview(makeLabel(title, font: Theme.Font.semibold(16)))
        }
        stack.addArrangedSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        stack.pinEdges(to: box, insets: NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20))
        inner.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        inner.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        return box
    }

    static func makeField(placeholder: String) -> NSTextField {
        let f = NSTextField()
        styleTextField(f, placeholder: placeholder)
        return f
    }
    static func makeSecureField(placeholder: String) -> NSSecureTextField {
        let f = NSSecureTextField()
        styleTextField(f, placeholder: placeholder)
        return f
    }
    private static func styleTextField(_ f: NSTextField, placeholder: String) {
        f.placeholderString = placeholder
        f.font = Theme.Font.regular(13.5)
        f.textColor = Theme.textPrimary
        f.drawsBackground = true
        f.backgroundColor = Theme.surfaceRaised
        f.bezelStyle = .roundedBezel
        f.focusRingType = .none
        f.translatesAutoresizingMaskIntoConstraints = false
        f.heightAnchor.constraint(equalToConstant: 32).isActive = true
    }
}

/// NSScrollView document views must be flipped for top-down layout.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A saved-profile row with connect / edit / delete.
final class ProfileRow: NSView {
    var onConnect: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    init(profile: Profile) {
        super.init(frame: .zero)
        fill(Theme.surfaceRaised, corner: 10)
        translatesAutoresizingMaskIntoConstraints = false

        let name = makeLabel(profile.name, font: Theme.Font.semibold(14))
        let host = makeLabel(URL(string: profile.baseURL)?.host ?? profile.baseURL,
                             font: Theme.Font.regular(11.5), color: Theme.textTertiary)
        let info = NSStackView(views: [name, host])
        info.orientation = .vertical
        info.spacing = 2
        info.alignment = .leading
        info.translatesAutoresizingMaskIntoConstraints = false

        let connect = PillButton(title: "Connect")
        connect.onClick = { [weak self] in self?.onConnect?() }
        let edit = IconButton(symbol: "pencil", pointSize: 13, tint: Theme.textSecondary)
        edit.target = self; edit.action = #selector(editTapped)
        let del = IconButton(symbol: "trash", pointSize: 13, tint: Theme.textSecondary, hover: Theme.negative)
        del.target = self; del.action = #selector(deleteTapped)

        let actions = NSStackView(views: [connect, edit, del])
        actions.spacing = 10
        actions.alignment = .centerY
        actions.translatesAutoresizingMaskIntoConstraints = false

        addSubview(info)
        addSubview(actions)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            info.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            info.centerYAnchor.constraint(equalTo: centerYAnchor),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            actions.centerYAnchor.constraint(equalTo: centerYAnchor),
            edit.widthAnchor.constraint(equalToConstant: 22),
            del.widthAnchor.constraint(equalToConstant: 22)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func editTapped() { onEdit?() }
    @objc private func deleteTapped() { onDelete?() }
}

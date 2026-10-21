#if os(iOS)
import DriverLogCore
import SwiftUI

struct BrandHeader: View {
    static let logo: UIImage? = Bundle.module.path(forResource: "logo", ofType: "png").flatMap(UIImage.init(contentsOfFile:))

    var body: some View {
        HStack(spacing: 14) {
            if let logo = BrandHeader.logo { Image(uiImage: logo).resizable().scaledToFit().frame(width: 64) }
            VStack(alignment: .leading, spacing: 2) {
                Text("FIRST DUE MOVERS").font(.caption.weight(.bold)).tracking(1.6).foregroundStyle(Brand.red)
                Text("Driver’s log").font(.system(size: 30, weight: .bold)).foregroundStyle(Brand.ink)
            }
            Spacer()
        }
    }
}

struct SignInView: View {
    @EnvironmentObject var model: AppModel
    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error = ""
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BrandHeader()
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Eyebrow("Private logbook", color: Brand.onDark)
                        Spacer()
                        Label("Signed out", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .overlay(Capsule().stroke(Brand.cardLine))
                    }
                    Text(creating ? "Create your account" : "Sign in").font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                    Text(creating ? "One account keeps your log on the web and in the app." : "You stay signed in on this phone.")
                        .foregroundStyle(Brand.onDark)
                    VStack(spacing: 14) {
                        TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().field("Email", labelColor: Brand.onDark)
                        SecureField("Password", text: $password).textContentType(creating ? .newPassword : .password).field("Password", labelColor: Brand.onDark)
                    }
                    .environment(\.colorScheme, .light)
                    if !note.isEmpty {
                        Text(note).font(.subheadline).foregroundStyle(Color(red: 0.79, green: 0.94, blue: 0.85))
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(red: 0.13, green: 0.25, blue: 0.18), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if !error.isEmpty { Text(error).font(.subheadline).foregroundStyle(Color(red: 1, green: 0.61, blue: 0.58)) }
                    Button(busy ? "One moment…" : creating ? "Create account" : "Sign in") { Task { await submit() } }
                        .buttonStyle(PrimaryButtonStyle(color: Brand.red))
                        .disabled(busy || email.isEmpty || password.count < (creating ? 8 : 1))
                    if model.canUseGoogle {
                        HStack { Rectangle().fill(Brand.cardLine).frame(height: 1); Text("or").font(.footnote).foregroundStyle(Brand.onDark); Rectangle().fill(Brand.cardLine).frame(height: 1) }
                        Button { Task { await google() } } label: {
                            HStack(spacing: 10) {
                                Text("G").font(.title3.weight(.heavy)).foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                                Text("Continue with Google").font(.headline)
                            }
                            .foregroundStyle(Brand.card)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(busy)
                    }
                    Button(creating ? "Already have an account? Sign in" : "First time? Create an account") {
                        creating.toggle(); error = ""; note = ""
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color(red: 1, green: 0.61, blue: 0.58))
                    .frame(maxWidth: .infinity)
                }
                .padding(24)
                .background(Brand.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .top) { UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16).fill(Brand.brightRed).frame(height: 5) }
            }
            .padding(20)
        }
        .background(Brand.page.ignoresSafeArea())
    }

    private func submit() async {
        busy = true; error = ""; note = ""
        defer { busy = false }
        do {
            let trimmed = email.trimmingCharacters(in: .whitespaces)
            if creating {
                if try await model.backend.signUp(email: trimmed, password: password) {
                    creating = false
                    note = "Account created. Open the confirmation link in your email, then sign in here."
                    return
                }
            } else {
                try await model.backend.signIn(email: trimmed, password: password)
            }
            await model.signedIn()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func google() async {
        busy = true; error = ""
        defer { busy = false }
        do {
            try await model.backend.signInWithGoogle()
            await model.signedIn()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        NavigationStack {
            Group {
                if appStore.session.userId == nil {
                    WelcomeView()
                } else if appStore.session.petId == nil {
                    PetSetupView()
                } else if !appStore.session.setupComplete {
                    DemoVideoUploadView()
                } else {
                    ChatView()
                }
            }
            .navigationTitle("PetPal Demo")
        }
    }
}

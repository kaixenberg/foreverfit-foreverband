import SwiftUI

public struct MedicalEmergencyView: View {
    @ObservedObject var dataStore: HealthDataStore

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var hotline: String = "112"
    @State private var showSavedToast: Bool = false

    public init(dataStore: HealthDataStore) {
        self.dataStore = dataStore
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Your emergency contact is called automatically with a spoken health summary after an unacknowledged fall, following the primary emergency services call.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Emergency Contact")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Contact Name")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.6))
                        TextField("Name", text: $name)
                            .foregroundStyle(Color.white)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Phone Number")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.6))
                        TextField("+91 98765 43210", text: $phone)
                            .keyboardType(.phonePad)
                            .foregroundStyle(Color.white)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Local Emergency Services")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hotline Number")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.6))
                        TextField("112", text: $hotline)
                            .keyboardType(.phonePad)
                            .foregroundStyle(Color.white)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                }

                Button {
                    save()
                } label: {
                    Text("Save Emergency Info")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LiquidGlassTheme.neonCyan)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.top, 10)
            }
            .padding(16)
        }
        .navigationTitle("Medical Emergency")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
        .onAppear {
            self.name = dataStore.emergencyContactName
            self.phone = dataStore.emergencyContactPhone
            self.hotline = dataStore.customEmergencyNumber
        }
        .overlay(alignment: .top) {
            if showSavedToast {
                Text("Emergency Contact Saved")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(LiquidGlassTheme.emeraldGreen))
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func save() {
        dataStore.saveEmergencyContact(name: name, phone: phone, customNumber: hotline)
        withAnimation {
            showSavedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showSavedToast = false
            }
        }
    }
}

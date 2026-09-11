import SwiftUI

public struct EmergencyContactsView: View {
    @ObservedObject var dataStore: HealthDataStore
    @State private var showingAddContactSheet = false

    public var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground(mood: .normal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Designated contacts receive automated SOS SMS notifications with your GPS coordinates and telemetry scripts.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.horizontal)

                        ForEach(dataStore.userProfile.emergencyContacts) { contact in
                            HStack {
                                ZStack {
                                    Circle()
                                        .fill(LiquidGlassTheme.alertCrimson.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(LiquidGlassTheme.alertCrimson)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(contact.name)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(Color.white)
                                        if contact.isPrimary {
                                            Text("PRIMARY")
                                                .font(.system(size: 9, weight: .black))
                                                .foregroundStyle(LiquidGlassTheme.emeraldGreen)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(LiquidGlassTheme.emeraldGreen.opacity(0.15)))
                                        }
                                    }

                                    Text("\(contact.relationship) • \(contact.phone)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.white.opacity(0.6))
                                }

                                Spacer()
                            }
                            .padding()
                            .liquidGlass(cornerRadius: 18)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Emergency Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddContactSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(LiquidGlassTheme.neonCyan)
                    }
                }
            }
            .sheet(isPresented: $showingAddContactSheet) {
                AddContactSheet(dataStore: dataStore)
            }
        }
    }
}

public struct AddContactSheet: View {
    @ObservedObject var dataStore: HealthDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var relationship: String = "Guardian"
    @State private var isPrimary: Bool = false

    public var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground(mood: .normal)

                VStack(spacing: 16) {
                    TextField("Contact Name", text: $name)
                        .textFieldStyle(GlassTextFieldStyle())
                    TextField("Phone Number (+91...)", text: $phone)
                        .keyboardType(.phonePad)
                        .textFieldStyle(GlassTextFieldStyle())
                    TextField("Relationship (e.g. Physician)", text: $relationship)
                        .textFieldStyle(GlassTextFieldStyle())

                    Toggle("Set as Primary SOS Contact", isOn: $isPrimary)
                        .tint(LiquidGlassTheme.emeraldGreen)
                        .foregroundStyle(Color.white)

                    Button {
                        guard !name.isEmpty, !phone.isEmpty else { return }
                        let newContact = EmergencyContact(name: name, phone: phone, relationship: relationship, isPrimary: isPrimary)
                        var list = dataStore.userProfile.emergencyContacts
                        if isPrimary {
                            for i in 0..<list.count { list[i].isPrimary = false }
                        }
                        list.append(newContact)
                        dataStore.userProfile.emergencyContacts = list
                        dataStore.saveUserProfile(dataStore.userProfile)
                        dismiss()
                    } label: {
                        Text("Add Contact")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.white))
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("New Contact")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
        }
    }
}

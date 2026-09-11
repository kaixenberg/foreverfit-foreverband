import SwiftUI

public struct ProfileMedicalView: View {
    @ObservedObject var dataStore: HealthDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var dateOfBirth: Date = Date()
    @State private var sex: String = "Male"
    @State private var weightStr: String = ""
    @State private var heightStr: String = ""
    @State private var bloodType: String = "O+"
    @State private var allergies: String = ""
    @State private var conditions: String = ""
    @State private var notes: String = ""
    @State private var organDonor: Bool = true
    @State private var showSavedToast: Bool = false

    private let sexOptions = ["Male", "Female", "Other", "Prefer not to say"]
    private let bloodTypeOptions = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-", "Unknown"]

    public init(dataStore: HealthDataStore) {
        self.dataStore = dataStore
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                fieldCard(title: "Full Name") {
                    TextField("Name", text: $name)
                        .foregroundStyle(Color.white)
                }

                fieldCard(title: "Date of Birth") {
                    DatePicker("", selection: $dateOfBirth, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .colorScheme(.dark)
                }

                fieldCard(title: "Biological Sex") {
                    Picker("Sex", selection: $sex) {
                        ForEach(sexOptions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(spacing: 12) {
                    fieldCard(title: "Weight (kg)") {
                        TextField("70.0", text: $weightStr)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(Color.white)
                    }

                    fieldCard(title: "Height (cm)") {
                        TextField("175.0", text: $heightStr)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(Color.white)
                    }
                }

                fieldCard(title: "Blood Type") {
                    Picker("Blood Type", selection: $bloodType) {
                        ForEach(bloodTypeOptions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(LiquidGlassTheme.neonCyan)
                }

                fieldCard(title: "Allergies") {
                    TextField("e.g. Penicillin, Peanuts (or None)", text: $allergies)
                        .foregroundStyle(Color.white)
                }

                fieldCard(title: "Medical Conditions") {
                    TextField("e.g. Asthma, Hypertension (or None)", text: $conditions)
                        .foregroundStyle(Color.white)
                }

                fieldCard(title: "Emergency Notes") {
                    TextField("Notes for emergency services", text: $notes)
                        .foregroundStyle(Color.white)
                }

                Toggle(isOn: $organDonor) {
                    Text("Organ Donor")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))

                Button {
                    save()
                } label: {
                    Text("Save Profile & Medical ID")
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
        .navigationTitle("Profile & Medical")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
        .onAppear {
            loadInitial()
        }
        .overlay(alignment: .top) {
            if showSavedToast {
                Text("Profile Saved")
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

    private func fieldCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }

    private func loadInitial() {
        self.name = dataStore.userProfile.name
        self.dateOfBirth = dataStore.userProfile.dateOfBirth ?? Date()
        self.sex = dataStore.userProfile.sex
        if let w = dataStore.latestWeightKg { self.weightStr = String(format: "%.1f", w) }
        if let h = dataStore.latestHeightCm { self.heightStr = String(format: "%.1f", h) }
        self.bloodType = dataStore.medicalId.bloodType.isEmpty ? "O+" : dataStore.medicalId.bloodType
        self.allergies = dataStore.medicalId.allergies
        self.conditions = dataStore.medicalId.conditions
        self.notes = dataStore.medicalId.notes
        self.organDonor = dataStore.medicalId.organDonor
    }

    private func save() {
        var prof = dataStore.userProfile
        prof.name = name
        prof.dateOfBirth = dateOfBirth
        prof.sex = sex
        dataStore.saveUserProfile(prof)

        var med = dataStore.medicalId
        med.bloodType = bloodType
        med.allergies = allergies
        med.conditions = conditions
        med.notes = notes
        med.organDonor = organDonor
        dataStore.saveMedicalId(med)

        if let w = Double(weightStr) { dataStore.addWeightKg(w) }
        if let h = Double(heightStr) { dataStore.addHeightCm(h) }

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

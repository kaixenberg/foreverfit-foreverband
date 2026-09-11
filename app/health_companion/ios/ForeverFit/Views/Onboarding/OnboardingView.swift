import SwiftUI

public struct OnboardingView: View {
    @ObservedObject var dataStore: HealthDataStore
    @Binding var onboardingCompleted: Bool

    @State private var currentPage = 0
    @State private var name: String = ""
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var sex: String = "Male"
    @State private var weightStr: String = "70.0"
    @State private var heightStr: String = "175.0"
    @State private var bloodType: String = "O+"
    @State private var allergies: String = ""
    @State private var conditions: String = ""
    @State private var notes: String = ""

    private let sexOptions = ["Male", "Female", "Other", "Prefer not to say"]
    private let bloodTypeOptions = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-", "Unknown"]

    public init(dataStore: HealthDataStore, onboardingCompleted: Binding<Bool>) {
        self.dataStore = dataStore
        self._onboardingCompleted = onboardingCompleted
    }

    public var body: some View {
        ZStack {
            MeshGradientBackground()

            VStack(spacing: 16) {
                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<3) { idx in
                        Circle()
                            .fill(currentPage == idx ? LiquidGlassTheme.neonCyan : Color.white.opacity(0.25))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 20)

                TabView(selection: $currentPage) {
                    // Page 1: Units
                    unitsPage
                        .tag(0)

                    // Page 2: Permissions
                    permissionsPage
                        .tag(1)

                    // Page 3: Profile & Medical
                    profileMedicalPage
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
    }

    // MARK: - Page 1: Units

    private var unitsPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "ruler.fill")
                .font(.system(size: 60))
                .foregroundStyle(LiquidGlassTheme.neonCyan)

            VStack(spacing: 8) {
                Text("Select Units")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                Text("Choose how body metrics, temperature, and speeds are displayed.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                ForEach(UnitSystem.allCases, id: \.self) { sys in
                    Button {
                        dataStore.setUnitSystem(sys)
                    } label: {
                        HStack {
                            Text(sys.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.white)
                            Spacer()
                            if dataStore.unitSystem == sys {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(LiquidGlassTheme.neonCyan)
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(dataStore.unitSystem == sys ? LiquidGlassTheme.neonCyan : Color.clear, lineWidth: 1.5)
                        )
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                withAnimation { currentPage = 1 }
            } label: {
                Text("Continue")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LiquidGlassTheme.neonCyan)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Page 2: Permissions

    private var permissionsPage: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Permissions & Privacy")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                Text("ForeverFit works fully offline on your iPhone. We only use device hardware sensors for safety features.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 10)

            ScrollView {
                VStack(spacing: 10) {
                    permissionRow(icon: "antenna.radiowaves.left.and.right", title: "Bluetooth", desc: "To connect and receive vitals from your ForeverBand wearable.")
                    permissionRow(icon: "location.fill", title: "Location", desc: "For real-time disaster hazard mapping and emergency SMS coordinates.")
                    permissionRow(icon: "figure.walk", title: "Motion & Fitness", desc: "For 20Hz phone-only fall detection and daily pedometer tracking.")
                    permissionRow(icon: "bell.badge.fill", title: "Notifications", desc: "For vital alerts, hazard warnings, and emergency countdowns.")
                    permissionRow(icon: "mic.fill", title: "Microphone", desc: "Optional — for voice dictation to the offline Gemma 4 E2B AI assistant.")
                    permissionRow(icon: "camera.fill", title: "Camera & Photos", desc: "Optional — for visual analysis in the AI health companion.")
                }
                .padding(.horizontal, 20)
            }

            Button {
                withAnimation { currentPage = 2 }
            } label: {
                Text("Continue")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LiquidGlassTheme.neonCyan)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func permissionRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(LiquidGlassTheme.neonCyan)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    }

    // MARK: - Page 3: Profile & Medical

    private var profileMedicalPage: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Profile & Medical ID")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)
                Text("Used for calibrated health metrics and spoken in emergency calls.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.top, 10)

            ScrollView {
                VStack(spacing: 12) {
                    fieldCard(title: "Full Name") {
                        TextField("Your Name", text: $name)
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
                }
                .padding(.horizontal, 20)
            }

            Button {
                saveAndFinish()
            } label: {
                Text("Get Started")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LiquidGlassTheme.emeraldGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
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

    private func saveAndFinish() {
        var profile = dataStore.userProfile
        profile.name = name.isEmpty ? "User" : name
        profile.dateOfBirth = dateOfBirth
        profile.sex = sex
        profile.onboardingCompleted = true
        dataStore.saveUserProfile(profile)

        var med = dataStore.medicalId
        med.bloodType = bloodType
        med.allergies = allergies
        med.conditions = conditions
        med.notes = notes
        dataStore.saveMedicalId(med)

        if let w = Double(weightStr) {
            dataStore.addWeightKg(w)
        }
        if let h = Double(heightStr) {
            dataStore.addHeightCm(h)
        }

        onboardingCompleted = true
    }
}

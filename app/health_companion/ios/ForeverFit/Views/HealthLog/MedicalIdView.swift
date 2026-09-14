import SwiftUI

public struct MedicalIdView: View {
    @ObservedObject var dataStore: HealthDataStore
    @State private var isEditing = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LiquidGlassTheme.alertCrimson.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "staroflife.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(LiquidGlassTheme.alertCrimson)
                }

                Text("EMERGENCY MEDICAL ID")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.6))

                Spacer()

                Button(isEditing ? "Done" : "Edit") {
                    isEditing.toggle()
                    if !isEditing {
                        dataStore.saveMedicalId(dataStore.medicalId)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LiquidGlassTheme.neonCyan)
            }

            if isEditing {
                editingForm
            } else {
                displayDetails
            }
        }
        .padding()
        .liquidGlass()
    }

    private var displayDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Blood Type")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.5))
                    Text(dataStore.medicalId.bloodType)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(LiquidGlassTheme.alertCrimson)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Organ Donor")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.5))
                    Text(dataStore.medicalId.organDonor ? "Yes" : "No")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }

            Divider().background(Color.white.opacity(0.1))

            detailRow(title: "Allergies", val: dataStore.medicalId.allergies)
            detailRow(title: "Conditions", val: dataStore.medicalId.conditions)
            detailRow(title: "Medications", val: dataStore.medicalId.medications)
        }
    }

    private func detailRow(title: String, val: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            Text(val.isEmpty ? "None reported" : val)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }

    private var editingForm: some View {
        VStack(spacing: 8) {
            TextField("Blood Type (e.g. O+)", text: $dataStore.medicalId.bloodType)
                .textFieldStyle(GlassTextFieldStyle())
            TextField("Allergies (e.g. Penicillin)", text: $dataStore.medicalId.allergies)
                .textFieldStyle(GlassTextFieldStyle())
            TextField("Conditions (e.g. Hypertension)", text: $dataStore.medicalId.conditions)
                .textFieldStyle(GlassTextFieldStyle())
            TextField("Medications (e.g. Metformin)", text: $dataStore.medicalId.medications)
                .textFieldStyle(GlassTextFieldStyle())
        }
    }
}

public struct GlassTextFieldStyle: TextFieldStyle {
    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(10)
            .background(Color.white.opacity(0.08))
            .cornerRadius(10)
            .foregroundStyle(Color.white)
            .font(.system(size: 13))
    }
}

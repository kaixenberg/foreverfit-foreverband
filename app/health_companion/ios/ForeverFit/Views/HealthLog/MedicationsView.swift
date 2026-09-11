import SwiftUI

public struct MedicationsView: View {
    @ObservedObject var dataStore: HealthDataStore
    @State private var showingAddMedication: Bool = false
    @State private var newName: String = ""
    @State private var newDosage: String = ""
    @State private var newFrequency: String = ""

    public init(dataStore: HealthDataStore) {
        self.dataStore = dataStore
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Adherence Banner
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(LiquidGlassTheme.emeraldGreen)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Doses Taken Today: \(dataStore.dosesTakenToday)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text("Consistent medication adherence supports recovery.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))

                // Medications List
                if dataStore.medications.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "pills")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.white.opacity(0.3))
                        Text("No medications added yet.\nTap 'Add Medication' below.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 10) {
                        ForEach(dataStore.medications) { med in
                            HStack(spacing: 14) {
                                Image(systemName: "pill.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(LiquidGlassTheme.neonCyan)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(med.name)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Color.white)
                                    Text("\(med.dosage) — \(med.frequency)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.white.opacity(0.7))
                                }

                                Spacer()

                                Button {
                                    dataStore.logMedicationDose(name: med.name)
                                } label: {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(LiquidGlassTheme.emeraldGreen)
                                        .frame(width: 32, height: 32)
                                        .background(LiquidGlassTheme.emeraldGreen.opacity(0.15))
                                        .clipShape(Circle())
                                }

                                Button {
                                    dataStore.removeMedication(id: med.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.white.opacity(0.5))
                                        .frame(width: 32, height: 32)
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                        }
                    }
                }

                Button {
                    showingAddMedication = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Medication")
                    }
                    .font(.system(size: 15, weight: .bold))
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
        .navigationTitle("Medications")
        .navigationBarTitleDisplayMode(.inline)
        .background(MeshGradientBackground())
        .sheet(isPresented: $showingAddMedication) {
            NavigationStack {
                VStack(spacing: 16) {
                    TextField("Name (e.g. Metformin)", text: $newName)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                        .foregroundStyle(Color.white)

                    TextField("Dosage (e.g. 500mg)", text: $newDosage)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                        .foregroundStyle(Color.white)

                    TextField("Frequency (e.g. Twice daily)", text: $newFrequency)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                        .foregroundStyle(Color.white)

                    Spacer()

                    Button("Save Medication") {
                        if !newName.isEmpty {
                            dataStore.addMedication(name: newName, dosage: newDosage, frequency: newFrequency)
                            newName = ""
                            newDosage = ""
                            newFrequency = ""
                            showingAddMedication = false
                        }
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LiquidGlassTheme.neonCyan)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(20)
                .navigationTitle("New Medication")
                .navigationBarTitleDisplayMode(.inline)
                .background(MeshGradientBackground())
            }
        }
    }
}

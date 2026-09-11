import SwiftUI

public struct AddBloodPressureSheet: View {
    @ObservedObject var dataStore: HealthDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var systolicText: String = "120"
    @State private var diastolicText: String = "80"

    public var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground(mood: .normal)

                VStack(spacing: 20) {
                    Text("Record Blood Pressure")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white)

                    HStack(spacing: 16) {
                        VStack {
                            Text("Systolic (mmHg)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.6))
                            TextField("120", text: $systolicText)
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .multilineTextAlignment(.center)
                                .keyboardType(.numberPad)
                                .textFieldStyle(GlassTextFieldStyle())
                        }

                        VStack {
                            Text("Diastolic (mmHg)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.6))
                            TextField("80", text: $diastolicText)
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .multilineTextAlignment(.center)
                                .keyboardType(.numberPad)
                                .textFieldStyle(GlassTextFieldStyle())
                        }
                    }
                    .padding()
                    .liquidGlass()

                    Button {
                        if let sys = Int(systolicText), let dia = Int(diastolicText) {
                            dataStore.addBloodPressure(systolic: sys, diastolic: dia)
                            dismiss()
                        }
                    } label: {
                        Text("Save Blood Pressure")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.white))
                    }

                    Spacer()
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
        }
    }
}

public struct AddBloodGlucoseSheet: View {
    @ObservedObject var dataStore: HealthDataStore
    @Environment(\.dismiss) private var dismiss

    @State private var glucoseText: String = "95"

    public var body: some View {
        NavigationStack {
            ZStack {
                MeshGradientBackground(mood: .normal)

                VStack(spacing: 20) {
                    Text("Record Blood Glucose")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white)

                    VStack {
                        Text("Blood Glucose (mg/dL)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.6))
                        TextField("95", text: $glucoseText)
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .multilineTextAlignment(.center)
                            .keyboardType(.numberPad)
                            .textFieldStyle(GlassTextFieldStyle())
                    }
                    .padding()
                    .liquidGlass()

                    Button {
                        if let val = Double(glucoseText) {
                            dataStore.addBloodGlucose(mgDl: val)
                            dismiss()
                        }
                    } label: {
                        Text("Save Glucose Reading")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color.white))
                    }

                    Spacer()
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
        }
    }
}

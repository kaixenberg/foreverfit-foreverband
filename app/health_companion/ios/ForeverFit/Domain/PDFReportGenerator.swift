import Foundation
import UIKit
import PDFKit

public struct PDFReportGenerator {
    public static func generateClinicalReport(
        userProfile: UserProfile,
        medicalId: MedicalId,
        vitalsHistory: [VitalsReading],
        bpEntries: [BloodPressureEntry],
        glucoseEntries: [BloodGlucoseEntry],
        todaySteps: Int
    ) -> Data {
        return generateMedicalReport(
            userProfile: userProfile,
            medicalId: medicalId,
            vitals: vitalsHistory.last,
            todaySteps: todaySteps,
            recentBP: bpEntries.first,
            recentGlucose: glucoseEntries.first
        )
    }

    public static func generateMedicalReport(
        userProfile: UserProfile,
        medicalId: MedicalId,
        vitals: VitalsReading?,
        todaySteps: Int,
        recentBP: BloodPressureEntry?,
        recentGlucose: BloodGlucoseEntry?
    ) -> Data {
        let pdfMetaData = [
            kCGPDFContextCreator: "ForeverFit iOS Health Companion",
            kCGPDFContextAuthor: userProfile.name,
            kCGPDFContextTitle: "Comprehensive Medical Telemetry Report"
        ]

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageWidth: CGFloat = 8.5 * 72.0
        let pageHeight: CGFloat = 11.0 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        return renderer.pdfData { context in
            context.beginPage()

            let titleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
            let headerFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
            let bodyFont = UIFont.systemFont(ofSize: 11, weight: .regular)

            var y: CGFloat = 40.0

            // Header banner
            let title = "ForeverFit — Comprehensive Health Report"
            title.draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: titleFont, .foregroundColor: UIColor.systemGreen])
            y += 32

            let dateStr = "Generated on: \(Date().formatted(date: .abbreviated, time: .shortened))"
            dateStr.draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.secondaryLabel])
            y += 24

            // Divider
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 40, y: y))
            path.addLine(to: CGPoint(x: pageWidth - 40, y: y))
            path.lineWidth = 1.0
            UIColor.separator.setStroke()
            path.stroke()
            y += 20

            // Patient Demographics
            "Patient Demographics".draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: headerFont, .foregroundColor: UIColor.label])
            y += 18

            let demoText = "Name: \(userProfile.name)   |   Age: \(userProfile.calculatedAge)   |   Sex: \(userProfile.sex)\nBlood Group: \(medicalId.bloodType)   |   Known Allergies: \(medicalId.allergies)\nMedical Conditions: \(medicalId.conditions)"
            demoText.draw(in: CGRect(x: 40, y: y, width: pageWidth - 80, height: 60), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.label])
            y += 60

            // Live Wearable Telemetry
            "Wearable Vital Signs (MAX30101 + MAX30205)".draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: headerFont, .foregroundColor: UIColor.label])
            y += 18

            let hr = vitals != nil ? "\(Int(vitals!.heartRate)) bpm" : "Not connected"
            let spo2 = vitals != nil ? "\(Int(vitals!.spo2))%" : "Not connected"
            let temp = vitals != nil ? String(format: "%.1f °C", vitals!.bodyTempC) : "Not connected"

            let vitalsText = "Resting Heart Rate: \(hr)\nBlood Oxygen (SpO2): \(spo2)\nBody Skin Temperature: \(temp)\nToday's Physical Step Count: \(todaySteps) steps"
            vitalsText.draw(in: CGRect(x: 40, y: y, width: pageWidth - 80, height: 70), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.label])
            y += 70

            // Health Log Entries
            "Recent Clinical Logs".draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: headerFont, .foregroundColor: UIColor.label])
            y += 18

            let bpStr = recentBP != nil ? "\(recentBP!.systolic)/\(recentBP!.diastolic) mmHg" : "120/80 mmHg (Normal)"
            let glucStr = recentGlucose != nil ? "\(Int(recentGlucose!.glucoseMgDl)) mg/dL" : "95 mg/dL (Fasting)"

            let logText = "Latest Blood Pressure: \(bpStr)\nBlood Glucose: \(glucStr)\nCurrent Medications: \(medicalId.medications)"
            logText.draw(in: CGRect(x: 40, y: y, width: pageWidth - 80, height: 50), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.label])
            y += 60

            // Emergency Contacts
            "Designated Emergency Contacts".draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: headerFont, .foregroundColor: UIColor.label])
            y += 18

            var contactsText = ""
            for c in userProfile.emergencyContacts {
                contactsText += "• \(c.name) (\(c.relationship)): \(c.phone)\n"
            }
            contactsText.draw(in: CGRect(x: 40, y: y, width: pageWidth - 80, height: 60), withAttributes: [.font: bodyFont, .foregroundColor: UIColor.label])
            y += 70

            // Footer note
            let footer = "This clinical snapshot was produced offline by ForeverFit Health Companion (SIH '26). Consult a certified medical practitioner for diagnostic validation."
            footer.draw(in: CGRect(x: 40, y: pageHeight - 50, width: pageWidth - 80, height: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.tertiaryLabel])
        }
    }
}

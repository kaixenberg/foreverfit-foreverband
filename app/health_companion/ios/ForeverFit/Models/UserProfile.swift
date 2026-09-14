import Foundation

public struct EmergencyContact: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var phone: String
    public var relationship: String
    public var isPrimary: Bool

    public init(id: UUID = UUID(), name: String, phone: String, relationship: String, isPrimary: Bool = false) {
        self.id = id
        self.name = name
        self.phone = phone
        self.relationship = relationship
        self.isPrimary = isPrimary
    }
}

public struct UserProfile: Codable, Equatable {
    public var name: String
    public var dateOfBirth: Date?
    public var sex: String
    public var defaultWeightKg: Double?
    public var defaultHeightCm: Double?
    public var emergencyContacts: [EmergencyContact]
    public var onboardingCompleted: Bool

    public init(
        name: String = "Ankit Gupta",
        dateOfBirth: Date? = Calendar.current.date(byAdding: .year, value: -22, to: Date()),
        sex: String = "Male",
        defaultWeightKg: Double? = 72.0,
        defaultHeightCm: Double? = 176.0,
        emergencyContacts: [EmergencyContact] = [
            EmergencyContact(name: "Dr. Sharma", phone: "+919876543210", relationship: "Physician", isPrimary: true),
            EmergencyContact(name: "Family (SOS)", phone: "+919812345678", relationship: "Guardian", isPrimary: false)
        ],
        onboardingCompleted: Bool = false
    ) {
        self.name = name
        self.dateOfBirth = dateOfBirth
        self.sex = sex
        self.defaultWeightKg = defaultWeightKg
        self.defaultHeightCm = defaultHeightCm
        self.emergencyContacts = emergencyContacts
        self.onboardingCompleted = onboardingCompleted
    }

    public var calculatedAge: Int {
        guard let dob = dateOfBirth else { return 25 }
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dob, to: Date())
        return ageComponents.year ?? 25
    }
}

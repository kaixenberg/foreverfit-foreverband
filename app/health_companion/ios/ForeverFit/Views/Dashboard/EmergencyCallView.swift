import SwiftUI

public struct EmergencyCallView: View {
    @ObservedObject var workflow: EmergencyWorkflowService
    @Environment(\.dismiss) private var dismiss

    public init(workflow: EmergencyWorkflowService) {
        self.workflow = workflow
    }

    private var stateLabel: String {
        switch workflow.state {
        case .idle: return "Idle"
        case .emergencyDetected: return "Emergency detected"
        case .collectingData: return "Collecting your recent health data…"
        case .gettingLocation: return "Getting your location…"
        case .generatingMessage: return "Preparing the emergency summary…"
        case .callingEmergencyServices: return "Opening emergency services dialer…"
        case .announcingToEmergencyServices: return "Speaking summary to emergency services…"
        case .waitingForEmergencyCallEnd: return "Emergency call in progress…"
        case .callingEmergencyContact: return "Calling your emergency contact…"
        case .retryingContact: return "Retrying emergency contact (attempt \(workflow.attempt) of 5)…"
        case .announcingToContact: return "Speaking summary to your contact…"
        case .contactNoAnswer: return "No answer — will retry shortly…"
        case .smsFallback: return "Contact unreachable after 5 attempts — sending emergency SMS…"
        case .completed: return "Done"
        case .failed: return "The workflow could not continue"
        case .cancelled: return "Cancelled"
        }
    }

    public var body: some View {
        ZStack {
            LiquidGlassTheme.alertCrimson
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Color.white)

                    Text("Emergency Response")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)

                    if workflow.isUsingMockTelephony {
                        Text("TEST MODE — no real call or SMS will be placed")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LiquidGlassTheme.alertCrimson)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white))
                    }

                    Text(stateLabel)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.top, 24)

                // Detailed Script Cards & Log
                ScrollView {
                    VStack(spacing: 12) {
                        if let script = workflow.servicesScript {
                            scriptCard(title: "Emergency Services Announcement", text: script)
                        }

                        if let script = workflow.contactScript {
                            scriptCard(title: "Emergency Contact Announcement", text: script)
                        }

                        if let sms = workflow.smsText {
                            scriptCard(title: "SMS Fallback Message", text: sms)
                        }

                        if !workflow.log.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Operational Log")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.6))
                                    .textCase(.uppercase)

                                ForEach(workflow.log, id: \.self) { entry in
                                    Text(entry)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Color.black.opacity(0.8))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.92)))
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Action Buttons
                VStack(spacing: 10) {
                    if workflow.isActive {
                        Button {
                            workflow.cancel()
                        } label: {
                            Text("Cancel Emergency Sequence")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.black.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Text("Close")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(LiquidGlassTheme.alertCrimson)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func scriptCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.6))
                .textCase(.uppercase)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.85))
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
    }
}

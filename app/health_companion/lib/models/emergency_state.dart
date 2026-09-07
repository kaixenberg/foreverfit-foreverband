/// States for the AI-assisted emergency call workflow
/// (`lib/domain/emergency_workflow_service.dart`) — an explicit state
/// machine rather than loosely connected callbacks, per its design brief.
/// `failed` and `cancelled` are practical additions beyond the brief's
/// (explicitly "suggested") list — a dedicated terminal state for an
/// unrecoverable error and for the user backing out via the existing
/// "I'm OK" affordance, respectively.
enum EmergencyWorkflowState {
  idle,
  emergencyDetected,
  collectingData,
  generatingMessage,
  gettingLocation,
  callingEmergencyServices,
  announcingToEmergencyServices,
  waitingForEmergencyCallEnd,
  callingEmergencyContact,
  announcingToContact,
  contactNoAnswer,
  retryingContact,
  smsFallback,
  completed,
  failed,
  cancelled,
}

/// What a single contact-call attempt resolved to. "notAnswered" collapses
/// rejected/no-answer/failed/unreachable — Android gives a normal app no
/// way to tell these apart (see ARCHITECTURE.md), so they're deliberately
/// not split further rather than inventing a distinction the platform
/// doesn't expose.
enum CallOutcome { answered, notAnswered, error }

/// Coarse call state as observed by the native telephony_events channel —
/// the only granularity a normal Android app can read (no distinct
/// "ringing" vs "active" for an outgoing call).
enum CallState { idle, offHook }

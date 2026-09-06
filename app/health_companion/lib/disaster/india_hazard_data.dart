/// Simplified, STATE-LEVEL hazard baseline for India — the fully-offline
/// fallback used when there's no cached location-specific data at all
/// (fresh install, never been online). This is a hackathon-scope
/// approximation, not authoritative: real seismic/flood/cyclone risk
/// varies within a state, often by district, and India's own agencies
/// (BIS, NDMA, CWC) publish much finer-grained official data.
///
/// Why state-level hardcoded data instead of a bundled official dataset:
/// data.gov.in's seismic-zone resource page returned HTTP 403 when
/// fetched directly, and the only India-wide flood dataset actually
/// confirmed downloadable (via the GitHub API, not just a page's
/// description — an earlier summary describing small ready-made
/// district/state JSON files turned out to be fabricated, not real) was
/// a 28.6MB historical flood-event GeoJSON not worth bundling for this
/// pass. Seismic zones per BIS IS 1893:2016 (approximate — a state's
/// predominant/highest zone, since real boundaries cross state lines).
library;

enum SeismicZone { ii, iii, iv, v }

class StateHazardProfile {
  final SeismicZone seismicZone;
  final bool cycloneProne;
  final bool floodProne;

  const StateHazardProfile({
    required this.seismicZone,
    required this.cycloneProne,
    required this.floodProne,
  });
}

/// Keyed by state/UT name as returned by Nominatim's reverse-geocode
/// `address.state` field for India (verified directly — e.g. "Delhi",
/// "West Bengal" — standard English state names).
const Map<String, StateHazardProfile> indiaStateHazards = {
  'Jammu and Kashmir': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: false, floodProne: false),
  'Ladakh': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: false, floodProne: false),
  'Himachal Pradesh': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: false, floodProne: false),
  'Uttarakhand': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: false, floodProne: false),
  'Gujarat': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: true, floodProne: false),
  'Assam': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: false, floodProne: true),
  'Arunachal Pradesh': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: false, floodProne: false),
  'Manipur': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: false, floodProne: false),
  'Meghalaya': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: false, floodProne: false),
  'Mizoram': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: false, floodProne: false),
  'Nagaland': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: false, floodProne: false),
  'Tripura': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: false, floodProne: false),
  'Sikkim': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: false, floodProne: false),
  'Andaman and Nicobar Islands': StateHazardProfile(
      seismicZone: SeismicZone.v, cycloneProne: true, floodProne: false),
  'Bihar': StateHazardProfile(
      seismicZone: SeismicZone.iv, cycloneProne: false, floodProne: true),
  'Delhi': StateHazardProfile(
      seismicZone: SeismicZone.iv, cycloneProne: false, floodProne: false),
  'Punjab': StateHazardProfile(
      seismicZone: SeismicZone.iv, cycloneProne: false, floodProne: true),
  'Haryana': StateHazardProfile(
      seismicZone: SeismicZone.iv, cycloneProne: false, floodProne: true),
  'West Bengal': StateHazardProfile(
      seismicZone: SeismicZone.iv, cycloneProne: true, floodProne: true),
  'Chandigarh': StateHazardProfile(
      seismicZone: SeismicZone.iv, cycloneProne: false, floodProne: false),
  'Rajasthan': StateHazardProfile(
      seismicZone: SeismicZone.iii, cycloneProne: false, floodProne: false),
  'Uttar Pradesh': StateHazardProfile(
      seismicZone: SeismicZone.iii, cycloneProne: false, floodProne: true),
  'Maharashtra': StateHazardProfile(
      seismicZone: SeismicZone.iii, cycloneProne: false, floodProne: true),
  'Karnataka': StateHazardProfile(
      seismicZone: SeismicZone.iii, cycloneProne: false, floodProne: false),
  'Goa': StateHazardProfile(
      seismicZone: SeismicZone.iii, cycloneProne: false, floodProne: false),
  'Kerala': StateHazardProfile(
      seismicZone: SeismicZone.iii, cycloneProne: false, floodProne: true),
  'Jharkhand': StateHazardProfile(
      seismicZone: SeismicZone.iii, cycloneProne: false, floodProne: false),
  'Chhattisgarh': StateHazardProfile(
      seismicZone: SeismicZone.iii, cycloneProne: false, floodProne: false),
  'Puducherry': StateHazardProfile(
      seismicZone: SeismicZone.iii, cycloneProne: true, floodProne: false),
  'Lakshadweep': StateHazardProfile(
      seismicZone: SeismicZone.iii, cycloneProne: true, floodProne: false),
  'Madhya Pradesh': StateHazardProfile(
      seismicZone: SeismicZone.ii, cycloneProne: false, floodProne: false),
  'Odisha': StateHazardProfile(
      seismicZone: SeismicZone.ii, cycloneProne: true, floodProne: true),
  'Tamil Nadu': StateHazardProfile(
      seismicZone: SeismicZone.ii, cycloneProne: true, floodProne: false),
  'Andhra Pradesh': StateHazardProfile(
      seismicZone: SeismicZone.ii, cycloneProne: true, floodProne: true),
  'Telangana': StateHazardProfile(
      seismicZone: SeismicZone.ii, cycloneProne: false, floodProne: false),
};

const StateHazardProfile defaultHazardProfile = StateHazardProfile(
  seismicZone: SeismicZone.iii,
  cycloneProne: false,
  floodProne: false,
);

StateHazardProfile hazardProfileForState(String? stateName) {
  if (stateName == null) return defaultHazardProfile;
  return indiaStateHazards[stateName] ?? defaultHazardProfile;
}

String seismicZoneLabel(SeismicZone zone) {
  switch (zone) {
    case SeismicZone.ii:
      return 'Zone II (low)';
    case SeismicZone.iii:
      return 'Zone III (moderate)';
    case SeismicZone.iv:
      return 'Zone IV (high)';
    case SeismicZone.v:
      return 'Zone V (very high)';
  }
}

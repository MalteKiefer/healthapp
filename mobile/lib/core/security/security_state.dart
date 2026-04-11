/// Global security lifecycle state for the HealthVault mobile app.
///
/// See docs/superpowers/specs/2026-04-10-mobile-security-pin-biometric-design.md
/// section 4 for the full state machine.
enum SecurityState {
  /// No server is configured, no vault exists. Fresh install.
  unregistered,

  /// Server login succeeded but the user has not yet set a PIN.
  /// Routing is forced to /setup-pin.
  loggedInNoPin,

  /// An existing vault needs PIN or biometric to unlock.
  locked,

  /// Unlock attempt in flight.
  unlocking,

  /// DEK is held in RAM and all data is reachable.
  unlocked,

  /// A wipe just finished; used to show a one-shot warning banner.
  wiped,

  /// Legacy credentials found without a vault; forced PIN setup required.
  migrationPending;

  /// True when the router must block every content route.
  bool get isGated => this != SecurityState.unlocked;
}

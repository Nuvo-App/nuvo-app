# Demo / store-review account: testing@getnuvo.net

Password / code flow: the account signs in with `testing123` (reviewer path; see
`isNuvoStoreDemoEmail`). These four rules are the contract. Each has a named
test; do not change behaviour without changing the rule here first.

- **R1 Cold open is clean.** If the last account signed in on this device was
  testing@getnuvo.net, the next cold start is signed out, local onboarding and
  first-use state are wiped, fake data is off, and the session is not restored.
  Test: `test/demo_account_r1_cold_start_test.dart`.
- **R2 Sign in skips onboarding.** Signing in as testing@getnuvo.net goes
  straight to the Arena, never through onboarding v2 (flag on or off).
  Test: `test/demo_account_routing_test.dart` ("R2: ...").
- **R3 Create account walks the full onboarding.** Creating an account with
  that email (a fresh user) walks the real onboarding flow like anyone else.
  Tests: `test/demo_account_routing_test.dart` ("R3: ..."),
  `test/demo_account_r3_controller_test.dart`.
- **R4 Fake data on demand, this account only.** A "Fake data" pill, shown only
  for testing@getnuvo.net, toggles fake (presentation) data on/off and reloads.
  It is absent for every other account. Test:
  `test/demo_account_r4_fake_data_pill_test.dart`.

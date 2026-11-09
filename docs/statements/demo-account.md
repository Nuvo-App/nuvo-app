# Demo / store-review account: testing@getnuvo.net

Four rules in Akshay's words. Each has a named test; change a rule here first.

- **R1** If the last signed-in account on this device was testing@getnuvo.net,
  every cold open (app swiped away and reopened) starts clean, like a first
  install: signed out, no local onboarding state, fake data off.
  R1 concerns cold opens only. An explicit sign-out goes to the login sheet
  for every account (including this one).
  Tests: `test/demo_account_r1_cold_start_test.dart`,
  `test/onboarding_v2/logout_landing_test.dart`.
- **R2** Signing in with testing@getnuvo.net / `testing123` logs in as the
  testing user and skips onboarding entirely, like a regular returning user.
  Test: `test/demo_account_routing_test.dart` ("R2: ...").
- **R3** Create account with that email is allowed even though it exists,
  because that account's information is never sent anywhere (the server
  resets it); it walks the full onboarding.
  Tests: `test/demo_account_routing_test.dart` ("R3: ..."),
  `test/demo_account_r3_controller_test.dart`.
- **R4** At any point in the app (every tab and pushed full-screen routes) a
  "Fake data" button creates a bunch of demo data on that account, and turns it
  off again. It exists for this account only (a root layer above the
  Navigator).
  Test: `test/demo_account_r4_fake_data_pill_test.dart`.

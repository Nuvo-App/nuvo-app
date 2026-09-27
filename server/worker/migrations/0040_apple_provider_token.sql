-- Sign in with Apple server flow: the client forwards its one-time
-- authorizationCode at sign-in; the worker exchanges it at Apple's token
-- endpoint and stores the refresh token here so account deletion can revoke
-- the Apple grant (App Review 5.1.1(v)). Never selected into public
-- responses; deleted with the identity row.
ALTER TABLE auth_identities ADD COLUMN provider_refresh_token TEXT;

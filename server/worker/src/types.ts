export type AppEnv = {
  Bindings: {
    DB: D1Database;
    GOOGLE_IOS_CLIENT_ID: string;
    RESEND_API_KEY: string;
    RESEND_FROM_EMAIL: string;
    JWT_SECRET: string;
    API_BASE_URL: string;
    PROFILE_PHOTOS: R2Bucket;
  };
  Variables: {
    userId: string;
  };
};

export interface UserRow {
  id: string;
  primary_email: string | null;
  status: string;
  created_at: string;
  updated_at: string;
  last_login_at: string | null;
  // Demo World Mode — added in migration 0006. Default 0 / null.
  demo_world_enabled: number;
  demo_world_seed: string | null;
  demo_world_variant: string | null;
}

export interface ProfileRow {
  user_id: string;
  full_name: string | null;
  username: string | null;
  avatar_url: string | null;
  private_profile: number;
  onboarding_complete: number;
  created_at: string;
  updated_at: string;
}

export interface PassRow {
  id: string;
  user_id: string;
  member_id: string;
  pass_slug: string;
  created_at: string;
}

export interface EmailCodeRow {
  id: string;
  email: string;
  code_hash: string;
  attempts: number;
  expires_at: string;
  used_at: string | null;
  created_at: string;
}

export interface SessionRow {
  id: string;
  user_id: string;
  refresh_token_hash: string;
  device_label: string | null;
  expires_at: string;
  revoked_at: string | null;
  created_at: string;
  last_seen_at: string | null;
}

export interface AuthIdentityRow {
  id: string;
  user_id: string;
  provider: string;
  provider_user_id: string | null;
  email: string | null;
  email_verified: number;
  display_name: string | null;
  avatar_url: string | null;
  created_at: string;
}

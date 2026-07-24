export type AppEnv = {
  Bindings: {
    DB: D1Database;
    GOOGLE_IOS_CLIENT_ID: string;
    RESEND_API_KEY: string;
    RESEND_FROM_EMAIL: string;
    JWT_SECRET: string;
    REVIEWER_PASSWORD_HASH?: string;
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
  terms_accepted_at: string | null;
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
  avatar_object_key: string | null;
  private_profile: number;
  onboarding_complete: number;
  is_demo: number;
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

// ---------------------------------------------------------------------------
// Simplified schema tables (added in migrations 0007/0008)
// ---------------------------------------------------------------------------

export interface MediaObjectRow {
  id: string;
  owner_user_id: string | null;
  bucket: string;
  object_key: string;
  public_url: string | null;
  media_type: string;
  purpose: string;
  status: string;
  created_at: string;
  deleted_at: string | null;
}

export interface RaceRow {
  id: string;
  creator_id: string;
  title: string;
  description: string | null;
  race_type: string;
  movement_type: string | null;
  verification_type: string;
  target_value: number | null;
  target_unit: string | null;
  activity_id?: string | null;
  metric?: string | null;
  format?: string | null;
  scoring_rule?: string | null;
  attempt_duration_seconds?: number | null;
  attempt_limit?: number | null;
  verification_method?: string | null;
  timezone?: string | null;
  recurrence?: string | null;
  winner_user_id?: string | null;
  completed_at?: string | null;
  status: string;
  visibility: string;
  public_join_enabled: number;
  start_at: string | null;
  end_at: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface RaceMemberRow {
  id: string;
  race_id: string;
  user_id: string;
  role: string;
  status: string;
  joined_at: string;
  cached_display_name: string | null;
  cached_avatar_url: string | null;
}

export interface RaceProgressRow {
  id: string;
  race_id: string;
  user_id: string;
  progress_value: number;
  progress_percent: number;
  completed_at: string | null;
  rank_cache: number | null;
  updated_at: string;
}

export interface MoveLogRow {
  id: string;
  race_id: string;
  user_id: string;
  source: string;
  movement_type: string | null;
  activity_id?: string | null;
  metric?: string | null;
  value: number | null;
  unit: string | null;
  status: string;
  summary: string | null;
  media_object_key: string | null;
  validator_version: string | null;
  duration_ms: number | null;
  metadata_json: string | null;
  client_submission_id?: string | null;
  previous_score?: number | null;
  new_score?: number | null;
  previous_rank?: number | null;
  new_rank?: number | null;
  race_completed?: number | null;
  created_at: string;
}

export interface BlockedUserRow {
  id: string;
  user_id: string;
  blocked_user_id: string;
  created_at: string;
}

export interface ReportRow {
  id: string;
  reporter_user_id: string;
  target_type: string;
  target_id: string;
  reason: string | null;
  status: string;
  reviewed_by: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

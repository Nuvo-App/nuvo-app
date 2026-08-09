export type RaceActivityId = 'push_ups' | 'jumping_jacks' | 'squats' | 'lunges' | 'plank_hold' | 'high_knees' | 'arm_raises';
export type RaceMetric = 'reps' | 'seconds';
export type RaceFormat = 'first_to_goal' | 'most_in_window' | 'best_attempt' | 'timed_attempt';
export type RaceScoringRule = 'cumulative_sum' | 'maximum_attempt';
export type VerificationMethod = 'camera_pose';
export type RaceRecurrence = 'none' | 'daily' | 'weekly';

export interface RaceActivityDefinition {
  id: RaceActivityId;
  displayName: string;
  aliases: string[];
  supportedMetrics: RaceMetric[];
  defaultMetric: RaceMetric;
  validatorKey: string;
  verificationMethod: VerificationMethod;
  cameraOrientation: 'front' | 'front_or_angle' | 'side';
  sessionBehavior: 'count_reps' | 'validated_timer';
  suggestedTargets: number[];
  supportedFormats: RaceFormat[];
  availability: 'supported' | 'hidden';
  instructions: string[];
}

export const RACE_ACTIVITY_CATALOG: RaceActivityDefinition[] = [
  {
    id: 'push_ups',
    displayName: 'Pushups',
    aliases: ['pushups', 'push ups', 'push-up', 'push-ups'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'pushups_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [6, 8, 15, 25, 50, 100],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your upper body and hands visible.', 'Wait for the Ready signal.', 'Finish each rep cleanly.'],
  },
  {
    id: 'jumping_jacks',
    displayName: 'Jumping Jacks',
    aliases: ['jumping jacks', 'jumping jack', 'jacks'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'jumping_jacks_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [15, 30, 60, 100],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your full body visible.', 'Leave room above your head.', 'Finish each rep cleanly.'],
  },
  {
    id: 'squats',
    displayName: 'Squats',
    aliases: ['squats', 'squat'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'squats_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [10, 25, 50, 100],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your full body centered.', 'Go lower.', 'Stand tall to finish the rep.'],
  },
  {
    id: 'lunges',
    displayName: 'Lunges',
    aliases: ['lunges', 'lunge'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'lunges_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front_or_angle',
    sessionBehavior: 'count_reps',
    suggestedTargets: [10, 20, 40, 60],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your full body visible.', 'Step back into frame.', 'Stand tall to finish the rep.'],
  },
  {
    id: 'plank_hold',
    displayName: 'Plank',
    aliases: ['plank', 'plank hold', 'hold plank'],
    supportedMetrics: ['seconds'],
    defaultMetric: 'seconds',
    validatorKey: 'plank_hold_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'side',
    sessionBehavior: 'validated_timer',
    suggestedTargets: [20, 30, 60, 120, 600],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt'],
    availability: 'supported',
    instructions: ['Use a side view.', 'Keep your whole body visible.', 'Keep your body straight.'],
  },
  {
    id: 'high_knees',
    displayName: 'High Knees',
    aliases: ['high knees', 'high knee', 'high-knees', 'highknees'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'high_knees_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [10, 20, 40, 60],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your full body visible.', 'Lift each knee above your hip.', 'Alternate legs cleanly.'],
  },
  {
    id: 'arm_raises',
    displayName: 'Arm Raises',
    aliases: ['arm raises', 'arm raise', 'arm-raises', 'armraises'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'arm_raises_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [10, 20, 40, 60],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your upper body and arms visible.', 'Raise both arms above your shoulders.', 'Lower both arms to finish the rep.'],
  },
];

export function activityForId(id: string | null | undefined): RaceActivityDefinition | undefined {
  return RACE_ACTIVITY_CATALOG.find((activity) => activity.id === normalizeActivityId(id));
}

export function normalizeActivityId(value: string | null | undefined): RaceActivityId | undefined {
  if (!value) return undefined;
  const normalized = value.toLowerCase().replace(/[-\s]+/g, '_');
  if (normalized === 'pushups' || normalized === 'push_up') return 'push_ups';
  if (normalized === 'plank' || normalized === 'plank_hold') return 'plank_hold';
  if (normalized === 'jumping_jack') return 'jumping_jacks';
  if (normalized === 'high_knee' || normalized === 'highknees') return 'high_knees';
  if (normalized === 'arm_raise' || normalized === 'armraises') return 'arm_raises';
  if (['push_ups', 'jumping_jacks', 'squats', 'lunges', 'plank_hold', 'high_knees', 'arm_raises'].includes(normalized)) {
    return normalized as RaceActivityId;
  }
  return undefined;
}

export function normalizeMetric(value: string | null | undefined, activity?: RaceActivityDefinition): RaceMetric | undefined {
  if (!value) return activity?.defaultMetric;
  const normalized = value.toLowerCase().trim();
  if (normalized === 'second' || normalized === 'seconds' || normalized === 'sec') return 'seconds';
  if (
    normalized === 'rep' ||
    normalized === 'reps' ||
    normalized === 'pushups' ||
    normalized === 'push ups' ||
    normalized === 'jumping jacks' ||
    normalized === 'squats' ||
    normalized === 'lunges' ||
    normalized === 'high_knees' ||
    normalized === 'high knees' ||
    normalized === 'arm_raises' ||
    normalized === 'arm raises'
  ) return 'reps';
  return undefined;
}

export function scoringRuleForFormat(format: RaceFormat): RaceScoringRule {
  return format === 'best_attempt' || format === 'timed_attempt' ? 'maximum_attempt' : 'cumulative_sum';
}

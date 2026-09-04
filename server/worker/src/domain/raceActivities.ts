export type RaceActivityId = 'push_ups' | 'jumping_jacks' | 'squats' | 'lunges' | 'plank_hold' | 'high_knees' | 'arm_raises' | 'sumo_squats' | 'side_lunges' | 'deep_squats' | 'squat_jacks' | 'jump_squats' | 'lunge_jumps' | 'running_in_place' | 'treadmill_running' | 'walking_in_place' | 'marching_in_place' | 'butt_kicks' | 'mountain_climbers' | 'burpees' | 'step_ups' | 'calf_raises' | 'lateral_steps';
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
  {
    id: 'sumo_squats',
    displayName: 'Sumo Squats',
    aliases: ['sumo squats', 'sumo squat', 'sumo'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'sumo_squats_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [10, 20, 40, 60],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Stand with feet wider than shoulder width.', 'Keep your full body centered.', 'Go lower, stand tall to finish.'],
  },
  {
    id: 'side_lunges',
    displayName: 'Side Lunges',
    aliases: ['side lunges', 'side lunge', 'lateral lunges'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'side_lunges_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [8, 16, 30, 50],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your full body visible.', 'Step one leg out to the side.', 'Stand tall to finish the rep.'],
  },
  {
    id: 'deep_squats',
    displayName: 'Deep Squats',
    aliases: ['deep squats', 'deep squat', 'ass to grass', 'atg squats'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'deep_squats_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [8, 15, 30, 50],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your full body centered.', 'Squat below parallel — hips below knees.', 'Stand tall to finish the rep.'],
  },
  {
    id: 'squat_jacks',
    displayName: 'Squat Jacks',
    aliases: ['squat jacks', 'squat jack', 'squatting jacks'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'squat_jacks_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [8, 15, 30, 50],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your full body visible.', 'Jump feet wide and squat down, arms up.', 'Return to standing with feet together.'],
  },
  {
    id: 'jump_squats',
    displayName: 'Jump Squats',
    aliases: ['jump squats', 'jump squat', 'plyometric squats', 'squat jumps'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'jump_squats_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [8, 15, 30, 50],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your full body visible.', 'Squat down, then jump explosively upward.', 'Land softly and stand tall to finish.'],
  },
  {
    id: 'lunge_jumps',
    displayName: 'Lunge Jumps',
    aliases: ['lunge jumps', 'lunge jump', 'jumping lunges', 'split jumps'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'lunge_jumps_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front_or_angle',
    sessionBehavior: 'count_reps',
    suggestedTargets: [8, 15, 30, 50],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your full body visible.', 'Lunge forward, then jump and switch legs in the air.', 'Land in the opposite lunge to finish the rep.'],
  },
  {
    id: 'running_in_place',
    displayName: 'Running in Place',
    aliases: ['running in place', 'run in place', 'running'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'running_in_place_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [50, 100, 200, 400],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your lower body visible.', 'Alternate knees at a running cadence.', 'Stay roughly in place.'],
  },
  {
    id: 'treadmill_running',
    displayName: 'Treadmill Running',
    aliases: ['treadmill running', 'treadmill', 'running on treadmill'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'treadmill_running_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [50, 100, 200, 400],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your lower body visible.', 'Detected from your gait, not the treadmill.', 'Camera stays fixed on you as you run.'],
  },
  {
    id: 'walking_in_place',
    displayName: 'Walking in Place',
    aliases: ['walking in place', 'walk in place', 'walking'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'walking_in_place_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [40, 80, 150, 300],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your lower body visible.', 'Step in place, alternating feet.', 'Stay roughly in place.'],
  },
  {
    id: 'marching_in_place',
    displayName: 'Marching in Place',
    aliases: ['marching in place', 'march in place', 'marching'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'marching_in_place_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [40, 80, 150, 300],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your lower body visible.', 'Lift each knee up high, alternating sides.', 'Stay roughly in place.'],
  },
  {
    id: 'butt_kicks',
    displayName: 'Butt Kicks',
    aliases: ['butt kicks', 'butt kick', 'heel kicks', 'glute kicks'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'butt_kicks_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [20, 40, 80, 150],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your lower body visible.', 'Kick your heels back toward your glutes.', 'Alternate sides.'],
  },
  {
    id: 'mountain_climbers',
    displayName: 'Mountain Climbers',
    aliases: ['mountain climbers', 'mountain climber', 'climbers'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'mountain_climbers_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [20, 40, 80, 150],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your full body visible.', 'Hands planted, drive your knees in one at a time.', 'Alternate sides.'],
  },
  {
    id: 'burpees',
    displayName: 'Burpees',
    aliases: ['burpees', 'burpee'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'burpees_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [5, 10, 20, 40],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your full body visible.', 'Crouch down with hands toward the floor.', 'Stand tall to finish the rep.'],
  },
  {
    id: 'step_ups',
    displayName: 'Step-Ups',
    aliases: ['step ups', 'step-ups', 'step up'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'step_ups_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [20, 40, 80, 150],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your lower body visible.', 'Step up and alternate legs.', 'Stay roughly in place.'],
  },
  {
    id: 'calf_raises',
    displayName: 'Calf Raises',
    aliases: ['calf raises', 'calf raise', 'heel raises'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'calf_raises_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [15, 25, 50, 100],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your lower body visible.', 'Rise onto your toes, then lower fully.', 'Keep your knees straight.'],
  },
  {
    id: 'lateral_steps',
    displayName: 'Lateral Steps',
    aliases: ['lateral steps', 'side steps', 'side step', 'lateral step'],
    supportedMetrics: ['reps'],
    defaultMetric: 'reps',
    validatorKey: 'lateral_steps_v1',
    verificationMethod: 'camera_pose',
    cameraOrientation: 'front',
    sessionBehavior: 'count_reps',
    suggestedTargets: [20, 40, 80, 150],
    supportedFormats: ['first_to_goal', 'most_in_window', 'best_attempt', 'timed_attempt'],
    availability: 'supported',
    instructions: ['Keep your full body visible.', 'Step side to side, alternating directions.', 'Take a deliberate step, not a small shuffle.'],
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
  if (normalized === 'deep_squat') return 'deep_squats';
  if (normalized === 'squat_jack') return 'squat_jacks';
  if (normalized === 'jump_squat') return 'jump_squats';
  if (normalized === 'lunge_jump') return 'lunge_jumps';
  if (normalized === 'run_in_place' || normalized === 'running') return 'running_in_place';
  if (normalized === 'treadmill') return 'treadmill_running';
  if (normalized === 'walk_in_place' || normalized === 'walking') return 'walking_in_place';
  if (normalized === 'march_in_place' || normalized === 'marching') return 'marching_in_place';
  if (normalized === 'butt_kick' || normalized === 'buttkicks') return 'butt_kicks';
  if (normalized === 'mountain_climber' || normalized === 'climbers') return 'mountain_climbers';
  if (normalized === 'burpee') return 'burpees';
  if (normalized === 'step_up' || normalized === 'stepups') return 'step_ups';
  if (normalized === 'calf_raise' || normalized === 'heel_raises') return 'calf_raises';
  if (normalized === 'side_steps' || normalized === 'side_step' || normalized === 'lateral_step') return 'lateral_steps';
  if (['push_ups', 'jumping_jacks', 'squats', 'lunges', 'plank_hold', 'high_knees', 'arm_raises', 'sumo_squats', 'side_lunges', 'deep_squats', 'squat_jacks', 'jump_squats', 'lunge_jumps', 'running_in_place', 'treadmill_running', 'walking_in_place', 'marching_in_place', 'butt_kicks', 'mountain_climbers', 'burpees', 'step_ups', 'calf_raises', 'lateral_steps'].includes(normalized)) {
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
    normalized === 'arm raises' ||
    normalized === 'sumo_squats' ||
    normalized === 'sumo squats' ||
    normalized === 'side_lunges' ||
    normalized === 'side lunges' ||
    normalized === 'deep_squats' ||
    normalized === 'deep squats' ||
    normalized === 'squat_jacks' ||
    normalized === 'squat jacks' ||
    normalized === 'jump_squats' ||
    normalized === 'jump squats' ||
    normalized === 'lunge_jumps' ||
    normalized === 'lunge jumps' ||
    normalized === 'running_in_place' ||
    normalized === 'running in place' ||
    normalized === 'treadmill_running' ||
    normalized === 'treadmill running' ||
    normalized === 'walking_in_place' ||
    normalized === 'walking in place' ||
    normalized === 'marching_in_place' ||
    normalized === 'marching in place' ||
    normalized === 'butt_kicks' ||
    normalized === 'butt kicks' ||
    normalized === 'mountain_climbers' ||
    normalized === 'mountain climbers' ||
    normalized === 'burpees' ||
    normalized === 'step_ups' ||
    normalized === 'step ups' ||
    normalized === 'calf_raises' ||
    normalized === 'calf raises' ||
    normalized === 'lateral_steps' ||
    normalized === 'lateral steps'
  ) return 'reps';
  return undefined;
}

export function scoringRuleForFormat(format: RaceFormat): RaceScoringRule {
  return format === 'best_attempt' || format === 'timed_attempt' ? 'maximum_attempt' : 'cumulative_sum';
}

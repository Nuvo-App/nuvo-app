/**
 * Server mirror of lib/features/races/domain/race_safety.dart — FlexiRace's
 * refusal layer. The interpreter may fully understand a dangerous prompt; this
 * module decides whether the race may be created. A client bypass must never
 * mint a refused race, so POST /races evaluates the same categories.
 *
 * KEEP IN SYNC with the Dart file — same categories, same pattern intents.
 */

export interface RaceSafetyDecision {
  ok: boolean;
  category: string | null;
  reason: string | null;
}

const ALLOW: RaceSafetyDecision = { ok: true, category: null, reason: null };

interface SafetyRule {
  category: string;
  reason: string;
  patterns: RegExp[];
}

function normalize(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}

const RULES: SafetyRule[] = [
  {
    category: 'food_restriction',
    reason: "Races about not eating aren't safe. Pick something active instead.",
    patterns: [
      /\bwithout eating\b/, /\b(no|not) (eating|food|meals?)\b/, /\bstop eating\b/,
      /\bskip\w* meals?\b/, /\bstarv\w*\b/, /\bhunger\b/, /\bfasting\b/,
      /\blongest (time )?(without|no) (food|eating|meals?)\b/,
      /\bdiet\w*\b.*\b(most|longest|extreme)\b/,
    ],
  },
  {
    category: 'weight_manipulation',
    reason: 'Weight, pounds, and BMI targets are off-limits. Race the workout, not the scale.',
    patterns: [
      /\b(los(e|ing|t)|drop(ping|ped)?|shed(ding)?|cut(ting)?|burn(ing)? off)\b.*\b(weight|pounds?|lbs?|kilos?|kgs?|body fat)\b/,
      /\b(weight|pounds?|lbs?|kilos?|kgs?|body fat)\b.*\b(los(e|ing|t)|drop|cut|shed|burn off)\b/,
      /\bbmi\b/, /\bweight loss\b/, /\bcut(ting)? weight\b/, /\bbody fat\b/, /\bskinniest\b/,
    ],
  },
  {
    category: 'substance_consumption',
    reason: "Races about alcohol, smoking, or drugs aren't allowed.",
    patterns: [
      /\balcohol\b/, /\bbeers?\b/, /\bwine\b/,
      /\bshots?\b.*\b(drink|drunk|alcohol|tequila|vodka|liquor|bar)\b/,
      /\b(drink|drunk|alcohol|tequila|vodka|liquor|bar)\b.*\bshots?\b/,
      /\b(liquor|booze|tequila|vodka|whiskey|whisky|beer)\b/,
      /\bdrunk\b/, /\bdrinking\b.*\b(alcohol|beer|wine|liquor|shots?)\b/,
      /\bdrinks?\b.*\bmost\b(?!\s+water)/, /\bmost\b.*\bdrinks?\b(?!.*water)/,
      /\bsmok(e|es|ing)\b/, /\bcigarettes?\b/, /\bvap(e|es|ing)\b/,
      /\b(weed|marijuana|cannabis|edibles?|joints?)\b/,
      /\bpills?\b/, /\bdrugs?\b/, /\b(medication|meds)\b/, /\bnicotine\b/,
    ],
  },
  {
    category: 'breath_holding',
    reason: "Breath-holding races aren't safe. Pick something you can prove on camera.",
    patterns: [
      /\bbreath\b.*\b(hold|holding|longest)\b/, /\bhold\w*\b.*\bbreath\b/,
      /\bunderwater\b/, /\bapnea\b/,
    ],
  },
  {
    category: 'dangerous_driving',
    reason: 'Speeding and street-racing races are off-limits.',
    patterns: [
      /\bdriv\w*\b.*\b(fast|faster|fastest|speed|speeding|race|racing)\b/,
      /\b(fast|faster|fastest|speed|speeding|race|racing)\b.*\bdriv\w*\b/,
      /\bstreet rac\w*\b/, /\bspeeding\b/, /\bdrag rac\w*\b/,
    ],
  },
  {
    category: 'illegal_conduct',
    reason: "Races about illegal activity aren't allowed.",
    patterns: [
      /\bsteal(ing|s)?\b/, /\b(theft|shoplift\w*|burgle\w*|burgla\w*|rob\w*)\b/, /\b(vandali\w*|graffiti)\b/,
      /\btrespass\w*\b/, /\b(shop)?lift(ing)? from\b/, /\b(crime|criminal)\b/,
      /\bhack (into|someone|accounts?)\b/, /\bpirat\w*\b.*\b(movies?|music|games?)\b/,
    ],
  },
  {
    category: 'self_harm_or_violence',
    reason: "Races that could hurt people aren't allowed.",
    patterns: [
      /\bstay(ing)? awake\b/, /\b(without|no) sleep\b/, /\bsleep depriv\w*\b/,
      /\b(longest|most)\b.*\bawake\b/, /\bpunch\w*\b/, /\bslap\w*\b/,
      /\bhit\w*\b.*\b(someone|people|person|hardest)\b/,
      /\bfight\w*\b.*\b(someone|each other|people)\b/, /\bchoke\w*\b/,
      /\bhurt\w*\b.*\b(yourself|myself|someone|people)\b/,
      /\bcut\w*\b.*\b(yourself|myself)\b/, /\bself.?harm\w*\b/,
      /\bpain\b.*\b(endure|endurance|tolerate|most)\b/, /\b(most|longest)\b.*\bpain\b/,
      /\binjur\w*\b.*\b(most|first)\b/, /\bdeadly\b/,
      /\bkill\w*\b.*\b(yourself|myself|someone|people|them|him|her)\b/,
    ],
  },
  {
    category: 'gambling',
    reason: "Races about gambling or betting money aren't allowed.",
    patterns: [
      /\bgambl\w*\b/, /\bbet(ting)?\b.*\b(money|cash|most)\b/,
      /\b(most money)\b.*\b(bet|gambl|casino|poker)\b/,
      /\bcasino|poker|blackjack|roulette|slots?\b/, /\b(lottery|lotto|wager)\b/,
    ],
  },
  {
    category: 'sexual_content',
    reason: 'Races with sexual content are not allowed.',
    patterns: [
      /\b(sex|sexual)\b/, /\b(naked|nudes?)\b/, /\b(hook ?up|kissing|kissed|kiss)\b/,
      /\b(onlyfans|porn\w*)\b/,
    ],
  },
];

/** Evaluate free-text race content (title + custom activity name). */
export function evaluateRaceSafety(raceText: string): RaceSafetyDecision {
  const normalized = normalize(raceText);
  if (!normalized) return ALLOW;
  for (const rule of RULES) {
    for (const pattern of rule.patterns) {
      if (pattern.test(normalized)) {
        return { ok: false, category: rule.category, reason: rule.reason };
      }
    }
  }
  return ALLOW;
}

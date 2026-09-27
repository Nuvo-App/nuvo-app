/// FlexiRace safety boundary — a single canonical choke point between natural
/// language interpretation and race creation.
///
/// The parser is allowed to fully understand "first to lose 20 pounds"; this
/// layer decides whether Nuvo may create that race. It is deliberately a
/// bounded CATEGORY policy (eating restriction, substance consumption,
/// dangerous conduct, …), NOT an activity allowlist and NOT per-title string
/// bans — new phrasings inside a category are caught by the same rules.
///
/// Server-side enforcement mirrors these categories in
/// `server/worker/src/domain/raceSafety.ts` so a client bypass cannot mint a
/// refused race. Keep the two in sync.
library;

enum RaceSafetyVerdict { allowed, clarify, rejected }

class RaceSafetyDecision {
  const RaceSafetyDecision.allow()
      : verdict = RaceSafetyVerdict.allowed,
        category = null,
        reason = null;
  const RaceSafetyDecision.reject(this.category, this.reason)
      : verdict = RaceSafetyVerdict.rejected;
  const RaceSafetyDecision.ask(this.category, this.reason)
      : verdict = RaceSafetyVerdict.clarify;

  final RaceSafetyVerdict verdict;
  final String? category;

  /// Short member-facing explanation of why the race can't be created.
  final String? reason;

  bool get isAllowed => verdict == RaceSafetyVerdict.allowed;
}

class _SafetyRule {
  const _SafetyRule(this.category, this.reason, this.patterns);
  final String category;
  final String reason;
  final List<String> patterns;
}

String _normalize(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Ordered refusal policy. First matching category wins; the order keeps the
/// most serious categories ahead of ambiguous ones.
const List<_SafetyRule> _rules = [
  _SafetyRule('food_restriction',
      "Races about not eating aren't safe. Pick something active instead.", [
    r'\bwithout eating\b',
    r'\b(no|not) (eating|food|meals?)\b',
    r'\bstop eating\b',
    r'\bskip\w* meals?\b',
    r'\bstarv\w*\b',
    r'\bhunger\b',
    r'\bfasting\b',
    r'\blongest (time )?(without|no) (food|eating|meals?)\b',
    r'\bdiet\w*\b.*\b(most|longest|extreme)\b',
  ]),
  _SafetyRule('weight_manipulation',
      'Weight, pounds, and BMI targets are off-limits. Race the workout, not the scale.', [
    r'\b(los(e|ing|t)|drop(ping|ped)?|shed(ding)?|cut(ting)?|burn(ing)? off)\b.*\b(weight|pounds?|lbs?|kilos?|kgs?|body fat)\b',
    r'\b(weight|pounds?|lbs?|kilos?|kgs?|body fat)\b.*\b(los(e|ing|t)|drop|cut|shed|burn off)\b',
    r'\bbmi\b',
    r'\bweight loss\b',
    r'\bcut(ting)? weight\b',
    r'\bbody fat\b',
    r'\bskinniest\b',
  ]),
  _SafetyRule('substance_consumption',
      "Races about alcohol, smoking, or drugs aren't allowed.", [
    r'\balcohol\b',
    r'\bbeers?\b',
    r'\bwine\b',
    r'\bshots?\b.*\b(drink|drunk|alcohol|tequila|vodka|liquor|bar)\b',
    r'\b(drink|drunk|alcohol|tequila|vodka|liquor|bar)\b.*\bshots?\b',
    r'\b(liquor|booze|tequila|vodka|whiskey|whisky|beer)\b',
    r'\bdrunk\b',
    r'\bdrinking\b.*\b(alcohol|beer|wine|liquor|shots?)\b',
    r'\bdrinks?\b.*\bmost\b(?!\s+water)',
    r'\bmost\b.*\bdrinks?\b(?!.*water)',
    r'\bsmok(e|es|ing)\b',
    r'\bcigarettes?\b',
    r'\bvap(e|es|ing)\b',
    r'\b(weed|marijuana|cannabis|edibles?|joints?)\b',
    r'\bpills?\b',
    r'\bdrugs?\b',
    r'\b(medication|meds)\b',
    r'\bnicotine\b',
  ]),
  _SafetyRule('breath_holding',
      "Breath-holding races aren't safe. Pick something you can prove on camera.", [
    r'\bbreath\b.*\b(hold|holding|longest)\b',
    r'\bhold\w*\b.*\bbreath\b',
    r'\bunderwater\b',
    r'\bapnea\b',
  ]),
  _SafetyRule('dangerous_driving',
      'Speeding and street-racing races are off-limits.', [
    r'\bdriv\w*\b.*\b(fast|faster|fastest|speed|speeding|race|racing)\b',
    r'\b(fast|faster|fastest|speed|speeding|race|racing)\b.*\bdriv\w*\b',
    r'\bstreet rac\w*\b',
    r'\bspeeding\b',
    r'\bdrag rac\w*\b',
  ]),
  _SafetyRule('illegal_conduct',
      "Races about illegal activity aren't allowed.", [
    r'\bsteal(ing|s)?\b',
    r'\b(theft|shoplift\w*|burgle\w*|burgla\w*|rob\w*)\b',
    r'\b(vandali\w*|graffiti)\b',
    r'\btrespass\w*\b',
    r'\b(shop)?lift(ing)? from\b',
    r'\b(crime|criminal)\b',
    r'\bhack (into|someone|accounts?)\b',
    r'\bpirat\w*\b.*\b(movies?|music|games?)\b',
  ]),
  _SafetyRule('self_harm_or_violence',
      "Races that could hurt people aren't allowed.", [
    r'\bstay(ing)? awake\b',
    r'\b(without|no) sleep\b',
    r'\bsleep depriv\w*\b',
    r'\b(longest|most)\b.*\bawake\b',
    r'\bpunch\w*\b',
    r'\bslap\w*\b',
    r'\bhit\w*\b.*\b(someone|people|person|hardest)\b',
    r'\bfight\w*\b.*\b(someone|each other|people)\b',
    r'\bchoke\w*\b',
    r'\bhurt\w*\b.*\b(yourself|myself|someone|people)\b',
    r'\bcut\w*\b.*\b(yourself|myself)\b',
    r'\bself.?harm\w*\b',
    r'\bpain\b.*\b(endure|endurance|tolerate|most)\b',
    r'\b(most|longest)\b.*\bpain\b',
    r'\binjur\w*\b.*\b(most|first)\b',
    r'\bdeadly\b',
    r'\bkill\w*\b.*\b(yourself|myself|someone|people|them|him|her)\b',
  ]),
  _SafetyRule('gambling',
      "Races about gambling or betting money aren't allowed.", [
    r'\bgambl\w*\b',
    r'\bbet(ting)?\b.*\b(money|cash|most)\b',
    r'\b(most money)\b.*\b(bet|gambl|casino|poker)\b',
    r'\bcasino|poker|blackjack|roulette|slots?\b',
    r'\b(lottery|lotto|wager)\b',
  ]),
  _SafetyRule('sexual_content',
      'Races with sexual content are not allowed.', [
    r'\b(sex|sexual)\b',
    r'\b(naked|nudes?)\b',
    r'\b(hook ?up|kissing|kissed|kiss)\b',
    r'\b(onlyfans|porn\w*)\b',
  ]),
];

/// Evaluates free-text race content (title + custom activity name) against the
/// category policy. Call with the committed race name BEFORE creating a draft
/// or posting to the server.
RaceSafetyDecision evaluateRaceSafety(String raceText) {
  final normalized = _normalize(raceText);
  if (normalized.isEmpty) return const RaceSafetyDecision.allow();
  for (final rule in _rules) {
    for (final pattern in rule.patterns) {
      if (RegExp(pattern).hasMatch(normalized)) {
        return RaceSafetyDecision.reject(rule.category, rule.reason);
      }
    }
  }
  return const RaceSafetyDecision.allow();
}

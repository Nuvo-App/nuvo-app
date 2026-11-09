/// Onboarding-v2 copy — every user-facing string the flow owns, in one file
/// (shared constants may be edited only by Part 0 and Part E, per the build
/// plan). Voice: short, warm, direct, a little competitive; no exclamation
/// marks except level-up. Product language only (race, friend, crew, proof,
/// leaderboard, start line, finish line, submit proof, arena, member pass,
/// AI Motion Proof, invite code).
abstract final class ObCopy {
  // ── Shared chrome ──────────────────────────────────────────────────────
  static const String next = 'Next';
  static const String skip = 'Skip';
  static const String back = 'Back';
  static const String skipTour = 'Skip tour';
  static const String you = 'You';
  static const String practiceTag = 'Practice';
  static const String nuvoCrew = 'Nuvo Crew';

  // ── S1 Intro — Race anything ───────────────────────────────────────────
  static const String introRaceTitle = 'Race anything.';
  static const String introRaceSub =
      'Pushups, reading, anything. Beat your friends.';
  static const String introRaceHint = 'Tap the card as fast as you can';
  static const String introRaceWin = 'You won. That took 5 seconds.';

  // ── S2 Intro — Prove it on camera ──────────────────────────────────────
  static const String introCameraTitle = 'Prove it on camera.';
  static const String introCameraSub =
      'Nuvo counts every rep. No faking, no arguing.';
  static const String introCameraPill = 'AI Motion verified';

  // ── S3 Intro — Climb the board ─────────────────────────────────────────
  static const String introBoardTitle = 'Climb the board.';
  static const String introBoardSub =
      'Every proof moves you up. Friends see it live.';
  static const String introBoardCta = 'Create my player';
  static const String introBoardLogin = 'I already have an account';

  // ── S4 Sign in — "Save your spot" sheet ────────────────────────────────
  static const String signInTitle = 'Save your spot';
  static const String signInSub = 'So your races, friends and level are yours.';
  static const String signInApple = 'Continue with Apple';
  static const String signInGoogle = 'Continue with Google';
  static const String signInEmailLink = 'Use email instead';
  static const String signInLegal =
      'By continuing you agree to the Terms and Privacy Policy';

  // ── S5 Email — player pass ticket ──────────────────────────────────────
  static const String emailTitle = "What's your email?";
  static const String emailSub =
      'We send a 6 digit code. No password to remember.';
  static const String emailCta = 'Send code';
  static const String reviewerSignInCta = 'Sign in';
  static const String reviewerPasswordLabel = 'Password';
  static const String reviewerSignInFailed =
      'That password did not match. Try again.';
  static const String emailSending = 'Sending...';
  static const String emailDisabledHint = 'Enter your email';
  static const String emailFieldLabel = 'Email';
  static const String emailStampReady = 'Ready';
  static const String emailStampNotVerified = 'Not verified yet';
  static const String emailTypoHint = 'Did you mean gmail.com?';
  static const String playerPassLabel = 'PLAYER PASS';
  static const String emailStepCounter = 'Step 1 of 4';

  // ── S6 Code ────────────────────────────────────────────────────────────
  static const String codeTitle = 'Check your email.';
  static const String codeSub = 'Enter the 6 digit code.';
  static const String codeVerifying = 'Verifying...';
  static const String codeStampVerified = 'VERIFIED';
  static const String codeError = 'That code did not match. Try again.';
  static const String codeTooManyTries = 'Too many tries. Wait 1 minute.';
  static const String codeResendLink = "Didn't get it?";
  static const String codeResendNew = 'Send a new code';
  static String codeResendIn(int seconds) => 'Resend in ${seconds}s';
  static String codeSentTo(String email) => 'Code sent to $email';
  static const String codeChange = 'Change';
  // Part B additions (auth visuals).
  static String emailTypoHintFor(String domain) => 'Did you mean $domain?';
  static const String emailRateLimited =
      'Too many codes. Wait a minute and try again.';
  static const String emailSendFailed = 'Could not send code. Please try again.';
  static const String authOffline =
      "Can't reach Nuvo. Check your connection and try again.";
  static const String signInAppleFailed =
      'Apple Sign In was cancelled or failed.';
  static const String signInGoogleFailed =
      'Google sign-in failed. Please try again.';
  static String codePaste(String code) => 'Paste $code?';
  static const String codeNewSent = 'New code sent';
  static const String codeResendFailed = 'Could not send a new code. Try again.';
  static const String codeVerifyFailed =
      'Code accepted, but Nuvo could not finish sign-in. Try again.';
  static const String codeServerSnag = 'Nuvo hit a snag. Try again.';
  static const String codeVerifyCta = 'Verify';
  static const String codeTipsTitle = "Didn't get the code?";
  static const String codeTipSpam = 'Check your spam or promotions folder.';
  static const String codeTipEmail = 'Make sure the email above is right.';
  static const String codeTipChangeEmail = 'Change email';
  static const String codeTipSocial = 'Use Apple or Google instead';
  static const String codeTipsDone = 'Got it';

  // ── S7 Player card ─────────────────────────────────────────────────────
  static const String playerCardStepCounter = 'Step 2 of 4';
  static const String playerCardNameField = 'Name';
  static const String playerCardUsernameField = 'Username';
  static const String playerCardNameWhy = 'Friends find you by this';
  static const String playerCardUsernameWhy = 'Your @ for races and invites';
  static const String playerCardPhotoWhy = 'Faces make races real';
  static const String playerCardPhotoTake = 'Take photo';
  static const String playerCardPhotoChoose = 'Choose photo';
  static const String playerCardPhotoSkip = 'Skip';
  static const String playerCardTerms =
      "I'm 13 or older and I agree to the Terms, Privacy Policy and Guidelines";
  static const String playerCardCta = "That's me";
  static const String playerCardUsernameTaken = 'taken';
  static String playerCardUsernameSuggest(String alt) => 'try @$alt';
  static const String playerCardLevelPill = 'Level 1';

  // ── S8 Starter questions ───────────────────────────────────────────────
  static const String questionsTitle1 = 'What do you want to race?';
  static const String questionsTitle2 = 'Race solo or with friends?';
  static const String questionsSub =
      'This picks your first race. You can change anything later.';
  static const String q1Fitness = 'Fitness';
  static const String q1Running = 'Running';
  static const String q1Reading = 'Reading';
  static const String q1Studying = 'Studying';
  static const String q1Gaming = 'Gaming';
  static const String q1Other = 'Something else';
  static const String q2WithFriends = 'With friends';
  static const String q2Solo = 'Solo first';
  static const String q2Surprise = 'Surprise me';
  static String q1Preview(String activity) => '$activity Race';

  // ── S9 First race ready ────────────────────────────────────────────────
  static const String firstRaceBuilding = 'Building your first race...';
  static const String firstRaceLive = 'Practice race vs Nuvo Crew is live';
  static String practiceRaceName(String activity) =>
      '$activity Race · First to 10';

  // ── S10 Arena tour — practice race + first proof ───────────────────────
  static const String arenaTourCoach =
      'This is a race. You are 3rd. Beat them.';
  static const String arenaTourRank = '3rd place';
  static const String arenaTourCameraReason =
      'Nuvo counts your reps with the camera. Video stays on your phone.';
  static const String arenaTourSkipCamera = 'Skip camera for now';
  static String arenaTourPassed(String racer) => 'You passed $racer';
  static String arenaTourNudge(String racer) => '$racer passed you';
  static const String arenaTourTakeBack = 'Take it back';
  static const String arenaTourLesson =
      "That's how Nuvo works. Someone passes you, you take it back.";
  static const List<String> arenaTourEncouragement = [
    'Nice depth',
    'Keep going',
  ];

  // ── S11 Notification opt-in ────────────────────────────────────────────
  static const String notifyTitle = 'Want a buzz when someone passes you?';
  static const String notifyCta = 'Turn on notifications';
  static const String notifyLater = 'Maybe later';

  // ── S12–14 Tour ────────────────────────────────────────────────────────
  static String tourCounter(int index) => 'Tour $index of 3';
  static const String tourCompeteText = 'Compete is where races find you.';
  static const String tourCompeteMission =
      'Joined. You can start your own anytime with New race.';
  static const String tourCompeteJoined = 'Joined';
  static const String tourCompeteJoin = 'Join a race';
  static const String tourCrewText = 'Crew is your people.';
  static const String tourCrewBubble =
      'Anyone who scans this becomes your friend.';
  static const String tourCrewShare = 'Send this to one friend.';
  static const String tourProfileText = 'Profile is you.';
  static const String tourProfileShow = 'Show on profile';
  static const String tourDone = "That's the whole app. One more thing.";

  // ── S15 Level up ───────────────────────────────────────────────────────
  static const String levelUpTitle = 'LEVEL UP';
  static const String levelUpFrom = 'LEVEL 1';
  static const String levelUpTo = 'LEVEL 2';
  static const String levelUpXpTile = '+100 XP';
  static const String levelUpBadgeTile = 'Day One';
  static const String levelUpStreakTile = '1 day streak started';
  static const String levelUpCta = 'Enter the Arena';
  static const String levelUpShare = 'Share my level';
  static const String levelUpShareLine = 'Join me on Nuvo';

  // ── Generic errors (spec: coral inline, no dialogs) ────────────────────
  static const String genericRetry =
      'Could not finish. Check your connection and try again.';
}

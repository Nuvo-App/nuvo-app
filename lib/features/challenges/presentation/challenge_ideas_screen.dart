import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class ChallengeIdeasScreen extends StatelessWidget {
  const ChallengeIdeasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NuvoColors.page,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/arena'),
        ),
        title: const Text('Race ideas'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Compete on anything.\nWith anyone.',
                    style: AppTextStyles.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick an idea or build your own race.',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: NuvoColors.muted),
                  ),
                ],
              ),
            ),
          ),
          for (final section in _ideas)
            SliverToBoxAdapter(
              child: _IdeaSection(section: section),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _IdeaSection extends StatelessWidget {
  const _IdeaSection({required this.section});
  final _IdeaGroup section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: NuvoColors.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(section.icon, size: 14, color: NuvoColors.white),
              ),
              const SizedBox(width: 10),
              Text(
                section.category.toUpperCase(),
                style: AppTextStyles.labelSmall.copyWith(
                  letterSpacing: 1.4,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: section.ideas.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _IdeaChip(label: section.ideas[i]),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _IdeaChip extends StatelessWidget {
  const _IdeaChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/create'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: NuvoColors.sectionBlue,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NuvoColors.border),
        ),
        child: Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(color: NuvoColors.navy),
        ),
      ),
    );
  }
}

class _IdeaGroup {
  const _IdeaGroup(this.category, this.icon, this.ideas);
  final String category;
  final IconData icon;
  final List<String> ideas;
}

const _ideas = [
  _IdeaGroup('Fitness', Icons.fitness_center_rounded, [
    '100 pushups',
    'Run 5 miles',
    'Fastest mile',
    '10,000 steps daily',
    'Most workouts this month',
    'Plank challenge',
    'Pull-ups to failure',
    '30-day abs',
    'Swim 1 mile',
    'Squat 225 lbs',
    'Cold shower streak',
    'No rest days for 30 days',
    'Walk 5 miles daily',
    'Bike 100 miles in a week',
    'Handstand in 30 days',
  ]),
  _IdeaGroup('Learning', Icons.menu_book_rounded, [
    'Read 3 books',
    'Learn a language',
    'Complete a course',
    'Finish a textbook chapter',
    'Study 30 min daily',
    'Memorize 100 vocab words',
    'Watch zero TV for 30 days',
    'Learn to code in 60 days',
    'Master a card trick',
    'Learn 10 new recipes',
    'Pass a certification exam',
    'Read one article a day',
    'No Wikipedia rabbit holes',
    'Learn music theory basics',
    '30 day journal streak',
  ]),
  _IdeaGroup('Productivity', Icons.bolt_rounded, [
    'Wake up before 6 AM',
    'No social media challenge',
    'Build a daily habit',
    'Clean room streak',
    'Homework before 7 PM',
    'No phone in bed',
    'Inbox zero daily',
    'Plan your week every Sunday',
    'Deep work 2 hrs a day',
    'No Netflix for a month',
    'Write 500 words daily',
    'Make your bed every day',
    'Cook every meal for a week',
    'Go outside every day',
    'Screen time under 2 hrs',
  ]),
  _IdeaGroup('Personal Growth', Icons.self_improvement_rounded, [
    'Meditation streak',
    'Journaling streak',
    'Drink more water',
    'Sleep before 11 PM',
    'Gratitude log daily',
    'One act of kindness daily',
    'No complaining for a week',
    'Talk to a stranger daily',
    'Declutter one thing a day',
    'Take a cold shower',
    'Spend time in nature',
    'Digital detox weekends',
    'Practice deep breathing',
    'Affirmations daily',
    'Spend 1 hr with family daily',
  ]),
  _IdeaGroup('Skills', Icons.emoji_objects_rounded, [
    'Learn a song',
    'Build a project',
    'Practice coding daily',
    'Master a trick',
    'Create content daily',
    'Draw every day',
    'Practice a language 20 min',
    'Solve 1 LeetCode problem',
    'Ship a feature weekly',
    'Record a podcast episode',
    'Make a short film',
    'Design a logo from scratch',
    'Publish a blog post',
    'Grow to 100 followers',
    'Finish a side project',
  ]),
  _IdeaGroup('Custom', Icons.tune_rounded, [
    'Your own race',
    'Set your own rules',
    'Make it competitive',
    'Anything goes',
  ]),
];

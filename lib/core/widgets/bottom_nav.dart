import 'package:flutter/material.dart' show IconData, Icons;

/// One root destination of the app shell. THE canonical tab table: the
/// order of [nuvoDestinations] IS the index contract — nav highlight,
/// `MainShell`'s route mapping, the `StatefulShellRoute` branch order, and
/// `NuvoTabStack`'s transition direction all derive from this single list.
/// 0 Arena · 1 Compete · 2 Friends · 3 Profile.
///
/// There is no Verify tab: starting a proof lives on Race Detail
/// (`/race/:id`), `/race/:id/proof` and `/race/:id/proof/ai-motion`.
///
/// The shell's rendered bar is `V13TabBar` (lib/core/v13); this file only
/// carries the shared destination contract.
class NuvoDestination {
  const NuvoDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const nuvoDestinations = <NuvoDestination>[
  NuvoDestination(
    path: '/arena',
    label: 'Arena',
    icon: Icons.stadium_outlined,
    selectedIcon: Icons.stadium,
  ),
  NuvoDestination(
    path: '/compete',
    label: 'Compete',
    icon: Icons.emoji_events_outlined,
    selectedIcon: Icons.emoji_events,
  ),
  NuvoDestination(
    path: '/pass',
    label: 'Friends',
    icon: Icons.group_outlined,
    selectedIcon: Icons.group,
  ),
  NuvoDestination(
    path: '/profile',
    label: 'Profile',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
  ),
];

/// v13 destinations. Same paths and branch order as [nuvoDestinations] — the
/// third tab keeps its `/pass` route (auth_gate protects `/pass`; `/crew`
/// redirects to it) but is labelled "Crew" and holds friends + crews.
const v13Destinations = <NuvoDestination>[
  NuvoDestination(
    path: '/arena',
    label: 'Arena',
    icon: Icons.stadium_outlined,
    selectedIcon: Icons.stadium,
  ),
  NuvoDestination(
    path: '/compete',
    label: 'Compete',
    icon: Icons.emoji_events_outlined,
    selectedIcon: Icons.emoji_events,
  ),
  NuvoDestination(
    path: '/pass',
    label: 'Crew',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
  ),
  NuvoDestination(
    path: '/profile',
    label: 'Profile',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
  ),
];

/// The destination table the shell uses.
const activeDestinations = v13Destinations;

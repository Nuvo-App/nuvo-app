class Friend {
  const Friend({
    required this.name,
    required this.username,
    required this.status,
    required this.initials,
    this.selected = false,
  });

  final String name;
  final String username;
  final String status;
  final String initials;
  final bool selected;

  Friend copyWith({bool? selected}) => Friend(
    name: name,
    username: username,
    status: status,
    initials: initials,
    selected: selected ?? this.selected,
  );
}

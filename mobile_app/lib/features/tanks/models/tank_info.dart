class TankInfo {
  const TankInfo({
    required this.initial,
    required this.name,
    required this.subtitle,
    required this.status,
    required this.health,
    required this.typeLabel,
    required this.volumeLabel,
    required this.lastFedLabel,
    required this.description,
    this.isSelected = false,
  });

  final String initial;
  final String name;
  final String subtitle;
  final String status;
  final int health;
  final String typeLabel;
  final String volumeLabel;
  final String lastFedLabel;
  final String description;
  final bool isSelected;
}

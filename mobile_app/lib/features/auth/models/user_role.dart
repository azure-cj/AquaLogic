enum UserRole {
  admin,
  staff;

  /// The value used by the current AquaLogic backend role model.
  String get backendValue => name;

  /// The role name presented in the mobile product.
  String get displayLabel => switch (this) {
    UserRole.admin => 'Owner',
    UserRole.staff => 'Staff',
  };

  String get badgeLabel => displayLabel.toUpperCase();
}

enum RateCategory {
  walling('Walling'),
  concrete('Concrete'),
  formwork('Formwork'),
  finishes('Finishes'),
  flooring('Flooring'),
  roofing('Roofing'),
  earthworks('Earthworks'),
  externalWorks('External Works'),
  services('Services'),
  custom('Custom');

  const RateCategory(this.label);
  final String label;

  static RateCategory fromValue(String value) => RateCategory.values.firstWhere(
    (item) =>
        item.name == value || item.label.toLowerCase() == value.toLowerCase(),
    orElse: () => RateCategory.custom,
  );
}

enum RateComponentType {
  material('Materials'),
  labour('Labour'),
  plant('Plant / equipment'),
  transport('Transport'),
  subcontract('Subcontract'),
  other('Other costs');

  const RateComponentType(this.label);
  final String label;

  static RateComponentType fromValue(String value) =>
      RateComponentType.values.firstWhere(
        (item) => item.name == value,
        orElse: () => RateComponentType.other,
      );
}

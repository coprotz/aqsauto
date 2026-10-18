import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:aqs/features/build_up_rates/models/rate_resource.dart';
import 'package:aqs/features/build_up_rates/services/rate_preset_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = RatePresetService();

  test('builds the 150 mm blockwork quantities per square metre', () {
    final preset = service.build('150 mm block wall')!;
    final blocks = preset.components.singleWhere(
      (item) => item.name == '150 mm concrete block',
    );
    final cement = preset.components.singleWhere(
      (item) => item.name == 'Cement (50 kg bag)',
    );
    final sand = preset.components.singleWhere(
      (item) => item.name == 'Mortar sand',
    );

    expect(blocks.quantity, 9);
    expect(blocks.wastePercent, 5);
    expect(cement.quantity, closeTo(0.1533, 0.0001));
    expect(sand.quantity, closeTo(0.02128, 0.00001));
    expect(preset.overheads, 15);
    expect(preset.profit, 10);
  });

  test('uses matching Resource Library prices', () {
    const resources = [
      RateResource(
        resourceId: 'cement',
        name: 'Cement',
        category: RateComponentType.material,
        unit: 'bag',
        currentRate: 18000,
      ),
      RateResource(
        resourceId: 'mason',
        name: 'Mason',
        category: RateComponentType.labour,
        unit: 'day',
        currentRate: 50000,
      ),
    ];
    final preset = service.build('150 mm block wall', resources: resources)!;

    expect(
      preset.components
          .singleWhere((item) => item.name.contains('Cement'))
          .unitRate,
      18000,
    );
    expect(
      preset.components.singleWhere((item) => item.name == 'Mason').unitRate,
      50000,
    );
  });

  test('builds reinforcement per kilogram from tonne and hourly prices', () {
    const resources = [
      RateResource(
        resourceId: 'steel',
        name: 'Reinforcement steel',
        category: RateComponentType.material,
        unit: 'tonne',
        currentRate: 1500000,
      ),
      RateResource(
        resourceId: 'wire',
        name: 'Binding wire',
        category: RateComponentType.material,
        unit: 'kg',
        currentRate: 3500,
      ),
    ];
    final preset =
        service.build('Reinforcement steel fixing', resources: resources)!;

    expect(preset.outputUnit, 'kg');
    expect(preset.overheads, 15);
    expect(preset.profit, 10);
    expect(
      preset.components
          .singleWhere((item) => item.name == 'Reinforcement steel')
          .quantity,
      0.001,
    );
    expect(
      preset.components
          .singleWhere((item) => item.name == 'Binding wire')
          .quantity,
      0.01,
    );
    expect(
      preset.components
          .singleWhere((item) => item.name == 'Steel fixer')
          .quantity,
      0.06,
    );
    expect(
      preset.components
          .singleWhere((item) => item.name == 'General labourer')
          .quantity,
      0.12,
    );
    expect(
      preset.components
          .singleWhere((item) => item.type == RateComponentType.transport)
          .amount,
      closeTo(((1500000 * 0.001 * 1.05) + (3500 * 0.01)) * 0.2, 0.001),
    );
  });

  test('builds the supplied earthworks productivity templates', () {
    final clearance = service.build('Site clearance')!;
    final excavation =
        service.build('Excavate trench not exceeding 1.5 m deep')!;
    final backfill =
        service.build('Return, fill and compact excavated material')!;
    final disposal =
        service.build('Dispose excavated material away from site')!;
    final imported = service.build('Imported backfill')!;

    expect(clearance.outputUnit, 'm²');
    expect(
      clearance.components
          .singleWhere((item) => item.name == 'General labourer')
          .quantity,
      closeTo(0.4, 0.0001),
    );
    expect(
      excavation.components
          .singleWhere((item) => item.name == 'General labourer')
          .quantity,
      closeTo(3.2, 0.0001),
    );
    expect(
      backfill.components
          .singleWhere((item) => item.name == 'Hand tools')
          .quantity,
      closeTo(0.25, 0.0001),
    );
    expect(
      disposal.components
          .singleWhere((item) => item.name == 'Tipper haul')
          .quantity,
      closeTo(0.25, 0.0001),
    );
    expect(imported.outputUnit, 'm³');
    expect(
      imported.components
          .singleWhere((item) => item.name == 'Selected fill material')
          .quantity,
      1,
    );
    expect(
      imported.components
          .singleWhere((item) => item.name == 'Compaction allowance')
          .quantity,
      0.2,
    );
    expect(
      imported.components
          .singleWhere((item) => item.name == 'Roller and watering')
          .quantity,
      closeTo(1 / 60, 0.000001),
    );
    expect(imported.overheads, 15);
    expect(imported.profit, 10);
  });

  test('builds hardcore filling and anti-termite treatment', () {
    final hardcore = service.build('Hardcore filling')!;
    final treatment = service.build('Anti-termite treatment')!;

    expect(hardcore.outputUnit, 'm³');
    expect(hardcore.overheads, 10);
    expect(hardcore.profit, 6);
    final stone = hardcore.components.singleWhere(
      (item) => item.name == 'Hardcore stone',
    );
    expect(stone.quantity, 1.25);
    expect(stone.wastePercent, 5);
    expect(
      hardcore.components
          .singleWhere((item) => item.name == 'General labourer')
          .quantity,
      2,
    );

    expect(treatment.outputUnit, 'm²');
    expect(treatment.overheads, 15);
    expect(treatment.profit, 10);
    final chemical = treatment.components.singleWhere(
      (item) => item.name == 'Soil insecticide',
    );
    expect(chemical.quantity, 7);
    expect(chemical.wastePercent, 2.5);
    expect(
      treatment.components
          .singleWhere((item) => item.name == 'Skilled applicator')
          .quantity,
      0.4,
    );
    expect(
      treatment.components
          .singleWhere((item) => item.name == 'Other materials allowance')
          .quantity,
      0.1,
    );
  });

  test('uses the same analysis with separate painting resource prices', () {
    const resources = [
      RateResource(
        resourceId: 'silk',
        name: 'Silk paint',
        category: RateComponentType.material,
        unit: 'litre',
        currentRate: 12000,
      ),
      RateResource(
        resourceId: 'weather',
        name: 'Weatherguard paint',
        category: RateComponentType.material,
        unit: 'litre',
        currentRate: 18000,
      ),
    ];
    final silk = service.build('Silk painting', resources: resources)!;
    final weather =
        service.build('Weatherguard painting', resources: resources)!;

    for (final preset in [silk, weather]) {
      expect(preset.outputUnit, 'm²');
      expect(preset.overheads, 15);
      expect(preset.profit, 10);
      expect(preset.components.first.quantity, 0.33);
      expect(preset.components.first.wastePercent, 10);
      expect(
        preset.components
            .singleWhere((item) => item.name == 'Skilled painter')
            .quantity,
        0.44,
      );
      expect(
        preset.components
            .singleWhere((item) => item.name == 'General labourer')
            .quantity,
        0.44,
      );
      expect(
        preset.components
            .singleWhere((item) => item.name == 'Painting sundries allowance')
            .quantity,
        0.2,
      );
    }
    expect(silk.components.first.unitRate, 12000);
    expect(weather.components.first.unitRate, 18000);
  });

  test('builds Class 20 and Class 25 concrete per cubic metre', () {
    final class20 = service.build('Class 20 concrete')!;
    final class25 = service.build('Class 25 concrete')!;

    for (final preset in [class20, class25]) {
      expect(preset.outputUnit, 'm³');
      expect(preset.overheads, 15);
      expect(preset.profit, 10);
      expect(
        preset.components
            .singleWhere((item) => item.name == 'Mixer operator')
            .quantity,
        closeTo(1 / 2.4, 0.000001),
      );
      expect(
        preset.components
            .singleWhere((item) => item.name == 'General labourer')
            .quantity,
        closeTo(7 / 2.4, 0.000001),
      );
      expect(
        preset.components
            .singleWhere(
              (item) => item.name == 'Concrete mixer (350–500 litre)',
            )
            .quantity,
        closeTo(1 / 2.4, 0.000001),
      );
    }
    expect(
      class20.components
          .singleWhere((item) => item.name == 'Cement (50 kg bag)')
          .quantity,
      6.34,
    );
    expect(
      class20.components
          .singleWhere((item) => item.name == 'Coarse aggregate')
          .quantity,
      0.88,
    );
    expect(
      class25.components
          .singleWhere((item) => item.name == 'Cement (50 kg bag)')
          .quantity,
      8.06,
    );
    expect(
      class25.components
          .singleWhere((item) => item.name == 'Coarse aggregate')
          .quantity,
      0.84,
    );
  });

  test('builds Class 15, 30, 35 and 40 concrete baselines per cubic metre', () {
    final class15 = service.build('Class 15 concrete')!;
    final class30 = service.build('Class 30 concrete')!;
    final class35 = service.build('Class 35 concrete')!;
    final class40 = service.build('Class 40 concrete')!;

    for (final preset in [class15, class30, class35, class40]) {
      expect(preset.outputUnit, 'm³');
      expect(preset.overheads, 15);
      expect(preset.profit, 10);
      expect(preset.components.length, 10);
    }
    expect(class15.components.first.quantity, 4.44);
    expect(class15.components[1].quantity, 0.462);
    expect(class15.components[2].quantity, 0.924);
    expect(class30.components.first.quantity, 11.09);
    expect(class30.components[1].quantity, 0.578);
    expect(class30.components[2].quantity, 0.578);
    expect(
      class30.components.singleWhere((item) => item.name == 'Water').quantity,
      180,
    );
    expect(class35.components.first.quantity, 12.67);
    expect(class35.components[1].quantity, 0.44);
    expect(class35.components[2].quantity, 0.66);
    expect(
      class35.components.singleWhere((item) => item.name == 'Water').quantity,
      180,
    );
    expect(class40.components.first.quantity, 14.78);
    expect(class40.components[1].quantity, 0.513);
    expect(class40.components[2].quantity, 0.513);
    expect(class30.components.first.description, contains('trial mix'));
    expect(class35.components.first.description, contains('trial mix'));
    expect(class40.components.first.description, contains('laboratory'));
    for (final preset in [class15, class30, class35, class40]) {
      expect(
        preset.components.any(
          (item) => item.name == 'Formwork material allowance',
        ),
        isFalse,
      );
    }
  });

  test('builds column formwork per square metre with timber reuse', () {
    final preset = service.build('Sawn formwork to vertical sides of columns')!;

    expect(preset.outputUnit, 'm²');
    expect(preset.overheads, 15);
    expect(preset.profit, 10);
    expect(preset.components.first.quantity, 0.5);
    expect(preset.components.first.wastePercent, 10);
    expect(preset.components[1].quantity, 3.5);
    expect(
      preset.components
          .singleWhere((item) => item.name == 'Skilled carpenter')
          .quantity,
      1.8,
    );
    expect(
      preset.components
          .singleWhere((item) => item.name == 'General labourer')
          .quantity,
      1.8,
    );
    expect(
      preset.components
          .singleWhere((item) => item.name == 'Formwork incidentals')
          .quantity,
      0.15,
    );
  });

  test('builds plastering and 25 mm screed per square metre', () {
    final plastering = service.build('Internal plastering')!;
    final screed = service.build('25 mm cement-sand floor screed')!;

    for (final preset in [plastering, screed]) {
      expect(preset.outputUnit, 'm²');
      expect(preset.overheads, 15);
      expect(preset.profit, 10);
      expect(preset.components.first.wastePercent, 5);
      expect(
        preset.components
            .singleWhere((item) => item.name == 'Skilled plasterer')
            .quantity,
        0.75,
      );
      expect(
        preset.components
            .singleWhere((item) => item.name == 'General labourer')
            .quantity,
        0.75,
      );
    }
    expect(plastering.components.first.quantity, 0.2);
    expect(plastering.components[1].quantity, 0.03);
    expect(screed.components.first.quantity, 0.4);
    expect(screed.components[1].quantity, 0.05);
  });

  test('builds ceramic floor tiles per square metre', () {
    final preset = service.build('Ceramic floor tiles')!;

    expect(preset.outputUnit, 'm²');
    expect(preset.overheads, 15);
    expect(preset.profit, 10);
    expect(preset.components.first.quantity, 11);
    expect(
      preset.components
          .singleWhere((item) => item.name == 'White cement')
          .quantity,
      0.025,
    );
    expect(
      preset.components
          .singleWhere((item) => item.name.startsWith('Portland cement'))
          .quantity,
      0.05,
    );
    expect(
      preset.components
          .singleWhere((item) => item.name == 'Skilled tiler')
          .quantity,
      11,
    );
    expect(
      preset.components
          .singleWhere((item) => item.name == 'Material transport allowance')
          .quantity,
      0.1,
    );
  });

  test('builds 300 mm random-rubble stone walling per square metre', () {
    final preset = service.build('Stone walling')!;

    expect(preset.outputUnit, 'm²');
    expect(preset.overheads, 0);
    expect(preset.profit, 0);
    expect(preset.components.first.quantity, closeTo(0.348, 0.000001));
    expect(
      preset.components
          .singleWhere((item) => item.name == 'Cement (50 kg bag)')
          .quantity,
      closeTo(0.542, 0.001),
    );
    expect(
      preset.components
          .singleWhere((item) => item.name == 'Masonry sand')
          .quantity,
      closeTo(0.1129, 0.0001),
    );
    expect(
      preset.components
          .singleWhere((item) => item.name == 'Stone mason')
          .quantity,
      closeTo(2.568, 0.000001),
    );
    expect(
      preset.components
          .singleWhere((item) => item.name == 'General labourer')
          .quantity,
      closeTo(4.272, 0.000001),
    );
  });
}

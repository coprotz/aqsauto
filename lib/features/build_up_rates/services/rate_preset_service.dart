import 'package:aqs/features/build_up_rates/models/rate_category.dart';
import 'package:aqs/features/build_up_rates/models/rate_component.dart';
import 'package:aqs/features/build_up_rates/models/rate_resource.dart';
import 'package:uuid/uuid.dart';

class RatePreset {
  const RatePreset({
    required this.components,
    this.overheads = 15,
    this.profit = 10,
    this.outputUnit = 'm²',
  });

  final List<RateComponent> components;
  final double overheads;
  final double profit;
  final String outputUnit;
}

class RatePresetService {
  const RatePresetService();

  RatePreset? build(
    String activity, {
    List<RateResource> resources = const [],
  }) {
    return switch (activity) {
      '150 mm block wall' => _blockwork(
        blockName: '150 mm concrete block',
        blocksPerSquareMetre: 9,
        wetMortarPerSquareMetre: 0.02,
        resources: resources,
      ),
      '230 mm block wall' => _blockwork(
        blockName: '230 mm concrete block',
        blocksPerSquareMetre: 14,
        wetMortarPerSquareMetre: 0.03,
        resources: resources,
      ),
      'Stone walling' => _stoneWalling(resources),
      'Reinforcement steel fixing' => _reinforcement(resources),
      '16 mm diameter mild-steel reinforcement' => _reinforcement(resources),
      'Site clearance' => _earthwork(
        resources: resources,
        outputUnit: 'm²',
        labourHours: 0.4,
        toolDays: 0.05,
        note: '150 mm average clearance depth; labour output 3 m³/day.',
      ),
      'Excavate trench not exceeding 1.5 m deep' => _earthwork(
        resources: resources,
        labourHours: 3.2,
        toolDays: 0.4,
        note: 'Manual trench and pit excavation output 2.5 m³/day.',
      ),
      'Return, fill and compact excavated material' => _earthwork(
        resources: resources,
        labourHours: 2,
        toolDays: 0.25,
        note: 'Return fill, consolidate and compact; output 4 m³/day.',
      ),
      'Dispose excavated material away from site' => _earthwork(
        resources: resources,
        labourHours: 16 / 9,
        toolDays: 2 / 9,
        tipperTrips: 0.25,
        note: 'Loading output 4.5 m³/day; one tipper trip carries 4 m³.',
      ),
      'Imported backfill' => _importedBackfill(resources),
      'Hardcore filling' => _hardcoreFilling(resources),
      'Anti-termite treatment' => _antiTermiteTreatment(resources),
      'Emulsion painting' => _painting(
        resources,
        paintName: 'Emulsion paint',
        aliases: const ['emulsion paint', 'emulsion'],
      ),
      'Silk painting' => _painting(
        resources,
        paintName: 'Silk paint',
        aliases: const ['silk paint', 'silk emulsion'],
      ),
      'Weatherguard painting' => _painting(
        resources,
        paintName: 'Weatherguard paint',
        aliases: const [
          'weatherguard paint',
          'weather guard paint',
          'exterior paint',
        ],
      ),
      'Internal plastering' => _cementSandFinish(
        resources,
        cementBags: 0.2,
        sandVolume: 0.03,
        description: 'Two-coat plastering, steel-trowelled smooth.',
      ),
      '25 mm cement-sand floor screed' ||
      'Cement-sand screed' => _cementSandFinish(
        resources,
        cementBags: 0.4,
        sandVolume: 0.05,
        description: '25 mm thick cement-sand floor screed.',
      ),
      'Floor tiles' || 'Ceramic floor tiles' => _ceramicFloorTiles(resources),
      'Class 15 concrete' => _concrete(
        resources,
        cementBags: 4.44,
        sandVolume: 0.462,
        aggregateVolume: 0.924,
        waterLitres: 120,
        mixDescription:
            'Class 15 nominal-mix budget baseline (approximately 1:3:6).',
      ),
      'Class 20 concrete' => _concrete(
        resources,
        cementBags: 6.34,
        sandVolume: 0.44,
        aggregateVolume: 0.88,
        waterLitres: 158.5,
        mixDescription:
            'Class 20 nominal-mix baseline (1:2:4), calculated using a 1.54 dry-volume factor and a 0.50 water-cement ratio.',
      ),
      'Class 25 concrete' => _concrete(
        resources,
        cementBags: 8.06,
        sandVolume: 0.42,
        aggregateVolume: 0.84,
        waterLitres: 181.5,
        mixDescription:
            'Class 25 nominal-mix baseline (1:1.5:3), calculated using a 1.54 dry-volume factor and a 0.45 water-cement ratio. Verify with an approved trial mix.',
      ),
      'Class 30 concrete' => _concrete(
        resources,
        cementBags: 11.09,
        sandVolume: 0.578,
        aggregateVolume: 0.578,
        waterLitres: 180,
        mixDescription:
            'Estimating allowance based on a 1:1.5:1.5 volumetric ratio and a 1.54 dry-volume factor. Class 30 must be verified by an approved laboratory trial mix.',
      ),
      'Class 35 concrete' => _concrete(
        resources,
        cementBags: 12.67,
        sandVolume: 0.44,
        aggregateVolume: 0.66,
        waterLitres: 180,
        mixDescription:
            'Estimating allowance based on a 1:1:1.5 volumetric ratio and a 1.54 dry-volume factor. Class 35 must be verified by an approved laboratory trial mix.',
      ),
      'Class 40 concrete' => _concrete(
        resources,
        cementBags: 14.78,
        sandVolume: 0.513,
        aggregateVolume: 0.513,
        waterLitres: 180,
        mixDescription:
            'Estimating allowance based on a 1:1:1 volumetric ratio and a 1.54 dry-volume factor. Class 40 must be verified by an approved laboratory trial mix.',
      ),
      'Sawn formwork to vertical sides of columns' => _columnFormwork(
        resources,
      ),
      _ => null,
    };
  }

  RatePreset _stoneWalling(List<RateResource> resources) {
    // Government rate-analysis basis: random-rubble masonry in 1:6 cement
    // mortar, analysed per m³. Factors below are converted to a 300 mm-thick
    // wall measured per m². An eight-hour working day is used for labour.
    const wallVolume = 0.3;
    const mortarPerCubicMetre = 0.33;
    const dryMortarFactor = 1.33;
    const cementBagVolume = 0.0347;
    const dryMortar = wallVolume * mortarPerCubicMetre * dryMortarFactor;
    const cementBags = (dryMortar / 7) / cementBagVolume;
    const sandVolume = dryMortar * 6 / 7;
    final components = <RateComponent>[
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'Hard masonry stone',
        description:
            'Random-rubble stone including through/bond stones for a 300 mm-thick wall.',
        unit: 'm³',
        quantity: 1.16 * wallVolume,
        unitRate: _findRate(
          resources,
          RateComponentType.material,
          const [
            'hard masonry stone',
            'random rubble stone',
            'rubble stone',
            'building stone',
          ],
          allowedUnits: const ['m³', 'm3'],
        ),
        wastePercent: 5,
        sortOrder: 0,
      ),
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'Cement (50 kg bag)',
        description: 'Cement mortar 1:6 for random-rubble masonry.',
        unit: 'bag',
        quantity: cementBags,
        unitRate: _findRate(
          resources,
          RateComponentType.material,
          const ['cement', 'cement 50kg', 'cement 50 kg'],
          allowedUnits: const ['bag'],
        ),
        wastePercent: 5,
        sortOrder: 1,
      ),
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'Masonry sand',
        description: 'Sand for 1:6 cement mortar.',
        unit: 'm³',
        quantity: sandVolume,
        unitRate: _findRate(
          resources,
          RateComponentType.material,
          const ['masonry sand', 'mortar sand', 'sand'],
          allowedUnits: const ['m³', 'm3'],
        ),
        wastePercent: 5,
        sortOrder: 2,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'Stone mason',
        aliases: const ['stone mason', 'mason', 'skilled labour'],
        unit: 'hr',
        quantity: 1.07 * 8 * wallVolume,
        description: 'Government analysis factor converted from person-days.',
        sortOrder: 3,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'General labourer',
        aliases: const ['general labourer', 'labourer', 'unskilled labour'],
        unit: 'hr',
        quantity: (1.07 + 0.71) * 8 * wallVolume,
        description:
            'Beldar and coolie labour combined and converted to hours.',
        sortOrder: 4,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'Water carrier',
        aliases: const ['water carrier', 'bhishti', 'general labourer'],
        unit: 'hr',
        quantity: 0.09 * 8 * wallVolume,
        description: 'Watering and curing labour converted to hours.',
        sortOrder: 5,
      ),
    ];
    final directCost = components.fold<double>(
      0,
      (sum, component) => sum + component.amount,
    );
    components.addAll([
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.other,
        name: 'Water and sundries allowance',
        description:
            'Calculated automatically: 1% for water charges and masonry sundries.',
        unit: '%',
        quantity: 0.01,
        unitRate: directCost,
        sortOrder: 6,
      ),
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.other,
        name: 'Contractor overhead and profit',
        description:
            'Calculated automatically: 10% contractor overhead and profit allowance.',
        unit: '%',
        quantity: 0.1,
        unitRate: directCost * 1.01,
        sortOrder: 7,
      ),
    ]);
    return RatePreset(
      components: components,
      overheads: 0,
      profit: 0,
      outputUnit: 'm²',
    );
  }

  RatePreset _ceramicFloorTiles(List<RateResource> resources) {
    final components = <RateComponent>[
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'Ceramic floor tile (300 × 300 mm)',
        description: 'Eleven 300 × 300 mm tiles per m².',
        unit: 'pc',
        quantity: 11,
        unitRate: _findRate(
          resources,
          RateComponentType.material,
          const [
            'ceramic floor tile 300 x 300',
            'ceramic floor tiles',
            'floor tile',
          ],
          allowedUnits: const ['pc', 'pcs', 'item'],
        ),
        sortOrder: 0,
      ),
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'White cement',
        description: 'Jointing allowance per m² of tiled floor.',
        unit: 'bag',
        quantity: 0.025,
        unitRate: _findRate(
          resources,
          RateComponentType.material,
          const ['white cement'],
          allowedUnits: const ['bag'],
        ),
        sortOrder: 1,
      ),
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'Portland cement (50 kg bag)',
        description: 'Bedding allowance per m² of tiled floor.',
        unit: 'bag',
        quantity: 0.05,
        unitRate: _findRate(
          resources,
          RateComponentType.material,
          const ['portland cement', 'cement', 'cement 50kg', 'cement 50 kg'],
          allowedUnits: const ['bag'],
        ),
        wastePercent: 5,
        sortOrder: 2,
      ),
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.transport,
        name: 'Material transport allowance',
        description: 'Calculated automatically: 10% of tile material cost.',
        unit: '%',
        quantity: 0.1,
        unitRate: 0,
        sortOrder: 3,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'Skilled tiler',
        aliases: const ['skilled tiler', 'tiler', 'tile layer'],
        unit: 'pc',
        quantity: 11,
        description: 'Skilled fixing labour priced per tile.',
        sortOrder: 4,
      ),
    ];
    final materialCost = components
        .where((component) => component.type == RateComponentType.material)
        .fold<double>(0, (sum, component) => sum + component.amount);
    components[3] = components[3].copyWith(unitRate: materialCost);
    return RatePreset(
      components: components,
      overheads: 15,
      profit: 10,
      outputUnit: 'm²',
    );
  }

  RatePreset _cementSandFinish(
    List<RateResource> resources, {
    required double cementBags,
    required double sandVolume,
    required String description,
  }) => RatePreset(
    components: [
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'Cement (50 kg bag)',
        description: description,
        unit: 'bag',
        quantity: cementBags,
        unitRate: _findRate(
          resources,
          RateComponentType.material,
          const ['cement', 'cement 50kg', 'cement 50 kg'],
          allowedUnits: const ['bag'],
        ),
        wastePercent: 5,
        sortOrder: 0,
      ),
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'Plastering sand',
        description: description,
        unit: 'm³',
        quantity: sandVolume,
        unitRate: _findRate(
          resources,
          RateComponentType.material,
          const ['plastering sand', 'sand', 'fine sand'],
          allowedUnits: const ['m³', 'm3'],
        ),
        wastePercent: 5,
        sortOrder: 1,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'Skilled plasterer',
        aliases: const ['skilled plasterer', 'plasterer', 'skilled labour'],
        unit: 'hr',
        quantity: 0.75,
        description: 'Skilled labour allowance per m².',
        sortOrder: 2,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'General labourer',
        aliases: const ['general labourer', 'labourer', 'unskilled labour'],
        unit: 'hr',
        quantity: 0.75,
        description: 'Unskilled labour allowance per m².',
        sortOrder: 3,
      ),
    ],
    overheads: 15,
    profit: 10,
    outputUnit: 'm²',
  );

  RatePreset _columnFormwork(List<RateResource> resources) {
    final components = <RateComponent>[
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'Sawn timber board (25 × 230 × 4000 mm)',
        description:
            'One board covers approximately 0.92 m². Quantity allows for 50% timber reuse.',
        unit: 'pc',
        quantity: 0.5,
        unitRate: _findRate(
          resources,
          RateComponentType.material,
          const [
            'sawn timber board 25 230 4000',
            'timber board 25 x 230 x 4000',
            'formwork timber board',
          ],
          allowedUnits: const ['pc', 'pcs', 'item'],
        ),
        wastePercent: 10,
        sortOrder: 0,
      ),
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'Props and braces (50 × 50 × 4000 mm)',
        description:
            'Props, braces and column supports. Quantity allows for 50% timber reuse.',
        unit: 'pc',
        quantity: 3.5,
        unitRate: _findRate(
          resources,
          RateComponentType.material,
          const [
            'props and braces',
            'timber board 50 x 50 x 4000',
            'formwork props',
          ],
          allowedUnits: const ['pc', 'pcs', 'item'],
        ),
        wastePercent: 10,
        sortOrder: 1,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'Skilled carpenter',
        aliases: const ['skilled carpenter', 'carpenter', 'skilled labour'],
        unit: 'hr',
        quantity: 1.8,
        description: 'Skilled labour allowance per m² of column formwork.',
        sortOrder: 2,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'General labourer',
        aliases: const ['general labourer', 'labourer', 'unskilled labour'],
        unit: 'hr',
        quantity: 1.8,
        description: 'Unskilled labour allowance per m² of column formwork.',
        sortOrder: 3,
      ),
    ];
    final directCost = components.fold<double>(
      0,
      (sum, component) => sum + component.amount,
    );
    components.add(
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.other,
        name: 'Formwork incidentals',
        description:
            'Calculated automatically: 15% for transport, nails and related incidentals.',
        unit: '%',
        quantity: 0.15,
        unitRate: directCost,
        sortOrder: 4,
      ),
    );
    return RatePreset(
      components: components,
      overheads: 15,
      profit: 10,
      outputUnit: 'm²',
    );
  }

  RatePreset _concrete(
    List<RateResource> resources, {
    required double cementBags,
    required double sandVolume,
    required double aggregateVolume,
    required String mixDescription,
    double waterLitres = 120,
  }) {
    const mixerHours = 1 / 2.4;
    return RatePreset(
      components: [
        RateComponent(
          componentId: const Uuid().v4(),
          type: RateComponentType.material,
          name: 'Cement (50 kg bag)',
          description: mixDescription,
          unit: 'bag',
          quantity: cementBags,
          unitRate: _findRate(
            resources,
            RateComponentType.material,
            const ['cement', 'cement 50kg', 'cement 50 kg'],
            allowedUnits: const ['bag'],
          ),
          wastePercent: 5,
          sortOrder: 0,
        ),
        RateComponent(
          componentId: const Uuid().v4(),
          type: RateComponentType.material,
          name: 'Concrete sand',
          description: mixDescription,
          unit: 'm³',
          quantity: sandVolume,
          unitRate: _findRate(
            resources,
            RateComponentType.material,
            const ['concrete sand', 'sand'],
            allowedUnits: const ['m³', 'm3'],
          ),
          wastePercent: 5,
          sortOrder: 1,
        ),
        RateComponent(
          componentId: const Uuid().v4(),
          type: RateComponentType.material,
          name: 'Coarse aggregate',
          description: mixDescription,
          unit: 'm³',
          quantity: aggregateVolume,
          unitRate: _findRate(
            resources,
            RateComponentType.material,
            const ['coarse aggregate', 'aggregates', 'aggregate'],
            allowedUnits: const ['m³', 'm3'],
          ),
          wastePercent: 5,
          sortOrder: 2,
        ),
        _resourceComponent(
          resources: resources,
          type: RateComponentType.material,
          name: 'Water',
          aliases: const ['water'],
          unit: 'litre',
          quantity: waterLitres,
          sortOrder: 3,
        ),
        _resourceComponent(
          resources: resources,
          type: RateComponentType.transport,
          name: 'Material haulage and handling',
          aliases: const [
            'material haulage and handling',
            'concrete material handling',
          ],
          unit: 'm³',
          quantity: 1,
          description:
              'Combined delivery and site-handling charge per m³ of concrete.',
          sortOrder: 4,
        ),
        _resourceComponent(
          resources: resources,
          type: RateComponentType.labour,
          name: 'Mixer operator',
          aliases: const ['mixer operator', 'operator'],
          unit: 'hr',
          quantity: mixerHours,
          description: 'One operator; mixer output 2.4 m³/hour.',
          sortOrder: 5,
        ),
        _resourceComponent(
          resources: resources,
          type: RateComponentType.labour,
          name: 'General labourer',
          aliases: const ['general labourer', 'labourer', 'unskilled labour'],
          unit: 'hr',
          quantity: 7 / 2.4,
          description: 'Seven labourers; mixer output 2.4 m³/hour.',
          sortOrder: 6,
        ),
        _resourceComponent(
          resources: resources,
          type: RateComponentType.plant,
          name: 'Concrete mixer (350–500 litre)',
          aliases: const ['concrete mixer', 'mixer 350 500 litre', 'mixer'],
          unit: 'hr',
          quantity: mixerHours,
          sortOrder: 7,
        ),
        _resourceComponent(
          resources: resources,
          type: RateComponentType.plant,
          name: 'Concrete vibrator',
          aliases: const ['concrete vibrator', 'vibrator'],
          unit: 'hr',
          quantity: mixerHours,
          sortOrder: 8,
        ),
        _resourceComponent(
          resources: resources,
          type: RateComponentType.plant,
          name: 'Hand tools',
          aliases: const ['hand tools', 'tools', 'small tools'],
          unit: 'hr',
          quantity: 8 / 2.4,
          sortOrder: 9,
        ),
      ],
      overheads: 15,
      profit: 10,
      outputUnit: 'm³',
    );
  }

  RatePreset _painting(
    List<RateResource> resources, {
    required String paintName,
    required List<String> aliases,
  }) {
    final components = <RateComponent>[
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: paintName,
        description: 'Paint coverage allowance: 0.33 litre per m².',
        unit: 'litre',
        quantity: 0.33,
        unitRate: _findRate(
          resources,
          RateComponentType.material,
          aliases,
          allowedUnits: const ['litre', 'liter', 'l'],
        ),
        wastePercent: 10,
        sortOrder: 0,
      ),
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.transport,
        name: 'Material transport allowance',
        description: 'Calculated automatically: 10% of paint cost.',
        unit: '%',
        quantity: 0.1,
        unitRate: 0,
        sortOrder: 1,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'Skilled painter',
        aliases: const ['skilled painter', 'painter', 'skilled labour'],
        unit: 'hr',
        quantity: 0.44,
        sortOrder: 2,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'General labourer',
        aliases: const ['general labourer', 'labourer', 'unskilled labour'],
        unit: 'hr',
        quantity: 0.44,
        sortOrder: 3,
      ),
    ];
    final materialCost = components.first.amount;
    components[1] = components[1].copyWith(unitRate: materialCost);
    final precedingCost = components.fold<double>(
      0,
      (sum, component) => sum + component.amount,
    );
    components.add(
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.other,
        name: 'Painting sundries allowance',
        description:
            'Calculated automatically: 20% for sandpaper, scrapers, brushes and other materials.',
        unit: '%',
        quantity: 0.2,
        unitRate: precedingCost,
        sortOrder: 4,
      ),
    );
    return RatePreset(
      components: components,
      overheads: 15,
      profit: 10,
      outputUnit: 'm²',
    );
  }

  RatePreset _hardcoreFilling(List<RateResource> resources) => RatePreset(
    components: [
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'Hardcore stone',
        description:
            '1.25 m³ of loose hardcore stone per compacted m³ of filling.',
        unit: 'm³',
        quantity: 1.25,
        unitRate: _findRate(
          resources,
          RateComponentType.material,
          const ['hardcore stone', 'hardcore', 'stones'],
          allowedUnits: const ['m³', 'm3'],
        ),
        wastePercent: 5,
        sortOrder: 0,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'General labourer',
        aliases: const ['general labourer', 'labourer', 'unskilled labour'],
        unit: 'hr',
        quantity: 2,
        description: 'Labour output 4 m³ per 8-hour day.',
        sortOrder: 1,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.plant,
        name: 'Hand tools',
        aliases: const ['hand tools', 'tools', 'small tools'],
        unit: 'day',
        quantity: 0.25,
        sortOrder: 2,
      ),
    ],
    overheads: 10,
    profit: 6,
    outputUnit: 'm³',
  );

  RatePreset _antiTermiteTreatment(List<RateResource> resources) {
    final components = <RateComponent>[
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'Soil insecticide',
        description:
            'Prepared soil-treatment solution applied under floors at 7 litres/m².',
        unit: 'litre',
        quantity: 7,
        unitRate: _findRate(
          resources,
          RateComponentType.material,
          const ['soil insecticide', 'aldrin', 'anti termite chemical'],
          allowedUnits: const ['litre', 'liter', 'l'],
        ),
        wastePercent: 2.5,
        sortOrder: 0,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'Skilled applicator',
        aliases: const ['skilled applicator', 'skilled labour'],
        unit: 'hr',
        quantity: 0.4,
        description: 'Output 20 m² per 8-hour person-day.',
        sortOrder: 1,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'General labourer',
        aliases: const ['general labourer', 'labourer', 'unskilled labour'],
        unit: 'hr',
        quantity: 0.4,
        description: 'Output 20 m² per 8-hour person-day.',
        sortOrder: 2,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.plant,
        name: 'Application tools',
        aliases: const ['application tools', 'hand tools', 'tools'],
        unit: 'day',
        quantity: 0.1,
        sortOrder: 3,
      ),
    ];
    final precedingCost = components.fold<double>(
      0,
      (sum, component) => sum + component.amount,
    );
    components.add(
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.other,
        name: 'Other materials allowance',
        description: 'Calculated automatically: 10% of preceding direct cost.',
        unit: '%',
        quantity: 0.1,
        unitRate: precedingCost,
        sortOrder: 4,
      ),
    );
    return RatePreset(
      components: components,
      overheads: 15,
      profit: 10,
      outputUnit: 'm²',
    );
  }

  RatePreset _earthwork({
    required List<RateResource> resources,
    required double labourHours,
    required double toolDays,
    required String note,
    String outputUnit = 'm³',
    double tipperTrips = 0,
  }) {
    final components = <RateComponent>[
      _resourceComponent(
        resources: resources,
        type: RateComponentType.labour,
        name: 'General labourer',
        aliases: const ['general labourer', 'labourer', 'unskilled labour'],
        unit: 'hr',
        quantity: labourHours,
        description: note,
        sortOrder: 0,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.plant,
        name: 'Hand tools',
        aliases: const ['hand tools', 'tools', 'small tools'],
        unit: 'day',
        quantity: toolDays,
        sortOrder: 1,
      ),
      if (tipperTrips > 0)
        _resourceComponent(
          resources: resources,
          type: RateComponentType.transport,
          name: 'Tipper haul',
          aliases: const ['tipper haul', 'tipper trip', 'hauling tipper'],
          unit: 'trip',
          quantity: tipperTrips,
          description: 'One trip carries 4 m³.',
          sortOrder: 2,
        ),
    ];
    return RatePreset(
      components: components,
      overheads: 15,
      profit: 10,
      outputUnit: outputUnit,
    );
  }

  RatePreset _importedBackfill(List<RateResource> resources) {
    final base = _earthwork(
      resources: resources,
      labourHours: 16 / 9,
      toolDays: 2 / 9,
      tipperTrips: 0.25,
      note:
          'Selected fill placed and compacted in 150 mm layers; loading output 4.5 m³/day.',
    );
    final components = [...base.components];
    components.insert(
      2,
      _resourceComponent(
        resources: resources,
        type: RateComponentType.material,
        name: 'Selected fill material',
        aliases: const ['selected fill', 'murram', 'imported fill'],
        unit: 'm³',
        quantity: 1,
        sortOrder: 2,
      ),
    );
    final initialBase = components.fold<double>(
      0,
      (sum, component) => sum + component.amount,
    );
    components.addAll([
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.other,
        name: 'Compaction allowance',
        description: 'Calculated automatically: 20% of preceding direct cost.',
        unit: '%',
        quantity: 0.2,
        unitRate: initialBase,
        sortOrder: 4,
      ),
      _resourceComponent(
        resources: resources,
        type: RateComponentType.plant,
        name: 'Roller and watering',
        aliases: const ['roller and watering', 'compaction roller', 'roller'],
        unit: 'day',
        quantity: 1 / 60,
        description: 'Compaction output 60 m³/day.',
        sortOrder: 5,
      ),
    ]);
    return RatePreset(
      components: components,
      overheads: 15,
      profit: 10,
      outputUnit: 'm³',
    );
  }

  RateComponent _resourceComponent({
    required List<RateResource> resources,
    required RateComponentType type,
    required String name,
    required List<String> aliases,
    required String unit,
    required double quantity,
    required int sortOrder,
    String description = '',
  }) => RateComponent(
    componentId: const Uuid().v4(),
    type: type,
    name: name,
    description: description,
    unit: unit,
    quantity: quantity,
    unitRate: _findRate(
      resources,
      type,
      aliases,
      allowedUnits: switch (unit) {
        'hr' => const ['hr', 'hour'],
        'day' => const ['day'],
        'm³' => const ['m³', 'm3'],
        'trip' => const ['trip'],
        _ => [unit],
      },
    ),
    sortOrder: sortOrder,
  );

  RatePreset _reinforcement(List<RateResource> resources) {
    // Source workbook basis: 1 tonne of fixed reinforcement. Quantities are
    // converted here to 1 kg, which is the workbook's final rate unit.
    final steelRatePerTonne = _findRate(
      resources,
      RateComponentType.material,
      [
        'reinforcement steel',
        'reinforcement bars',
        'rebar',
        'round bar',
        '16 mm round bar',
        '16mm round bar',
        '16 mm mild steel',
      ],
      allowedUnits: const ['tonne', 'ton', 't'],
    );
    final bindingWireRate = _findRate(resources, RateComponentType.material, [
      'binding wire',
      'tying wire',
    ]);
    final materialSubtotal =
        (steelRatePerTonne * 0.001 * 1.05) + (bindingWireRate * 0.01);
    final specs = <RateComponent>[
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'Reinforcement steel',
        description:
            'Factory price per tonne; automatically converted to 1 kg with 5% cutting waste and overlap.',
        unit: 'tonne',
        quantity: 0.001,
        unitRate: steelRatePerTonne,
        wastePercent: 5,
        sortOrder: 0,
      ),
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.material,
        name: 'Binding wire',
        description: '10 kg per tonne of reinforcement.',
        unit: 'kg',
        quantity: 0.01,
        unitRate: bindingWireRate,
        sortOrder: 1,
      ),
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.transport,
        name: 'Material transport allowance',
        description:
            'Calculated automatically: 20% of reinforcement and binding-wire cost.',
        unit: '%',
        quantity: 0.2,
        unitRate: materialSubtotal,
        sortOrder: 2,
      ),
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.labour,
        name: 'Steel fixer',
        description: '60 labour hours per tonne.',
        unit: 'hr',
        quantity: 0.06,
        unitRate: _findRate(resources, RateComponentType.labour, [
          'steel fixer',
          'steelfixer',
        ]),
        sortOrder: 3,
      ),
      RateComponent(
        componentId: const Uuid().v4(),
        type: RateComponentType.labour,
        name: 'General labourer',
        description: '120 labour hours per tonne.',
        unit: 'hr',
        quantity: 0.12,
        unitRate: _findRate(resources, RateComponentType.labour, [
          'general labourer',
          'labourer',
          'unskilled labour',
        ]),
        sortOrder: 4,
      ),
    ];
    return RatePreset(
      components: specs,
      overheads: 15,
      profit: 10,
      outputUnit: 'kg',
    );
  }

  RatePreset _blockwork({
    required String blockName,
    required double blocksPerSquareMetre,
    required double wetMortarPerSquareMetre,
    required List<RateResource> resources,
  }) {
    // Mortar assumption: cement:sand = 1:4 by volume, dry-volume factor 1.33,
    // and one 50 kg cement bag occupies approximately 0.0347 m³.
    final dryMortar = wetMortarPerSquareMetre * 1.33;
    final cementBags = (dryMortar / 5) / 0.0347;
    final sandVolume = dryMortar * 4 / 5;
    final specs = <
      ({
        RateComponentType type,
        String name,
        String unit,
        double quantity,
        double waste,
        List<String> aliases,
      })
    >[
      (
        type: RateComponentType.material,
        name: blockName,
        unit: 'pc',
        quantity: blocksPerSquareMetre,
        waste: 5,
        aliases:
            blockName.startsWith('150')
                ? [
                  '150 mm concrete block',
                  'concrete block 150 mm',
                  '150mm block',
                ]
                : [
                  '230 mm concrete block',
                  'concrete block 230 mm',
                  '230mm block',
                ],
      ),
      (
        type: RateComponentType.material,
        name: 'Cement (50 kg bag)',
        unit: 'bag',
        quantity: cementBags,
        waste: 5,
        aliases: ['cement', 'cement 50kg', 'cement 50 kg'],
      ),
      (
        type: RateComponentType.material,
        name: 'Mortar sand',
        unit: 'm³',
        quantity: sandVolume,
        waste: 5,
        aliases: ['sand', 'mortar sand'],
      ),
      (
        type: RateComponentType.labour,
        name: 'Mason',
        unit: 'day',
        quantity: 0.15,
        waste: 0,
        aliases: ['mason', 'skilled labour'],
      ),
      (
        type: RateComponentType.labour,
        name: 'General labourer',
        unit: 'day',
        quantity: 0.15,
        waste: 0,
        aliases: ['general labourer', 'labourer', 'unskilled labour'],
      ),
    ];
    return RatePreset(
      components: [
        for (var index = 0; index < specs.length; index++)
          RateComponent(
            componentId: const Uuid().v4(),
            type: specs[index].type,
            name: specs[index].name,
            description:
                specs[index].name.contains('Cement') ||
                        specs[index].name.contains('sand')
                    ? '1:4 cement-sand mortar; $wetMortarPerSquareMetre m³ wet mortar per m².'
                    : '',
            unit: specs[index].unit,
            quantity: specs[index].quantity,
            unitRate: _findRate(
              resources,
              specs[index].type,
              specs[index].aliases,
            ),
            wastePercent: specs[index].waste,
            sortOrder: index,
          ),
      ],
    );
  }

  double _findRate(
    List<RateResource> resources,
    RateComponentType type,
    List<String> aliases, {
    List<String>? allowedUnits,
  }) {
    String normalise(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    final normalisedAliases = aliases.map(normalise).toList();
    for (final resource in resources.where((item) => item.category == type)) {
      if (allowedUnits != null &&
          !allowedUnits.map(normalise).contains(normalise(resource.unit))) {
        continue;
      }
      final candidate = normalise(resource.name);
      if (normalisedAliases.any(
        (alias) => candidate == alias || candidate.contains(alias),
      )) {
        return resource.currentRate;
      }
    }
    return 0;
  }
}

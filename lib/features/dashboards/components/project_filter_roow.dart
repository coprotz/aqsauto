import 'package:aqs/core/theme/aqs_theme.dart';
import 'package:aqs/features/utils/enum.dart';
import 'package:aqs/features/utils/helpers/helpers.dart';
import 'package:flutter/material.dart';

class ProjectsFiltersRow extends StatelessWidget {
  final TextEditingController search;
  final ProjectStage? stageFilter;
  final VoidCallback onSearchChanged;
  final ValueChanged<ProjectStage?> onStageFilterChanged;

  const ProjectsFiltersRow({
    required this.search,
    required this.stageFilter,
    required this.onSearchChanged,
    required this.onStageFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final searchField = TextField(
          controller: search,
          decoration: InputDecoration(
            hintText: 'Search projects',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AqsColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AqsColors.border),
            ),
          ),
          onChanged: (_) => onSearchChanged(),
        );
        final stageField = DropdownButtonFormField<ProjectStage?>(
          value: stageFilter,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AqsColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AqsColors.border),
            ),
          ),
          items: [
            const DropdownMenuItem<ProjectStage?>(
              value: null,
              child: Text('All stages'),
            ),
            ...ProjectStage.values.map(
              (s) => DropdownMenuItem<ProjectStage?>(
                value: s,
                child: Text(s.label),
              ),
            ),
          ],
          onChanged: onStageFilterChanged,
        );

        if (compact) {
          return Column(
            children: [
              searchField,
              const SizedBox(height: 10),
              stageField,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 12),
            SizedBox(width: 210, child: stageField),
          ],
        );
      },
    );
  }
}

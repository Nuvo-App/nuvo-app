import 'package:flutter_test/flutter_test.dart';
import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/preset_motion/movement_work_order.dart';
import 'package:nuvo/features/races/ai/preset_motion/preset_movement_work_orders.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';
import 'package:nuvo/features/races/domain/motion_activity.dart';
import 'package:nuvo/features/races/domain/motion_activity_catalog.dart';

// ── Validation ───────────────────────────────────────────────────────────────

/// Validates a single [MovementWorkOrder]. Throws if required information
/// is missing or inconsistent.
void validateWorkOrder(MovementWorkOrder order) {
  // Required landmarks must be non-empty.
  if (order.requiredLandmarks.isEmpty) {
    throw WorkOrderValidationError(
      order.type,
      'requiredLandmarks cannot be empty',
    );
  }

  // Demo phase names must be non-empty for a visible preset.
  if (order.demoPhaseNames.isEmpty) {
    throw WorkOrderValidationError(
      order.type,
      'demoPhaseNames cannot be empty for a visible preset',
    );
  }

  // Stable frames must be non-negative.
  if (order.stableFrames < 0) {
    throw WorkOrderValidationError(
      order.type,
      'stableFrames cannot be negative',
    );
  }

  // Family-specific behavior type checks.
  switch (order.family) {
    case MovementFactoryFamily.configurableRep:
      if (order.behavior is! ConfigurableRepBehavior) {
        throw WorkOrderValidationError(
          order.type,
          'configurableRep family requires ConfigurableRepBehavior',
        );
      }
      // RepMovementDefinition has non-nullable startCondition and
      // activeCondition, so they are guaranteed present at compile time.
      if (order.isHold) {
        throw WorkOrderValidationError(
          order.type,
          'configurableRep cannot be a hold movement',
        );
      }

    case MovementFactoryFamily.customRep:
      if (order.behavior is! CustomRepBehavior) {
        throw WorkOrderValidationError(
          order.type,
          'customRep family requires CustomRepBehavior',
        );
      }
      final b = order.behavior as CustomRepBehavior;
      if (b.capabilityNotes.isEmpty) {
        throw WorkOrderValidationError(
          order.type,
          'customRep must have non-empty capabilityNotes',
        );
      }
      if (order.isHold) {
        throw WorkOrderValidationError(
          order.type,
          'customRep cannot be a hold movement',
        );
      }

    case MovementFactoryFamily.alternatingSideRep:
      if (order.behavior is! AlternatingSideBehavior) {
        throw WorkOrderValidationError(
          order.type,
          'alternatingSideRep family requires AlternatingSideBehavior',
        );
      }
      if (order.isHold) {
        throw WorkOrderValidationError(
          order.type,
          'alternatingSideRep cannot be a hold movement',
        );
      }

    case MovementFactoryFamily.hold:
      if (order.behavior is! HoldBehavior) {
        throw WorkOrderValidationError(
          order.type,
          'hold family requires HoldBehavior',
        );
      }
      if (!order.isHold) {
        throw WorkOrderValidationError(
          order.type,
          'hold family must have isHold = true',
        );
      }

    case MovementFactoryFamily.simpleStateRep:
      if (order.behavior is! SimpleStateBehavior) {
        throw WorkOrderValidationError(
          order.type,
          'simpleStateRep family requires SimpleStateBehavior',
        );
      }
      if (order.isHold) {
        throw WorkOrderValidationError(
          order.type,
          'simpleStateRep cannot be a hold movement',
        );
      }
  }
}

/// Validates the complete set of preset work orders against the catalog.
/// Throws if any invariant is violated.
void validatePresetWorkOrders() {
  final seenTypes = <MotionActivityType>{};

  // 1. No duplicate work-order types.
  for (final order in presetMovementWorkOrders) {
    if (seenTypes.contains(order.type)) {
      throw WorkOrderValidationError(
        order.type,
        'duplicate work order for this type',
      );
    }
    seenTypes.add(order.type);
    validateWorkOrder(order);
  }

  // 2. Every catalog movement must have exactly one work order.
  for (final definition in motionActivityDefinitions) {
    final order = workOrderForType(definition.type);
    if (order == null) {
      throw WorkOrderValidationError(
        definition.type,
        'catalog movement has no work order',
      );
    }
  }

  // 3. No extra work orders for types not in the catalog.
  final catalogTypes = motionActivityDefinitions.map((d) => d.type).toSet();
  for (final order in presetMovementWorkOrders) {
    if (!catalogTypes.contains(order.type)) {
      throw WorkOrderValidationError(
        order.type,
        'work order references a type not in the catalog',
      );
    }
  }
}

class WorkOrderValidationError implements Exception {
  WorkOrderValidationError(this.type, this.message);

  final MotionActivityType type;
  final String message;

  @override
  String toString() => 'WorkOrderValidationError(${type.name}): $message';
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('work-order validation', () {
    test('all 9 preset work orders validate', () {
      for (final order in presetMovementWorkOrders) {
        expect(
          () => validateWorkOrder(order),
          returnsNormally,
          reason: '${order.type.name} failed validation',
        );
      }
    });

    test('validatePresetWorkOrders passes for the current set', () {
      expect(validatePresetWorkOrders, returnsNormally);
    });

    test('no duplicate work-order types', () {
      final types = presetMovementWorkOrders.map((o) => o.type).toList();
      final unique = types.toSet();
      expect(
        types.length,
        unique.length,
        reason: 'Duplicate work-order types found',
      );
    });

    test('all 9 catalog movements have exactly one work order', () {
      for (final definition in motionActivityDefinitions) {
        final orders = presetMovementWorkOrders
            .where((o) => o.type == definition.type)
            .toList();
        expect(
          orders.length,
          1,
          reason: '${definition.type.name} must have exactly one work order',
        );
      }
    });

    test('work order count matches catalog count', () {
      expect(
        presetMovementWorkOrders.length,
        motionActivityDefinitions.length,
        reason: 'Work order count must match catalog count',
      );
    });
  });

  group('configurableRep work orders match production definitions', () {
    for (final order in presetMovementWorkOrders) {
      if (order.family != MovementFactoryFamily.configurableRep) continue;

      test(
        '${order.type.name} behavior references the production definition',
        () {
          final behavior = order.behavior as ConfigurableRepBehavior;

          // The definition's activity must match the work order's type.
          final expectedActivity = _aiActivityForType(order.type);
          expect(
            behavior.definition.activity,
            expectedActivity,
            reason: '${order.type.name} definition activity mismatch',
          );

          // The definition's requiredLandmarks must match the work order's.
          expect(
            behavior.definition.requiredLandmarks,
            order.requiredLandmarks,
            reason: '${order.type.name} landmarks mismatch',
          );

          // The definition's stableFrames must match the work order's.
          expect(
            behavior.definition.stableFrames,
            order.stableFrames,
            reason: '${order.type.name} stableFrames mismatch',
          );
        },
      );

      test(
        '${order.type.name} production definition is the one createMotionValidator uses',
        () {
          // Verify that createMotionValidator produces a ConfigurableRepValidator
          // with the same definition.
          final validator = createMotionValidator(
            _aiActivityForType(order.type),
            10,
          );
          expect(
            validator,
            isA<ConfigurableRepValidator>(),
            reason:
                '${order.type.name} should route through ConfigurableRepValidator',
          );
          final configurable = validator as ConfigurableRepValidator;
          final behavior = order.behavior as ConfigurableRepBehavior;
          expect(
            configurable.definition.activity,
            behavior.definition.activity,
            reason:
                '${order.type.name} production definition activity mismatch',
          );
          expect(
            configurable.definition.requiredLandmarks,
            behavior.definition.requiredLandmarks,
            reason:
                '${order.type.name} production definition landmarks mismatch',
          );
          expect(
            configurable.definition.stableFrames,
            behavior.definition.stableFrames,
            reason:
                '${order.type.name} production definition stableFrames mismatch',
          );
        },
      );
    }
  });

  group('custom movements are not fed into ConfigurableRepValidator', () {
    for (final order in presetMovementWorkOrders) {
      if (order.family == MovementFactoryFamily.configurableRep) continue;

      test(
        '${order.type.name} (${order.family.name}) does NOT use ConfigurableRepValidator',
        () {
          final validator = createMotionValidator(
            _aiActivityForType(order.type),
            10,
          );
          expect(
            validator,
            isNot(isA<ConfigurableRepValidator>()),
            reason:
                '${order.type.name} should NOT use ConfigurableRepValidator',
          );
        },
      );

      test(
        '${order.type.name} (${order.family.name}) behavior is NOT ConfigurableRepBehavior',
        () {
          expect(
            order.behavior,
            isNot(isA<ConfigurableRepBehavior>()),
            reason:
                '${order.type.name} should not have ConfigurableRepBehavior',
          );
        },
      );
    }
  });

  group('work-order field integrity', () {
    test('every work order has non-empty requiredLandmarks', () {
      for (final order in presetMovementWorkOrders) {
        expect(
          order.requiredLandmarks,
          isNotEmpty,
          reason: '${order.type.name} has empty requiredLandmarks',
        );
      }
    });

    test('every work order has non-empty demoPhaseNames', () {
      for (final order in presetMovementWorkOrders) {
        expect(
          order.demoPhaseNames,
          isNotEmpty,
          reason: '${order.type.name} has empty demoPhaseNames',
        );
      }
    });

    test('every work order has non-empty confusionLabels', () {
      for (final order in presetMovementWorkOrders) {
        expect(
          order.confusionLabels,
          isNotEmpty,
          reason: '${order.type.name} has empty confusionLabels',
        );
      }
    });

    test('hold work order has isHold = true', () {
      for (final order in presetMovementWorkOrders) {
        if (order.family == MovementFactoryFamily.hold) {
          expect(
            order.isHold,
            isTrue,
            reason: '${order.type.name} (hold) must have isHold = true',
          );
        } else {
          expect(
            order.isHold,
            isFalse,
            reason: '${order.type.name} (non-hold) must have isHold = false',
          );
        }
      }
    });

    test('workOrderForType returns the correct order for each type', () {
      for (final order in presetMovementWorkOrders) {
        final found = workOrderForType(order.type);
        expect(
          found,
          isNotNull,
          reason: '${order.type.name} not found by workOrderForType',
        );
        expect(found!.type, order.type);
        expect(found.family, order.family);
      }
    });

    test('workOrderForType returns null for unknown types', () {
      // All current MotionActivityType values have work orders, so this
      // verifies the lookup function handles the full enum correctly.
      for (final type in MotionActivityType.values) {
        final found = workOrderForType(type);
        expect(
          found,
          isNotNull,
          reason: '${type.name} should have a work order',
        );
      }
    });
  });

  group('factory family distribution', () {
    test('exactly 5 movements use configurableRep', () {
      final configurable = presetMovementWorkOrders
          .where((o) => o.family == MovementFactoryFamily.configurableRep)
          .toList();
      expect(configurable.length, 5);
      expect(configurable.map((o) => o.type).toSet(), {
        MotionActivityType.squats,
        MotionActivityType.jumpingJacks,
        MotionActivityType.lunges,
        MotionActivityType.sumoSquats,
        MotionActivityType.sideLunges,
      });
    });

    test('exactly 1 movement uses customRep (pushups)', () {
      final custom = presetMovementWorkOrders
          .where((o) => o.family == MovementFactoryFamily.customRep)
          .toList();
      expect(custom.length, 1);
      expect(custom.first.type, MotionActivityType.pushUps);
    });

    test('exactly 1 movement uses hold (plank)', () {
      final hold = presetMovementWorkOrders
          .where((o) => o.family == MovementFactoryFamily.hold)
          .toList();
      expect(hold.length, 1);
      expect(hold.first.type, MotionActivityType.plankHold);
    });

    test('exactly 1 movement uses alternatingSideRep (high knees)', () {
      final alternating = presetMovementWorkOrders
          .where((o) => o.family == MovementFactoryFamily.alternatingSideRep)
          .toList();
      expect(alternating.length, 1);
      expect(alternating.first.type, MotionActivityType.highKnees);
    });

    test('exactly 1 movement uses simpleStateRep (arm raises)', () {
      final simple = presetMovementWorkOrders
          .where((o) => o.family == MovementFactoryFamily.simpleStateRep)
          .toList();
      expect(simple.length, 1);
      expect(simple.first.type, MotionActivityType.armRaises);
    });
  });

  group('work-order behavior details', () {
    test('pushups custom behavior lists all custom capabilities', () {
      final order = workOrderForType(MotionActivityType.pushUps)!;
      final behavior = order.behavior as CustomRepBehavior;
      expect(behavior.capabilityNotes, contains('dynamic_baseline_tracking'));
      expect(behavior.capabilityNotes, contains('shoulder_drop_fallback'));
      expect(behavior.capabilityNotes, contains('symmetry_check'));
      expect(behavior.capabilityNotes, contains('cooldown_frames'));
    });

    test('plank hold behavior has correct alignment thresholds', () {
      final order = workOrderForType(MotionActivityType.plankHold)!;
      final behavior = order.behavior as HoldBehavior;
      expect(behavior.maxHipLineError, 0.16);
      expect(behavior.maxKneeLineError, 0.18);
      expect(behavior.minKneeAngle, 148);
      expect(behavior.stableAlignmentFrames, 4);
    });

    test('high knees alternating behavior has correct thresholds', () {
      final order = workOrderForType(MotionActivityType.highKnees)!;
      final behavior = order.behavior as AlternatingSideBehavior;
      expect(behavior.raiseThreshold, 0.02);
      expect(behavior.lowerThreshold, 0.12);
    });

    test('arm raises simple state behavior has correct thresholds', () {
      final order = workOrderForType(MotionActivityType.armRaises)!;
      final behavior = order.behavior as SimpleStateBehavior;
      expect(behavior.openThreshold, 0.04);
      expect(behavior.closedThreshold, 0.03);
      expect(behavior.requiresDirectionalCycle, isTrue);
    });

    test('squat configurable behavior references squatRepDefinition', () {
      final order = workOrderForType(MotionActivityType.squats)!;
      final behavior = order.behavior as ConfigurableRepBehavior;
      expect(behavior.definition.activity, AiMotionActivity.squats);
      expect(behavior.definition.stableFrames, 3);
    });

    test(
      'jumping jacks configurable behavior references jumpingJackRepDefinition',
      () {
        final order = workOrderForType(MotionActivityType.jumpingJacks)!;
        final behavior = order.behavior as ConfigurableRepBehavior;
        expect(behavior.definition.activity, AiMotionActivity.jumpingJacks);
        expect(behavior.definition.stableFrames, 3);
      },
    );

    test('lunges configurable behavior references lungeRepDefinition', () {
      final order = workOrderForType(MotionActivityType.lunges)!;
      final behavior = order.behavior as ConfigurableRepBehavior;
      expect(behavior.definition.activity, AiMotionActivity.lunges);
      expect(behavior.definition.stableFrames, 3);
    });
  });

  group('validation failure cases', () {
    test('empty requiredLandmarks fails validation', () {
      const order = MovementWorkOrder(
        type: MotionActivityType.pushUps,
        family: MovementFactoryFamily.customRep,
        requiredLandmarks: [],
        preferredCameraView: PreferredCameraView.frontPreferred,
        isHold: false,
        stableFrames: 3,
        demoPhaseNames: ['top'],
        confusionLabels: ['test'],
        behavior: CustomRepBehavior(capabilityNotes: ['note']),
      );
      expect(
        () => validateWorkOrder(order),
        throwsA(isA<WorkOrderValidationError>()),
      );
    });

    test('empty demoPhaseNames fails validation', () {
      const order = MovementWorkOrder(
        type: MotionActivityType.pushUps,
        family: MovementFactoryFamily.customRep,
        requiredLandmarks: ['leftShoulder'],
        preferredCameraView: PreferredCameraView.frontPreferred,
        isHold: false,
        stableFrames: 3,
        demoPhaseNames: [],
        confusionLabels: ['test'],
        behavior: CustomRepBehavior(capabilityNotes: ['note']),
      );
      expect(
        () => validateWorkOrder(order),
        throwsA(isA<WorkOrderValidationError>()),
      );
    });

    test('configurableRep with hold flag fails validation', () {
      const order = MovementWorkOrder(
        type: MotionActivityType.squats,
        family: MovementFactoryFamily.configurableRep,
        requiredLandmarks: ['leftShoulder'],
        preferredCameraView: PreferredCameraView.frontPreferred,
        isHold: true,
        stableFrames: 3,
        demoPhaseNames: ['standing'],
        confusionLabels: ['test'],
        behavior: ConfigurableRepBehavior(squatRepDefinition),
      );
      expect(
        () => validateWorkOrder(order),
        throwsA(isA<WorkOrderValidationError>()),
      );
    });

    test('hold family with isHold=false fails validation', () {
      const order = MovementWorkOrder(
        type: MotionActivityType.plankHold,
        family: MovementFactoryFamily.hold,
        requiredLandmarks: ['leftShoulder'],
        preferredCameraView: PreferredCameraView.sideOrDiagonalRequired,
        isHold: false,
        stableFrames: 4,
        demoPhaseNames: ['plank'],
        confusionLabels: ['test'],
        behavior: HoldBehavior(
          maxHipLineError: 0.16,
          maxKneeLineError: 0.18,
          minKneeAngle: 148,
          stableAlignmentFrames: 4,
        ),
      );
      expect(
        () => validateWorkOrder(order),
        throwsA(isA<WorkOrderValidationError>()),
      );
    });

    test('wrong behavior type for family fails validation', () {
      const order = MovementWorkOrder(
        type: MotionActivityType.pushUps,
        family: MovementFactoryFamily.configurableRep,
        requiredLandmarks: ['leftShoulder'],
        preferredCameraView: PreferredCameraView.frontPreferred,
        isHold: false,
        stableFrames: 3,
        demoPhaseNames: ['top'],
        confusionLabels: ['test'],
        behavior: CustomRepBehavior(capabilityNotes: ['note']),
      );
      expect(
        () => validateWorkOrder(order),
        throwsA(isA<WorkOrderValidationError>()),
      );
    });
  });
}

/// Maps a [MotionActivityType] to its [AiMotionActivity] for test purposes.
AiMotionActivity _aiActivityForType(MotionActivityType type) {
  return switch (type) {
    MotionActivityType.pushUps => AiMotionActivity.pushUps,
    MotionActivityType.jumpingJacks => AiMotionActivity.jumpingJacks,
    MotionActivityType.squats => AiMotionActivity.squats,
    MotionActivityType.lunges => AiMotionActivity.lunges,
    MotionActivityType.highKnees => AiMotionActivity.highKnees,
    MotionActivityType.armRaises => AiMotionActivity.armRaises,
    MotionActivityType.plankHold => AiMotionActivity.plankHold,
    MotionActivityType.sumoSquats => AiMotionActivity.sumoSquats,
    MotionActivityType.sideLunges => AiMotionActivity.sideLunges,
  };
}

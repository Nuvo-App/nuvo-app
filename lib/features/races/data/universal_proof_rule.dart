import 'dart:convert';

import '../ai/local_motion_signature.dart';

const universalProofRuleStart = '[NUVO_UNIVERSAL_PROOF_RULE]';
const universalProofRuleEnd = '[/NUVO_UNIVERSAL_PROOF_RULE]';

class UniversalProofRule {
  const UniversalProofRule({
    required this.version,
    required this.unit,
    required this.countRule,
    required this.rejectRule,
    required this.framingTip,
    required this.promptText,
    required this.confidenceThreshold,
    this.motionSignature,
  });

  final String version;
  final String unit;
  final String countRule;
  final String rejectRule;
  final String framingTip;
  final String promptText;
  final double confidenceThreshold;
  final LocalMotionSignature? motionSignature;

  factory UniversalProofRule.fromJson(Map<String, dynamic> json) {
    return UniversalProofRule(
      version: json['version'] as String? ?? 'nuvo-universal-rule-v1',
      unit: json['unit'] as String? ?? 'actions',
      countRule: json['countRule'] as String? ?? 'Count one clean action.',
      rejectRule:
          json['rejectRule'] as String? ??
          'Reject partial, repeated, or unrelated actions.',
      framingTip: json['framingTip'] as String? ?? 'Keep the action visible.',
      promptText:
          json['promptText'] as String? ??
          'Return actionComplete only for one clean completed count.',
      confidenceThreshold:
          (json['confidenceThreshold'] as num?)?.toDouble().clamp(0, 1) ?? 0.72,
      motionSignature: json['motionSignature'] is Map<String, dynamic>
          ? LocalMotionSignature.fromJson(
              json['motionSignature'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'unit': unit,
    'countRule': countRule,
    'rejectRule': rejectRule,
    'framingTip': framingTip,
    'promptText': promptText,
    'confidenceThreshold': confidenceThreshold,
    if (motionSignature != null) 'motionSignature': motionSignature!.toJson(),
  };

  UniversalProofRule copyWith({
    String? version,
    String? unit,
    String? countRule,
    String? rejectRule,
    String? framingTip,
    String? promptText,
    double? confidenceThreshold,
    LocalMotionSignature? motionSignature,
  }) {
    return UniversalProofRule(
      version: version ?? this.version,
      unit: unit ?? this.unit,
      countRule: countRule ?? this.countRule,
      rejectRule: rejectRule ?? this.rejectRule,
      framingTip: framingTip ?? this.framingTip,
      promptText: promptText ?? this.promptText,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      motionSignature: motionSignature ?? this.motionSignature,
    );
  }

  String encodeForDescription({String? visibleDescription}) {
    final visible = visibleDescription?.trim();
    final encoded = jsonEncode(toJson());
    final ruleBlock = '$universalProofRuleStart$encoded$universalProofRuleEnd';
    if (visible == null || visible.isEmpty) return ruleBlock;
    return '$visible\n\n$ruleBlock';
  }

  static UniversalProofRule? fromDescription(String? description) {
    if (description == null) return null;
    final start = description.indexOf(universalProofRuleStart);
    final end = description.indexOf(universalProofRuleEnd);
    if (start < 0 || end <= start) return null;
    final jsonText = description.substring(
      start + universalProofRuleStart.length,
      end,
    );
    try {
      final json = jsonDecode(jsonText) as Map<String, dynamic>;
      return UniversalProofRule.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

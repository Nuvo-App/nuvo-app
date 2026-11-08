import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart';

import '../../../../core/v13/v13.dart';
import 'nuvo_motion_viewport.dart';
import 'nuvo_rive_calibration.dart';

/// Debug-only manual calibration surface for the exported Nuvo Rive rig.
///
/// This screen deliberately does not start an animation or use the semantic
/// resolver. Each control writes only its own View Model number property.
class RiveCalibrationScreen extends StatefulWidget {
  const RiveCalibrationScreen({super.key});

  @override
  State<RiveCalibrationScreen> createState() => _RiveCalibrationScreenState();
}

class _RiveCalibrationScreenState extends State<RiveCalibrationScreen> {
  static const _asset = 'assets/animations/preverify/nuvo_stickman.riv';
  static const _artboard = 'nuvo stickman elite';
  static const _viewport = NuvoMotionViewportConfig();
  static const _leftArm = ['leftShoulderAngle', 'leftElbowAngle'];
  static const _rightArm = ['rightShoulderAngle', 'rightElbowAngle'];
  static const _leftLeg = ['leftHipAngle', 'leftKneeAngle'];
  static const _rightLeg = ['rightHipAngle', 'rightKneeAngle'];
  static const _body = ['torsoAngle'];

  late final FileLoader _fileLoader;
  late final DataBind _dataBind;
  ViewModelInstance? _instance;
  Map<String, double> _values = const {};
  Object? _loadError;
  int _rigGeneration = 0;

  Factory get _riveFactory => Platform.environment.containsKey('FLUTTER_TEST')
      ? Factory.flutter
      : Factory.rive;

  @override
  void initState() {
    super.initState();
    _fileLoader = FileLoader.fromAsset(_asset, riveFactory: _riveFactory);
    _dataBind = DataBind.auto();
  }

  @override
  void dispose() {
    _fileLoader.dispose();
    super.dispose();
  }

  void _onLoaded(RiveLoaded state) {
    final instance = state.viewModelInstance;
    if (instance == null) {
      setState(() => _loadError = 'NuvoPoseModel was not bound.');
      return;
    }
    try {
      final pose = NuvoRiveCalibrationPose.read(instance);
      setState(() {
        _instance = instance;
        _values = pose.values;
        _loadError = null;
      });
    } catch (error) {
      setState(() => _loadError = error);
    }
  }

  void _setProperty(String name, double value) {
    final property = _instance?.number(name);
    if (property == null) return;
    property.value = value;
    _instance!.requestAdvance();
    setState(() => _values = {..._values, name: value});
  }

  void _nudge(String name, double amount) {
    _setProperty(name, (_values[name] ?? 0) + amount);
  }

  Future<void> _copyPose({required bool closed}) async {
    if (_instance == null) return;
    final pose = closed
        ? NuvoJumpingJackCalibrationStore.closed
        : NuvoJumpingJackCalibrationStore.open;
    if (pose == null) {
      _showMessage(
        closed
            ? 'No closed pose has been saved.'
            : 'No open pose has been saved.',
      );
      return;
    }
    await Clipboard.setData(
      ClipboardData(
        text: pose.toJsonLikeString(
          label: closed
              ? 'jumpingJackClosedCalibration'
              : 'jumpingJackOpenCalibration',
        ),
      ),
    );
    if (mounted) {
      _showMessage(closed ? 'Closed pose copied.' : 'Open pose copied.');
    }
  }

  void _savePose({required bool closed}) {
    if (_instance == null) return;
    final pose = NuvoRiveCalibrationPose.read(_instance!);
    if (closed) {
      NuvoJumpingJackCalibrationStore.closed = pose;
    } else {
      NuvoJumpingJackCalibrationStore.open = pose;
    }
    _showMessage(closed ? 'Closed pose saved.' : 'Open pose saved.');
  }

  void _showPose({required bool closed}) {
    final pose = closed
        ? NuvoJumpingJackCalibrationStore.closed
        : NuvoJumpingJackCalibrationStore.open;
    if (pose == null || _instance == null) {
      _showMessage(
        closed
            ? 'No closed pose has been saved.'
            : 'No open pose has been saved.',
      );
      return;
    }
    pose.applyTo(_instance!);
    setState(() => _values = pose.values);
  }

  void _resetRig() {
    setState(() {
      _instance = null;
      _values = const {};
      _loadError = null;
      _rigGeneration++;
    });
    _showMessage('Rig reloaded from authored defaults.');
  }

  void _showMessage(String message) {
    showV13Toast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V13.bg,
      body: SafeArea(
        child: Column(
          children: [
            V13BackBar(
              title: 'Rive rig calibration',
              trailing: [
                V13IconButton(
                  icon: Icons.restart_alt,
                  shape: V13IconButtonShape.square,
                  semanticLabel: 'Reset rig',
                  onTap: _resetRig,
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  V13.pagePad,
                  V13.gapMd,
                  V13.pagePad,
                  40,
                ),
                children: [
                  _buildRigPreview(),
                  const SizedBox(height: V13.gapLg),
                  _buildActionPanel(),
                  const SizedBox(height: V13.gapXl),
                  _buildJointSection('LEFT ARM', _leftArm),
                  _buildJointSection('RIGHT ARM', _rightArm),
                  _buildJointSection('LEFT LEG', _leftLeg),
                  _buildJointSection('RIGHT LEG', _rightLeg),
                  _buildJointSection('BODY', _body),
                  const SizedBox(height: V13.gapXl),
                  _buildJointSection(
                    'ADVANCED / SEGMENT LENGTH',
                    NuvoRiveCalibrationContract.scaleProperties,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRigPreview() {
    return SizedBox(
      height: 360,
      child: ClipRect(
        child: Center(
          child: SizedBox(
            width: double.infinity,
            height: 360 * _viewport.artboardExtentFactor,
            child: RiveWidgetBuilder(
              key: ValueKey(_rigGeneration),
              fileLoader: _fileLoader,
              artboardSelector: const ArtboardNamed(_artboard),
              stateMachineSelector: const StateMachineNamed('Nuvo pose'),
              dataBind: _dataBind,
              onLoaded: _onLoaded,
              onFailed: (error, _) => setState(() => _loadError = error),
              builder: (context, state) {
                if (state is RiveLoaded) {
                  return RiveWidget(
                    controller: state.controller,
                    fit: Fit.contain,
                    alignment: Alignment.center,
                    hitTestBehavior: RiveHitTestBehavior.opaque,
                  );
                }
                if (state is RiveFailed) {
                  return const Center(child: Text('Rive rig failed to load.'));
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionPanel() {
    final closedSaved = NuvoJumpingJackCalibrationStore.closed != null;
    final openSaved = NuvoJumpingJackCalibrationStore.open != null;
    return V13Card(
      padding: const EdgeInsets.all(V13.gapMd),
      child: Wrap(
        spacing: V13.gapSm,
        runSpacing: V13.gapSm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          V13Button.secondary(
            label: 'RESET',
            size: V13ButtonSize.small,
            onPressed: _resetRig,
          ),
          V13Button.secondary(
            label: 'SAVE CLOSED',
            size: V13ButtonSize.small,
            onPressed: _instance == null ? null : () => _savePose(closed: true),
          ),
          V13Button.secondary(
            label: 'SAVE OPEN',
            size: V13ButtonSize.small,
            onPressed: _instance == null
                ? null
                : () => _savePose(closed: false),
          ),
          V13Button.ghost(
            label: 'SHOW CLOSED',
            size: V13ButtonSize.small,
            onPressed: closedSaved ? () => _showPose(closed: true) : null,
          ),
          V13Button.ghost(
            label: 'SHOW OPEN',
            size: V13ButtonSize.small,
            onPressed: openSaved ? () => _showPose(closed: false) : null,
          ),
          V13Button.secondary(
            label: 'COPY CLOSED',
            size: V13ButtonSize.small,
            onPressed: closedSaved ? () => _copyPose(closed: true) : null,
          ),
          V13Button.secondary(
            label: 'COPY OPEN',
            size: V13ButtonSize.small,
            onPressed: openSaved ? () => _copyPose(closed: false) : null,
          ),
          Text(
            'CLOSED: ${closedSaved ? 'SAVED' : 'NOT SAVED'}',
            style: V13.label,
          ),
          Text('OPEN: ${openSaved ? 'SAVED' : 'NOT SAVED'}', style: V13.label),
          if (_loadError != null)
            Text(
              'Calibration error: $_loadError',
              style: V13.caption.copyWith(color: V13.danger),
            ),
        ],
      ),
    );
  }

  Widget _buildJointSection(String title, List<String> properties) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: V13.gapSm),
          child: Text(
            title,
            style: V13.label.copyWith(fontSize: 12, color: V13.navy),
          ),
        ),
        for (final property in properties) _buildPropertyEditor(property),
        const SizedBox(height: V13.gapMd),
      ],
    );
  }

  Widget _buildPropertyEditor(String property) {
    final value = _values[property] ?? 0;
    final min = NuvoRiveCalibrationContract.minimum(property);
    final max = NuvoRiveCalibrationContract.maximum(property);
    return Padding(
      padding: const EdgeInsets.only(bottom: V13.gapSm),
      child: V13Card(
        padding: const EdgeInsets.fromLTRB(V13.gapMd, 10, V13.gapMd, V13.gapSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  property,
                  style: V13.caption.copyWith(
                    color: V13.navy,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  value.toStringAsFixed(2),
                  style: V13.numberSm.copyWith(fontSize: 14),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: V13.blue,
                thumbColor: V13.blue,
                inactiveTrackColor: V13.divider,
                overlayColor: V13.blue.withValues(alpha: 0.12),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: _instance == null
                    ? null
                    : (next) => _setProperty(property, next),
              ),
            ),
            Wrap(
              spacing: V13.gapXs,
              children: [
                for (final amount in const [-5.0, -1.0, 1.0, 5.0])
                  V13Button.ghost(
                    label: amount > 0
                        ? '+${amount.toInt()}'
                        : '${amount.toInt()}',
                    size: V13ButtonSize.small,
                    onPressed: _instance == null
                        ? null
                        : () => _nudge(property, amount),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart';

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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rive rig calibration'),
        actions: [
          IconButton(
            tooltip: 'Reset rig',
            onPressed: _resetRig,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          _buildRigPreview(),
          const SizedBox(height: 16),
          _buildActionPanel(),
          const SizedBox(height: 20),
          _buildJointSection('LEFT ARM', _leftArm),
          _buildJointSection('RIGHT ARM', _rightArm),
          _buildJointSection('LEFT LEG', _leftLeg),
          _buildJointSection('RIGHT LEG', _rightLeg),
          _buildJointSection('BODY', _body),
          const SizedBox(height: 20),
          _buildJointSection(
            'ADVANCED / SEGMENT LENGTH',
            NuvoRiveCalibrationContract.scaleProperties,
          ),
        ],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: _resetRig,
              child: const Text('RESET'),
            ),
            OutlinedButton(
              onPressed: _instance == null
                  ? null
                  : () => _savePose(closed: true),
              child: const Text('SAVE CLOSED'),
            ),
            OutlinedButton(
              onPressed: _instance == null
                  ? null
                  : () => _savePose(closed: false),
              child: const Text('SAVE OPEN'),
            ),
            TextButton(
              onPressed: closedSaved ? () => _showPose(closed: true) : null,
              child: const Text('SHOW CLOSED'),
            ),
            TextButton(
              onPressed: openSaved ? () => _showPose(closed: false) : null,
              child: const Text('SHOW OPEN'),
            ),
            OutlinedButton(
              onPressed: closedSaved ? () => _copyPose(closed: true) : null,
              child: const Text('COPY CLOSED'),
            ),
            OutlinedButton(
              onPressed: openSaved ? () => _copyPose(closed: false) : null,
              child: const Text('COPY OPEN'),
            ),
            Text(
              'CLOSED: ${closedSaved ? 'SAVED' : 'NOT SAVED'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              'OPEN: ${openSaved ? 'SAVED' : 'NOT SAVED'}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (_loadError != null)
              Text(
                'Calibration error: $_loadError',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildJointSection(String title, List<String> properties) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        for (final property in properties) _buildPropertyEditor(property),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildPropertyEditor(String property) {
    final value = _values[property] ?? 0;
    final min = NuvoRiveCalibrationContract.minimum(property);
    final max = NuvoRiveCalibrationContract.maximum(property);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(property, style: const TextStyle(fontFamily: 'monospace')),
                Text(value.toStringAsFixed(2)),
              ],
            ),
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: _instance == null
                  ? null
                  : (next) => _setProperty(property, next),
            ),
            Wrap(
              spacing: 4,
              children: [
                for (final amount in const [-5.0, -1.0, 1.0, 5.0])
                  OutlinedButton(
                    onPressed: _instance == null
                        ? null
                        : () => _nudge(property, amount),
                    child: Text(
                      amount > 0 ? '+${amount.toInt()}' : '${amount.toInt()}',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

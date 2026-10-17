// Motion replay + visualizer.
//
//   dart run tool/motion_replay.dart <session.json|.json.gz> \
//       [--spec server/worker/motion_specs/<id>.json] \
//       [--set key=value ...] [--out replay.html]
//
// Replays a recorded session (the pose log the app uploads) through the SAME
// code the phone runs — the compiled validator with the spec's `params`, or
// the rep_tree_v1 evaluator — and writes a self-contained HTML page: a skeleton
// viewer with a scrubber, the live signals the verifier reads, and where reps
// were counted. `--set` overrides a spec param so you can try a threshold
// before publishing it. No app build, no device, no Cloudflare needed.
import 'dart:convert';
import 'dart:io';

import 'package:nuvo/features/races/ai/motion_validators.dart';
import 'package:nuvo/features/races/ai/remote_verifier_runtime.dart';
import 'package:nuvo/features/races/ai/remote_verifier_spec.dart';
import 'package:nuvo/features/races/ai/rep_tree.dart';
import 'package:nuvo/features/races/data/ai_motion_models.dart';

void main(List<String> args) {
  String? sessionPath, specPath, out;
  final overrides = <String, double>{};
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--spec':
        specPath = args[++i];
      case '--out':
        out = args[++i];
      case '--set':
        final kv = args[++i].split('=');
        overrides[kv[0]] = double.parse(kv[1]);
      default:
        sessionPath = args[i];
    }
  }
  if (sessionPath == null) {
    stderr.writeln('usage: dart run tool/motion_replay.dart <session> [--spec f] [--set k=v] [--out f.html]');
    exit(2);
  }

  List<int> raw = File(sessionPath).readAsBytesSync();
  if (raw.length > 2 && raw[0] == 0x1f && raw[1] == 0x8b) raw = gzip.decode(raw);
  final session = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
  final context = (session['context'] as Map?) ?? const {};
  final activityId = (context['activityId'] ?? session['activityId']) as String;
  final recordedCount =
      ((session['result'] as Map?)?['detectedValue'] as num?)?.toInt();
  final events = (session['events'] as List?) ?? const [];

  final frames = <NuvoPoseFrame>[];
  for (final f in (session['frames'] as List)) {
    final m = f as Map<String, dynamic>;
    final pts = <String, NuvoPosePoint>{};
    (m['landmarks'] as Map<String, dynamic>).forEach((k, v) {
      final p = v as Map<String, dynamic>;
      pts[k] = NuvoPosePoint(
        x: (p['x'] as num).toDouble(),
        y: (p['y'] as num).toDouble(),
        z: (p['z'] as num?)?.toDouble() ?? 0,
        likelihood: (p['confidence'] as num?)?.toDouble() ?? 1,
      );
    });
    frames.add(NuvoPoseFrame(
      points: pts,
      imageWidth: 640,
      imageHeight: 480,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (m['timestampMs'] as num).toInt(),
        isUtc: true,
      ),
    ));
  }
  if (frames.isEmpty) {
    stderr.writeln('session has no frames');
    exit(1);
  }
  final t0 = frames.first.createdAt.millisecondsSinceEpoch;

  final specFile = File(specPath ?? 'server/worker/motion_specs/$activityId.json');
  final specJson = specFile.existsSync()
      ? jsonDecode(specFile.readAsStringSync()) as Map<String, dynamic>
      : null;
  if (specJson != null &&
      overrides.isNotEmpty &&
      specJson['engineType'] != 'native_tuned_v1') {
    stderr.writeln(
      '--set only applies to native_tuned_v1 specs. For rep_tree_v1 / '
      'sequence specs, edit a copy of the spec file and pass it with --spec.',
    );
    exit(2);
  }
  if (specJson != null && overrides.isNotEmpty) {
    final params = ((specJson['params'] as Map?) ?? {}).cast<String, dynamic>();
    params.addAll(overrides);
    specJson['params'] = params;
  }
  final spec = specJson == null ? null : RemoteVerifierSpec.fromJson(specJson);

  final counts = <int>[];
  final series = <String, List<double>>{};
  void put(String name, int i, double v) {
    final s = series.putIfAbsent(name, () => List.filled(frames.length, double.nan));
    s[i] = v.isFinite ? v : double.nan;
  }

  const big = 100000;
  String engine;
  if (spec != null && spec.engine == RemoteEngineType.repTreeV1) {
    engine = 'rep_tree_v1 (${spec.releaseId})';
    final rt = createRemoteVerifierRuntime(spec: spec, target: big);
    final used = spec.repTree!.landmarks;
    final names = kRepTreeSignals.entries
        .where((e) => e.value.landmarks.every(used.contains))
        .map((e) => e.key);
    for (var i = 0; i < frames.length; i++) {
      counts.add(rt.update(frames[i]).count);
      if (frames[i].hasPoints(used.toList())) {
        final f = PoseFeatureExtractor(frames[i]);
        for (final n in names) {
          put(n, i, kRepTreeSignals[n]!.read(f));
        }
      }
    }
  } else {
    final activity = AiMotionActivity.fromBackendValue(activityId);
    final tuning = spec?.tuning ?? MotionTuning.empty;
    engine = spec == null
        ? 'compiled validator (no spec found)'
        : '${spec.engine.name} (${spec.releaseId})';
    final v = createMotionValidator(activity, big, tuning: tuning)..start();
    for (var i = 0; i < frames.length; i++) {
      final u = v.update(frames[i]);
      counts.add(u.currentValue);
      v.debugValues.forEach((k, val) {
        if (k.startsWith('count') || k.endsWith('Frames')) return;
        put(k, i, val);
      });
    }
  }

  final data = {
    'sessionId': session['sessionId'] ?? sessionPath.split('/').last,
    'activity': activityId,
    'engine': engine,
    'recordedCount': recordedCount,
    'replayCount': counts.last,
    'overrides': overrides,
    't': [for (final f in frames) f.createdAt.millisecondsSinceEpoch - t0],
    'counts': counts,
    'series': {
      for (final e in series.entries)
        if (e.value.any((x) => !x.isNaN))
          e.key: [for (final x in e.value) x.isNaN ? null : double.parse(x.toStringAsFixed(4))],
    },
    'events': events,
    'frames': [
      for (final f in frames)
        {
          for (final e in f.points.entries)
            e.key: [
              double.parse(e.value.x.toStringAsFixed(4)),
              double.parse(e.value.y.toStringAsFixed(4)),
            ],
        },
    ],
  };
  final outPath = out ?? 'replay_$activityId.html';
  File(outPath).writeAsStringSync(_html.replaceFirst('__DATA__', jsonEncode(data)));
  stdout.writeln(
    '$activityId: replay counted ${counts.last}'
    '${recordedCount == null ? '' : ' (app counted $recordedCount)'} '
    'over ${frames.length} frames via $engine\n-> $outPath',
  );
}

const _html = r'''<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>Motion replay</title>
<style>
:root{--bg:#fff;--fg:#14181f;--mut:#66707d;--line:#d9dee5;--acc:#2f6fed}
@media(prefers-color-scheme:dark){:root{--bg:#10141a;--fg:#e8ecf2;--mut:#98a2b0;--line:#2a313b;--acc:#6ea0ff}}
body{margin:0;background:var(--bg);color:var(--fg);font:14px system-ui,sans-serif;padding:16px}
h1{font-size:18px;margin:0 0 4px}.m{color:var(--mut)}
.row{display:flex;gap:16px;flex-wrap:wrap;margin-top:12px}
canvas{border:1px solid var(--line);border-radius:8px;background:var(--bg)}
input[type=range]{width:100%;margin-top:8px}
label{display:inline-flex;gap:4px;margin:2px 10px 2px 0;white-space:nowrap}
.big{font-size:28px;font-weight:600}
</style>
<h1 id=title></h1><div class=m id=sub></div>
<div class=row>
 <div><canvas id=sk width=300 height=400></canvas>
  <div>frame <b id=fi>0</b> · <span id=ft></span> · count <span class=big id=fc></span></div></div>
 <div style="flex:1;min-width:300px"><canvas id=ch width=720 height=300 style="width:100%"></canvas>
  <div id=legend></div></div>
</div>
<div class=row id=lab style="border:1px solid var(--line);border-radius:8px;padding:12px">
 <div><b>Is this recording a correct example?</b><br>
  <label><input type=radio name=v value=correct> Correct motion</label>
  <label><input type=radio name=v value=incorrect> Wrong / sloppy motion</label>
  <label><input type=radio name=v value=unusable> Unusable (bad tracking / not the motion)</label></div>
 <div>Reps you actually did <input id=tr type=number min=0 style="width:70px"> <span class=m id=mm></span></div>
 <div style="flex:1;min-width:220px"><input id=nt placeholder="notes (optional)" style="width:100%"></div>
 <div><button id=sv>Save label (downloads JSON)</button> <span class=m id=ss></span></div>
</div>
<input id=sc type=range min=0 value=0>
<script>
const D=__DATA__;
const $=id=>document.getElementById(id);
$('title').textContent=D.activity+' — replay counted '+D.replayCount+(D.recordedCount!=null?' (app counted '+D.recordedCount+')':'');
$('sub').textContent=D.engine+(Object.keys(D.overrides).length?' · overrides '+JSON.stringify(D.overrides):'');
const N=D.t.length;$('sc').max=N-1;
const names=Object.keys(D.series);const on={};const col={};
names.forEach((n,i)=>{on[n]=i<4;col[n]=`hsl(${(i*57)%360} 70% 50%)`;});
$('legend').innerHTML=names.map(n=>`<label><input type=checkbox data-n="${n}" ${on[n]?'checked':''}><span style="color:${col[n]}">■</span>${n}</label>`).join('');
$('legend').onchange=e=>{on[e.target.dataset.n]=e.target.checked;draw()};
const BONES=[['leftShoulder','rightShoulder'],['leftShoulder','leftElbow'],['leftElbow','leftWrist'],['rightShoulder','rightElbow'],['rightElbow','rightWrist'],['leftShoulder','leftHip'],['rightShoulder','rightHip'],['leftHip','rightHip'],['leftHip','leftKnee'],['leftKnee','leftAnkle'],['rightHip','rightKnee'],['rightKnee','rightAnkle']];
function skel(i){const c=$('sk'),x=c.getContext('2d');x.clearRect(0,0,c.width,c.height);const f=D.frames[i];
 x.strokeStyle=getComputedStyle(document.body).color;x.lineWidth=3;x.lineCap='round';
 const P=n=>f[n]?[f[n][0]*c.width,f[n][1]*c.height]:null;
 BONES.forEach(([a,b])=>{const A=P(a),B=P(b);if(A&&B){x.beginPath();x.moveTo(...A);x.lineTo(...B);x.stroke();}});
 Object.keys(f).forEach(n=>{const p=P(n);x.fillStyle=n.startsWith('left')?'#e5484d':n.startsWith('right')?'#2f6fed':'#888';x.beginPath();x.arc(p[0],p[1],4,0,7);x.fill();});}
function draw(){const i=+$('sc').value;skel(i);
 $('fi').textContent=i;$('ft').textContent=(D.t[i]/1000).toFixed(2)+'s';$('fc').textContent=D.counts[i];
 const c=$('ch'),x=c.getContext('2d'),W=c.width,H=c.height;x.clearRect(0,0,W,H);
 const T=D.t[N-1]||1,X=t=>t/T*W;
 const fg=getComputedStyle(document.body).color;
 // rep ticks
 x.strokeStyle='#30a46c';x.lineWidth=1;for(let k=1;k<N;k++)if(D.counts[k]>D.counts[k-1]){x.beginPath();x.moveTo(X(D.t[k]),0);x.lineTo(X(D.t[k]),H);x.stroke();}
 names.filter(n=>on[n]).forEach(n=>{const s=D.series[n];let lo=1e9,hi=-1e9;s.forEach(v=>{if(v!=null){lo=Math.min(lo,v);hi=Math.max(hi,v)}});if(hi==lo)hi=lo+1;
  x.strokeStyle=col[n];x.lineWidth=1.5;x.beginPath();let pen=false;
  s.forEach((v,k)=>{if(v==null){pen=false;return}const px=X(D.t[k]),py=H-8-(v-lo)/(hi-lo)*(H-16);pen?x.lineTo(px,py):x.moveTo(px,py);pen=true});x.stroke();});
 x.strokeStyle=fg;x.lineWidth=1;x.beginPath();x.moveTo(X(D.t[i]),0);x.lineTo(X(D.t[i]),H);x.stroke();
 x.fillStyle=fg;x.fillText('green = rep counted · each signal is scaled to its own min/max',8,12);}
$('sc').oninput=draw;draw();
const KEY='nuvo-label-'+D.sessionId;
function show(){const t=$('tr').value;$('mm').textContent=t===''?'':(+t===D.replayCount?'replay count matches':'replay counted '+D.replayCount+' — off by '+(D.replayCount-t));}
try{const o=JSON.parse(localStorage.getItem(KEY)||'null');if(o){document.querySelectorAll('[name=v]').forEach(r=>r.checked=r.value===o.verdict);$('tr').value=o.trueReps??'';$('nt').value=o.notes||'';$('ss').textContent='loaded saved label';}}catch(e){}
$('tr').oninput=show;show();
$('sv').onclick=()=>{const v=document.querySelector('[name=v]:checked');if(!v){$('ss').textContent='pick correct / wrong / unusable first';return}
 const o={sessionId:D.sessionId,activityId:D.activity,verdict:v.value,trueReps:$('tr').value===''?null:+$('tr').value,appCount:D.recordedCount,replayCount:D.replayCount,engine:D.engine,overrides:D.overrides,notes:$('nt').value,labeledAt:new Date().toISOString(),useForTraining:v.value==='correct'};
 try{localStorage.setItem(KEY,JSON.stringify(o))}catch(e){}
 const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(o,null,2)],{type:'application/json'}));a.download='label_'+D.sessionId+'.json';a.click();$('ss').textContent='saved';};
</script>''';

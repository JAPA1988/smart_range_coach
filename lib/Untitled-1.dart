import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() {
  runApp(const SmartRangeCoachApp());
}

/* ===========================
   APP
=========================== */

class SmartRangeCoachApp extends StatelessWidget {
  const SmartRangeCoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Range Coach',
      theme: ThemeData.dark(),
      home: const DemoSessionScreen(),
    );
  }
}

/* ===========================
   MODELS
=========================== */

enum DiagnosisType { tempo, impact, pfad, release, stabil, unsicher }

class ShotSample {
  final double downswingMs;
  final double impactAudioMs;
  /// Release relativ zu Impact (z. B. -45ms). Wir nutzen nur die Streuung.
  final double releaseRelMs;
  /// Normierte Abweichung (z.B. %). Wir nutzen nur die Streuung.
  final double handPathMetric;

  ShotSample({
    required this.downswingMs,
    required this.impactAudioMs,
    required this.releaseRelMs,
    required this.handPathMetric,
  });
}

class KpiScores {
  final double stk;
  final double its;
  final double hps;
  final double rts;

  KpiScores({
    required this.stk,
    required this.its,
    required this.hps,
    required this.rts,
  });
}

class Diagnosis {
  final DiagnosisType type;
  final String message;

  Diagnosis(this.type, this.message);
}

/* ===========================
   KPI ENGINE
=========================== */

double _mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;

double _stddev(List<double> xs) {
  if (xs.length < 2) return double.nan;
  final m = _mean(xs);
  final v = xs.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b);
  return math.sqrt(v / (xs.length - 1));
}

/// Mappt Sigma in einen 0..100 Score.
/// sigma<=good => 100, sigma>=bad => 0
double _score({
  required double sigma,
  required double good,
  required double bad,
}) {
  final raw = 1 - ((sigma - good) / (bad - good));
  final clamped = raw.clamp(0.0, 1.0);
  return clamped * 100;
}

KpiScores computeKpis(List<ShotSample> shots) {
  final downswing = shots.map((s) => s.downswingMs).toList();
  final impact = shots.map((s) => s.impactAudioMs).toList();
  final releaseRel = shots.map((s) => s.releaseRelMs).toList();
  final handPath = shots.map((s) => s.handPathMetric).toList();

  return KpiScores(
    // STK: good=8ms, bad=25ms
    stk: _score(sigma: _stddev(downswing), good: 8, bad: 25),
    // ITS: good=6ms, bad=18ms
    its: _score(sigma: _stddev(impact), good: 6, bad: 18),
    // HPS: good=0.8, bad=3.0 (normiert)
    hps: _score(sigma: _stddev(handPath), good: 0.8, bad: 3.0),
    // RTS: good=7ms, bad=20ms
    rts: _score(sigma: _stddev(releaseRel), good: 7, bad: 20),
  );
}

/* ===========================
   DIAGNOSIS ENGINE (V1)
=========================== */

Diagnosis diagnose(KpiScores k) {
  // Reihenfolge: STK -> ITS -> HPS -> RTS
  if (k.stk < 65) {
    return Diagnosis(DiagnosisType.tempo, "Dein Schwungtempo ist heute nicht konstant.");
  }
  if (k.its < 60) {
    return Diagnosis(DiagnosisType.impact, "Dein Treffmoment ist heute instabil.");
  }
  if (k.hps < 60) {
    return Diagnosis(DiagnosisType.pfad, "Dein Handpfad ist heute nicht konstant.");
  }
  if (k.rts < 60) {
    return Diagnosis(DiagnosisType.release, "Dein Release kommt zu spät oder ungleichmäßig.");
  }
  return Diagnosis(DiagnosisType.stabil, "Dein Schwung ist heute insgesamt stabil.");
}

/* ===========================
   SCENARIO GENERATOR
=========================== */

enum Scenario { stabil, tempo, impact, pfad, release }

String scenarioLabel(Scenario s) {
  switch (s) {
    case Scenario.stabil:
      return "Stabil";
    case Scenario.tempo:
      return "Tempo";
    case Scenario.impact:
      return "Impact";
    case Scenario.pfad:
      return "Handpfad";
    case Scenario.release:
      return "Release";
  }
}

List<ShotSample> generateShots(Scenario scenario, {int n = 10, int seed = 42}) {
  final rnd = math.Random(seed);

  double jitter(double base, double amp) {
    return base + (rnd.nextDouble() * 2 - 1) * amp;
  }

  // Baselines (realistisch genug für Demo)
  const baseDownswing = 268.0; // ms
  const baseImpact = 1000.0;   // ms (relativ)
  const baseRelease = -45.0;   // ms relativ zu Impact
  const baseHandPath = 1.4;    // normiert

  // Amplituden (je nach Scenario)
  double dsAmp = 2;   // Downswing jitter
  double impAmp = 2;  // Impact jitter
  double relAmp = 2;  // Release jitter
  double hpAmp = 0.15; // Handpath jitter

  // Nur einen KPI "kaputt" machen (V1-typisch)
  switch (scenario) {
    case Scenario.stabil:
      dsAmp = 2; impAmp = 2; relAmp = 2; hpAmp = 0.15;
      break;
    case Scenario.tempo:
      dsAmp = 18; // große Streuung => STK fällt <65
      impAmp = 2; relAmp = 2; hpAmp = 0.15;
      break;
    case Scenario.impact:
      dsAmp = 2;
      impAmp = 14; // große Streuung => ITS fällt <60
      relAmp = 2; hpAmp = 0.15;
      break;
    case Scenario.pfad:
      dsAmp = 2; impAmp = 2; relAmp = 2;
      hpAmp = 1.4; // große Streuung => HPS fällt <60
      break;
    case Scenario.release:
      dsAmp = 2; impAmp = 2; hpAmp = 0.15;
      relAmp = 14; // große Streuung => RTS fällt <60
      break;
  }

  return List.generate(n, (i) {
    return ShotSample(
      downswingMs: jitter(baseDownswing, dsAmp),
      impactAudioMs: jitter(baseImpact + i * 1.5, impAmp), // leichter Drift ok
      releaseRelMs: jitter(baseRelease, relAmp),
      handPathMetric: jitter(baseHandPath, hpAmp),
    );
  });
}

/* ===========================
   UI
=========================== */

class DemoSessionScreen extends StatefulWidget {
  const DemoSessionScreen({super.key});

  @override
  State<DemoSessionScreen> createState() => _DemoSessionScreenState();
}

class _DemoSessionScreenState extends State<DemoSessionScreen> {
  Scenario _scenario = Scenario.impact;
  late List<ShotSample> _shots;

  @override
  void initState() {
    super.initState();
    _shots = generateShots(_scenario, n: 10);
  }

  void _setScenario(Scenario s) {
    setState(() {
      _scenario = s;
      _shots = generateShots(_scenario, n: 10);
    });
  }

  @override
  Widget build(BuildContext context) {
    final kpis = computeKpis(_shots);
    final diagnosis = diagnose(kpis);

    return Scaffold(
      appBar: AppBar(title: const Text("Smart Range Coach – Demo")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Szenario: ${scenarioLabel(_scenario)}",
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: Scenario.values.map((s) {
                final selected = s == _scenario;
                return OutlinedButton(
                  onPressed: () => _setScenario(s),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: selected ? Colors.white12 : null,
                  ),
                  child: Text(scenarioLabel(s)),
                );
              }).toList(),
            ),

            const SizedBox(height: 18),
            Text("KPIs", style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            _kpiRow("STK", kpis.stk),
            _kpiRow("ITS", kpis.its),
            _kpiRow("HPS", kpis.hps),
            _kpiRow("RTS", kpis.rts),

            const Divider(height: 32),
            Text("Diagnose", style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(diagnosis.message, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              "Erwartet: ${_expectedDiagnosisLabel(_scenario)}",
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 50, child: Text("$label:")),
          Text(value.toStringAsFixed(1)),
        ],
      ),
    );
  }

  String _expectedDiagnosisLabel(Scenario s) {
    switch (s) {
      case Scenario.stabil:
        return "Stabil";
      case Scenario.tempo:
        return "Tempo";
      case Scenario.impact:
        return "Impact";
      case Scenario.pfad:
        return "Handpfad";
      case Scenario.release:
        return "Release";
    }
  }
}

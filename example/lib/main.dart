import 'package:synthkit/synthkit.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

void main() {
  runApp(const SynthKitApp());
}

// ─── Theme ────────────────────────────────────────────────────────────────────

class SK {
  static const bg = Color(0xFF07090F);
  static const surface = Color(0xFF0D1117);
  static const card = Color(0xFF111827);
  static const cardHover = Color(0xFF161F30);
  static const border = Color(0xFF1E293B);
  static const borderBright = Color(0xFF2D3F5C);
  static const neon = Color(0xFF00E5B0);
  static const neonDim = Color(0x1A00E5B0);
  static const purple = Color(0xFF8B5CF6);
  static const purpleDim = Color(0x1A8B5CF6);
  static const amber = Color(0xFFF59E0B);
  static const amberDim = Color(0x1AF59E0B);
  static const rose = Color(0xFFF43F5E);
  static const roseDim = Color(0x1AF43F5E);
  static const text = Color(0xFFEFF6FF);
  static const textSub = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF334155);
}

// ─── App ──────────────────────────────────────────────────────────────────────

class SynthKitApp extends StatelessWidget {
  const SynthKitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SynthKit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: SK.bg,
        colorScheme: const ColorScheme.dark(
          primary: SK.neon,
          surface: SK.surface,
        ),
      ),
      home: const _Root(),
    );
  }
}

// ─── Root shell ───────────────────────────────────────────────────────────────

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  int _tab = 0;
  final _engine = SynthKitEngine();
  bool _initialized = false;
  bool _busy = false;
  String _status = 'Tap a control to initialize audio.';
  String? _backend;

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!_initialized) {
        await _engine.initialize(bpm: 112, masterVolume: 0.7);
        _initialized = true;
        _backend = (await _engine.backendName);
      }
      await fn();
    } catch (e) {
      _setStatus('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;

    final pages = <Widget>[
      _LandingPage(onNavigate: (i) => setState(() => _tab = i)),
      BasicPage(engine: _engine, setStatus: _setStatus, run: run),
      UiSoundsPage(engine: _engine, setStatus: _setStatus, run: run),
      LofiPage(engine: _engine, setStatus: _setStatus, run: run),
    ];

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _SideNav(
              tab: _tab,
              onTab: (i) => setState(() => _tab = i),
              status: _status,
              backend: _backend,
              busy: _busy,
            ),
            Expanded(child: pages[_tab]),
          ],
        ),
      );
    }

    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: _BottomBar(
        tab: _tab,
        onTab: (i) => setState(() => _tab = i),
        status: _status,
        busy: _busy,
      ),
    );
  }
}

// ─── Side nav ─────────────────────────────────────────────────────────────────

class _SideNav extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onTab;
  final String status;
  final String? backend;
  final bool busy;
  const _SideNav({
    required this.tab,
    required this.onTab,
    required this.status,
    required this.backend,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: SK.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: SK.neonDim,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: SK.neon.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.graphic_eq, color: SK.neon, size: 16),
                ),
                const SizedBox(width: 12),
                const Text(
                  'synthkit',
                  style: TextStyle(
                    color: SK.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.only(left: 24),
            child: Text(
              'v0.0.1',
              style: TextStyle(
                color: SK.textMuted,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'NAVIGATION',
              style: TextStyle(
                color: SK.textMuted,
                fontSize: 10,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ..._kTabs.asMap().entries.map(
            (e) => _NavItem(
              icon: e.value.$1,
              label: e.value.$2,
              selected: tab == e.key,
              onTap: () => onTab(e.key),
            ),
          ),
          const Spacer(),
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SK.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: SK.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: busy ? SK.amber : SK.neon,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (busy ? SK.amber : SK.neon).withOpacity(0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      busy ? 'WORKING' : 'READY',
                      style: TextStyle(
                        color: busy ? SK.amber : SK.neon,
                        fontSize: 9,
                        letterSpacing: 2,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: const TextStyle(
                    color: SK.textSub,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
                if (backend != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: SK.purpleDim,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: SK.purple.withOpacity(0.3)),
                    ),
                    child: Text(
                      backend!,
                      style: const TextStyle(
                        color: SK.purple,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

const _kTabs = [
  (Icons.home_outlined, 'Overview'),
  (Icons.graphic_eq, 'Basic Synth'),
  (Icons.touch_app_outlined, 'UI Sounds'),
  (Icons.coffee_outlined, 'Lo-Fi Beat'),
];

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? SK.neonDim : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? SK.neon.withOpacity(0.3) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: selected ? SK.neon : SK.textSub),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: selected ? SK.neon : SK.textSub,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom bar (mobile) ──────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onTab;
  final String status;
  final bool busy;
  const _BottomBar({
    required this.tab,
    required this.onTab,
    required this.status,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: SK.surface,
        border: Border(top: BorderSide(color: SK.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: SK.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: busy ? SK.amber : SK.neon,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: SK.textSub, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: Row(
              children: _kTabs.asMap().entries.map((e) {
                final sel = tab == e.key;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onTab(e.key),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            e.value.$1,
                            size: 20,
                            color: sel ? SK.neon : SK.textMuted,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            e.value.$2.split(' ').first,
                            style: TextStyle(
                              fontSize: 10,
                              color: sel ? SK.neon : SK.textMuted,
                            ),
                          ),
                          const SizedBox(height: 3),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 2,
                            width: sel ? 20.0 : 0.0,
                            decoration: BoxDecoration(
                              color: SK.neon,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Landing / Overview ───────────────────────────────────────────────────────

class _LandingPage extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  const _LandingPage({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final maxW = w > 900 ? 800.0 : double.infinity;
    final hPad = w > 800 ? 48.0 : 24.0;

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 56),
                _HeroBanner(),
                const SizedBox(height: 48),

                // Feature pills
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _Pill('4 waveforms', SK.neon),
                    _Pill('ADSR envelope', SK.neon),
                    _Pill('Low-pass filter', SK.neon),
                    _Pill('Beat transport', SK.purple),
                    _Pill('Per-note velocity', SK.purple),
                    _Pill('Delayed triggers', SK.purple),
                    _Pill('Web · iOS · macOS', SK.amber),
                    _Pill('Android · Windows', SK.amber),
                  ],
                ),
                const SizedBox(height: 52),

                _H2('Platform Support'),
                const SizedBox(height: 16),
                const _PlatformTable(),
                const SizedBox(height: 52),

                _H2('Examples'),
                const SizedBox(height: 16),
                _ExGrid(onNavigate: onNavigate),
                const SizedBox(height: 52),

                _H2('Quick Start'),
                const SizedBox(height: 16),
                const _CodeCard(
                  code: r'''import 'package:synthkit/synthkit.dart';

final engine = SynthKitEngine();
await engine.initialize(bpm: 112, masterVolume: 0.7);

final synth = await engine.createSynth(
  const SynthKitSynthOptions(
    waveform: SynthKitWaveform.sawtooth,
    envelope: SynthKitEnvelope(
      attack: Duration(milliseconds: 8),
      decay: Duration(milliseconds: 140),
      sustain: 0.65,
      release: Duration(milliseconds: 260),
    ),
    filter: SynthKitFilter.lowPass(cutoffHz: 1600),
    volume: 0.75,
  ),
);

// Play a note immediately
await synth.triggerAttackRelease(
  SynthKitNote.parse('C4'),
  const Duration(milliseconds: 380),
);

// Schedule a pattern
await engine.transport.schedule(
  synth: synth,
  note: SynthKitNote.parse('G4'),
  beat: 0,
  durationBeats: 0.5,
);
await engine.transport.start();''',
                ),
                const SizedBox(height: 72),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Hero banner ─────────────────────────────────────────────────────────────

class _HeroBanner extends StatefulWidget {
  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: SK.neon,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: SK.neon.withOpacity(0.7), blurRadius: 8),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'pub.dev/packages/synthkit',
              style: TextStyle(
                color: SK.textSub,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'synthkit',
          style: TextStyle(
            color: SK.text,
            fontSize: 52,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Cross-platform Flutter synth plugin\n'
          'for note playback, envelopes,\n'
          'filters, and beat scheduling.',
          style: TextStyle(color: SK.textSub, fontSize: 17, height: 1.65),
        ),
        const SizedBox(height: 28),
        // Waveform — LayoutBuilder avoids infinite-width crash
        LayoutBuilder(
          builder: (ctx, box) {
            final w = box.maxWidth;
            if (w <= 0) return const SizedBox(height: 72);
            return SizedBox(
              height: 72,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => CustomPaint(
                  painter: _WavePainter(_ctrl.value, w),
                  size: Size(w, 72),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WavePainter extends CustomPainter {
  final double phase;
  final double w;
  _WavePainter(this.phase, this.w);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || w <= 0) return;

    final line = Paint()
      ..color = SK.neon.withOpacity(0.9)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final glow = Paint()
      ..color = SK.neon.withOpacity(0.15)
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final mid = size.height / 2;
    // Use a fixed step count based on captured width, never infinity
    final steps = w.clamp(1, 1200).toInt();

    final mp = Path();
    final gp = Path();
    bool first = true;

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = t * size.width;
      final env = math.sin(t * math.pi);
      final y =
          mid + math.sin(t * math.pi * 8 + phase * math.pi * 2) * 26 * env;
      if (first) {
        mp.moveTo(x, y);
        gp.moveTo(x, y);
        first = false;
      } else {
        mp.lineTo(x, y);
        gp.lineTo(x, y);
      }
    }

    canvas.drawPath(gp, glow);
    canvas.drawPath(mp, line);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.phase != phase;
}

// ─── Landing helpers ──────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

Widget _H2(String t) => Text(
  t,
  style: const TextStyle(
    color: SK.text,
    fontSize: 22,
    fontWeight: FontWeight.w700,
  ),
);

class _PlatformTable extends StatelessWidget {
  const _PlatformTable();
  @override
  Widget build(BuildContext context) {
    const rows = [
      ('Web', 'Tone.js (loaded at runtime)', true),
      ('iOS', 'AVAudioEngine', true),
      ('macOS', 'AVAudioEngine', true),
      ('Android', 'AudioTrack', true),
      ('Windows', 'waveOut API', true),
      ('Linux', 'Not implemented', false),
    ];
    return Container(
      decoration: BoxDecoration(
        color: SK.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SK.border),
      ),
      child: Column(
        children: rows.asMap().entries.map((e) {
          final last = e.key == rows.length - 1;
          final r = e.value;
          return Container(
            decoration: last
                ? null
                : BoxDecoration(
                    border: Border(bottom: BorderSide(color: SK.border)),
                  ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    r.$1,
                    style: TextStyle(
                      color: r.$3 ? SK.text : SK.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    r.$2,
                    style: TextStyle(
                      color: r.$3 ? SK.textSub : SK.textMuted,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: r.$3 ? SK.neonDim : SK.roseDim,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: (r.$3 ? SK.neon : SK.rose).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    r.$3 ? 'Supported' : 'Planned',
                    style: TextStyle(
                      color: r.$3 ? SK.neon : SK.rose,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ExGrid extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  const _ExGrid({required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        1,
        Icons.graphic_eq,
        'Basic Synth',
        SK.neon,
        'Sawtooth oscillator · low-pass filter · ADSR envelope · one-shot and scheduled pattern playback.',
      ),
      (
        2,
        Icons.touch_app_outlined,
        'UI Sounds',
        SK.amber,
        'Click, hover, accept, cancel, error, success, and notification tones — ready to drop into any app.',
      ),
      (
        3,
        Icons.coffee_outlined,
        'Lo-Fi Beat',
        SK.purple,
        '8-bar Fmaj7–Em7–Dm7–Cmaj7 loop at 78 BPM with pad, bass, lead melody and arpeggio.',
      ),
    ];
    return Column(
      children: items
          .map(
            (ex) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ExCard(
                icon: ex.$2,
                title: ex.$3,
                color: ex.$4,
                desc: ex.$5,
                onTap: () => onNavigate(ex.$1),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ExCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final Color color;
  final String desc;
  final VoidCallback onTap;
  const _ExCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.desc,
    required this.onTap,
  });
  @override
  State<_ExCard> createState() => _ExCardState();
}

class _ExCardState extends State<_ExCard> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _h ? SK.cardHover : SK.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _h ? widget.color.withOpacity(0.4) : SK.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: widget.color.withOpacity(0.25)),
                ),
                child: Icon(widget.icon, color: widget.color, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: SK.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.desc,
                      style: const TextStyle(
                        color: SK.textSub,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.arrow_forward,
                size: 16,
                color: _h ? widget.color : SK.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  final String code;
  const _CodeCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF060A10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SK.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: SK.border)),
            ),
            child: Row(
              children: [
                _dot(SK.rose),
                const SizedBox(width: 6),
                _dot(SK.amber),
                const SizedBox(width: 6),
                _dot(SK.neon),
                const SizedBox(width: 16),
                const Text(
                  'main.dart',
                  style: TextStyle(
                    color: SK.textMuted,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(20),
            child: _SyntaxText(code),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: c.withOpacity(0.7),
      shape: BoxShape.circle,
    ),
  );
}

class _SyntaxText extends StatelessWidget {
  final String code;
  const _SyntaxText(this.code);

  static const _kws = ['await', 'final', 'const', 'return', 'async'];
  static const _types = [
    'SynthKitSynthOptions',
    'SynthKitWaveform',
    'SynthKitEnvelope',
    'SynthKitFilter',
    'SynthKitNote',
    'SynthKitEngine',
    'SynthKitSynth',
    'SynthKitTransport',
    'Duration',
  ];

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (final line in code.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//')) {
        spans.add(
          TextSpan(
            text: '$line\n',
            style: const TextStyle(color: Color(0xFF4B6175)),
          ),
        );
      } else if (trimmed.startsWith("import '")) {
        spans.add(
          TextSpan(
            text: '$line\n',
            style: const TextStyle(color: Color(0xFF86EFAC)),
          ),
        );
      } else {
        spans.addAll(_parseLine(line));
        spans.add(const TextSpan(text: '\n'));
      }
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 13,
          height: 1.7,
          fontFamily: 'monospace',
        ),
        children: spans,
      ),
    );
  }

  List<TextSpan> _parseLine(String src) {
    final out = <TextSpan>[];
    var rest = src;
    while (rest.isNotEmpty) {
      // string literal
      final sm = RegExp(r"'[^']*'").matchAsPrefix(rest);
      if (sm != null) {
        out.add(
          TextSpan(
            text: sm.group(0),
            style: const TextStyle(color: Color(0xFFFBBF24)),
          ),
        );
        rest = rest.substring(sm.end);
        continue;
      }
      // types
      bool hit = false;
      for (final t in _types) {
        if (rest.startsWith(t) &&
            (rest.length == t.length ||
                !RegExp(r'\w').hasMatch(rest[t.length]))) {
          out.add(
            TextSpan(
              text: t,
              style: const TextStyle(color: Color(0xFF67E8F9)),
            ),
          );
          rest = rest.substring(t.length);
          hit = true;
          break;
        }
      }
      if (hit) continue;
      // keywords
      for (final kw in _kws) {
        if (rest.startsWith(kw) &&
            (rest.length == kw.length ||
                !RegExp(r'\w').hasMatch(rest[kw.length]))) {
          out.add(
            TextSpan(
              text: kw,
              style: const TextStyle(color: Color(0xFFC084FC)),
            ),
          );
          rest = rest.substring(kw.length);
          hit = true;
          break;
        }
      }
      if (hit) continue;
      // digit
      final isNum = RegExp(r'[0-9]').hasMatch(rest[0]);
      out.add(
        TextSpan(
          text: rest[0],
          style: TextStyle(
            color: isNum ? const Color(0xFF86EFAC) : const Color(0xFFCDD9E5),
          ),
        ),
      );
      rest = rest.substring(1);
    }
    return out;
  }
}

// ─── Basic Page ───────────────────────────────────────────────────────────────

class BasicPage extends StatefulWidget {
  final SynthKitEngine engine;
  final void Function(String) setStatus;
  final Future<void> Function(Future<void> Function()) run;
  const BasicPage({
    super.key,
    required this.engine,
    required this.setStatus,
    required this.run,
  });
  @override
  State<BasicPage> createState() => _BasicPageState();
}

class _BasicPageState extends State<BasicPage> {
  SynthKitSynth? _synth;

  Future<void> _ensure() async {
    _synth ??= await widget.engine.createSynth(
      const SynthKitSynthOptions(
        waveform: SynthKitWaveform.sawtooth,
        envelope: SynthKitEnvelope(
          attack: Duration(milliseconds: 8),
          decay: Duration(milliseconds: 140),
          sustain: 0.65,
          release: Duration(milliseconds: 260),
        ),
        filter: SynthKitFilter.lowPass(cutoffHz: 1600),
        volume: 0.75,
      ),
    );
  }

  Future<void> _oneShot() async {
    await widget.run(() async {
      await _ensure();
      await _synth!.triggerAttackRelease(
        SynthKitNote.parse('C4'),
        const Duration(milliseconds: 380),
      );
      widget.setStatus('Played C4 one-shot.');
    });
  }

  Future<void> _pattern() async {
    await widget.run(() async {
      await _ensure();
      await widget.engine.transport.stop(clearSequence: true);
      await widget.engine.transport.setBpm(112);
      const notes = [
        ('A3', 0.0, 0.5),
        ('C4', 1.0, 0.5),
        ('E4', 2.0, 0.5),
        ('G4', 3.0, 1.0),
      ];
      for (final n in notes) {
        await widget.engine.transport.schedule(
          synth: _synth!,
          note: SynthKitNote.parse(n.$1),
          beat: n.$2,
          durationBeats: n.$3,
        );
      }
      await widget.engine.transport.start();
      widget.setStatus('Playing A3–C4–E4–G4 at 112 BPM.');
    });
  }

  Future<void> _stop() async {
    await widget.run(() async {
      await widget.engine.transport.stop();
      widget.setStatus('Transport stopped.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ExPage(
      icon: Icons.graphic_eq,
      color: SK.neon,
      title: 'Basic Synth',
      subtitle: 'Sawtooth · Low-pass filter · ADSR envelope',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PropGrid(
            items: const [
              ('Waveform', 'sawtooth'),
              ('Filter', 'lowPass  1600 Hz'),
              ('Attack', '8 ms'),
              ('Decay', '140 ms'),
              ('Sustain', '65%'),
              ('Release', '260 ms'),
              ('Volume', '0.75'),
              ('BPM', '112'),
            ],
          ),
          const SizedBox(height: 24),
          _Label('PATTERN NOTES'),
          const SizedBox(height: 10),
          Row(
            children: ['A3', 'C4', 'E4', 'G4']
                .map(
                  (n) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: SK.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: SK.neon.withOpacity(0.2)),
                      ),
                      child: Text(
                        n,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: SK.neon,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 24),
          _Label('CONTROLS'),
          const SizedBox(height: 12),
          _Btn(
            label: 'Play One-Shot  C4',
            icon: Icons.music_note,
            color: SK.neon,
            onTap: _oneShot,
          ),
          const SizedBox(height: 10),
          _Btn(
            label: 'Play Pattern',
            icon: Icons.queue_music,
            color: SK.purple,
            onTap: _pattern,
          ),
          const SizedBox(height: 10),
          _Btn(
            label: 'Stop',
            icon: Icons.stop,
            color: SK.rose,
            onTap: _stop,
            ghost: true,
          ),
        ],
      ),
    );
  }
}

// ─── UI Sounds Page ───────────────────────────────────────────────────────────

class UiSoundsPage extends StatefulWidget {
  final SynthKitEngine engine;
  final void Function(String) setStatus;
  final Future<void> Function(Future<void> Function()) run;
  const UiSoundsPage({
    super.key,
    required this.engine,
    required this.setStatus,
    required this.run,
  });
  @override
  State<UiSoundsPage> createState() => _UiSoundsPageState();
}

class _UiSoundsPageState extends State<UiSoundsPage> {
  SynthKitSynth? _s;

  Future<void> _ensure() async {
    _s ??= await widget.engine.createSynth(
      const SynthKitSynthOptions(waveform: SynthKitWaveform.sine, volume: 0.6),
    );
  }

  Future<void> _play(
    SynthKitSynthOptions opts,
    List<(String, int)> notes,
    String msg,
  ) async {
    await widget.run(() async {
      await _ensure();
      await _s!.update(opts);
      for (final n in notes) {
        await _s!.triggerAttackRelease(
          SynthKitNote.parse(n.$1),
          const Duration(milliseconds: 200),
          delay: Duration(milliseconds: n.$2),
        );
      }
      widget.setStatus(msg);
    });
  }

  @override
  Widget build(BuildContext context) {
    const e0 = SynthKitEnvelope(
      attack: Duration(milliseconds: 1),
      decay: Duration(milliseconds: 30),
      sustain: 0,
      release: Duration(milliseconds: 10),
    );
    const e1 = SynthKitEnvelope(
      attack: Duration(milliseconds: 1),
      decay: Duration(milliseconds: 15),
      sustain: 0,
      release: Duration(milliseconds: 10),
    );
    const e2 = SynthKitEnvelope(
      attack: Duration(milliseconds: 5),
      decay: Duration(milliseconds: 100),
      sustain: 0,
      release: Duration(milliseconds: 100),
    );
    const e3 = SynthKitEnvelope(
      attack: Duration(milliseconds: 10),
      decay: Duration(milliseconds: 100),
      sustain: 0,
      release: Duration(milliseconds: 100),
    );
    const e4 = SynthKitEnvelope(
      attack: Duration(milliseconds: 10),
      decay: Duration(milliseconds: 200),
      sustain: 0,
      release: Duration(milliseconds: 100),
    );
    const e5 = SynthKitEnvelope(
      attack: Duration(milliseconds: 5),
      decay: Duration(milliseconds: 150),
      sustain: 0,
      release: Duration(milliseconds: 200),
    );
    const e6 = SynthKitEnvelope(
      attack: Duration(milliseconds: 5),
      decay: Duration(milliseconds: 300),
      sustain: 0,
      release: Duration(milliseconds: 400),
    );

    final sounds = [
      (
        'Click',
        Icons.touch_app,
        SK.neon,
        SynthKitSynthOptions(
          waveform: SynthKitWaveform.sine,
          envelope: e0,
          volume: 0.5,
        ),
        [('C6', 0)],
        'Click — sine · C6',
      ),
      (
        'Hover',
        Icons.mouse_outlined,
        SK.neon,
        SynthKitSynthOptions(
          waveform: SynthKitWaveform.sine,
          envelope: e1,
          volume: 0.2,
        ),
        [('F5', 0)],
        'Hover — sine · F5',
      ),
      (
        'Accept',
        Icons.check_circle_outline,
        SK.neon,
        SynthKitSynthOptions(
          waveform: SynthKitWaveform.triangle,
          envelope: e2,
          filter: SynthKitFilter.lowPass(cutoffHz: 2000),
          volume: 0.6,
        ),
        [('C5', 0), ('E5', 100)],
        'Accept — triangle · C5 → E5',
      ),
      (
        'Cancel',
        Icons.cancel_outlined,
        SK.amber,
        SynthKitSynthOptions(
          waveform: SynthKitWaveform.square,
          envelope: e3,
          filter: SynthKitFilter.lowPass(cutoffHz: 600),
          volume: 0.4,
        ),
        [('E4', 0), ('C4', 120)],
        'Cancel — square · E4 → C4',
      ),
      (
        'Error',
        Icons.error_outline,
        SK.rose,
        SynthKitSynthOptions(
          waveform: SynthKitWaveform.sawtooth,
          envelope: e4,
          filter: SynthKitFilter.lowPass(cutoffHz: 800),
          volume: 0.6,
        ),
        [('Eb4', 0), ('A3', 160)],
        'Error — sawtooth · tritone',
      ),
      (
        'Success',
        Icons.star_outline,
        SK.neon,
        SynthKitSynthOptions(
          waveform: SynthKitWaveform.triangle,
          envelope: e5,
          filter: SynthKitFilter.lowPass(cutoffHz: 3000),
          volume: 0.5,
        ),
        [('C5', 0), ('E5', 100), ('G5', 200), ('C6', 300)],
        'Success — triangle arpeggio',
      ),
      (
        'Notification',
        Icons.notifications_outlined,
        SK.purple,
        SynthKitSynthOptions(
          waveform: SynthKitWaveform.sine,
          envelope: e6,
          volume: 0.5,
        ),
        [('A5', 0), ('E6', 150)],
        'Notification — sine · perfect fifth',
      ),
    ];

    return _ExPage(
      icon: Icons.touch_app_outlined,
      color: SK.amber,
      title: 'UI Sounds',
      subtitle: 'Tap any tile to audition the synthesized sound',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: sounds
            .map(
              (s) => _SoundTile(
                label: s.$1,
                icon: s.$2,
                color: s.$3,
                onTap: () => _play(s.$4, s.$5, s.$6),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SoundTile extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SoundTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  State<_SoundTile> createState() => _SoundTileState();
}

class _SoundTileState extends State<_SoundTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  bool _h = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _scale = Tween(
      begin: 1.0,
      end: 0.93,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _tap() async {
    await _ctrl.forward();
    widget.onTap();
    await _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final pad = w > 800 ? 96.0 : (w > 400 ? 48.0 : 48.0);
    final tileW = ((w - pad) / (w >= 600 ? 4.0 : 2.0) - 10.0).clamp(
      100.0,
      200.0,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: _tap,
        child: ScaleTransition(
          scale: _scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: tileW,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _h ? SK.cardHover : SK.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _h ? widget.color.withOpacity(0.4) : SK.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 18),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: SK.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Lo-Fi Page ───────────────────────────────────────────────────────────────

class LofiPage extends StatefulWidget {
  final SynthKitEngine engine;
  final void Function(String) setStatus;
  final Future<void> Function(Future<void> Function()) run;
  const LofiPage({
    super.key,
    required this.engine,
    required this.setStatus,
    required this.run,
  });
  @override
  State<LofiPage> createState() => _LofiPageState();
}

class _LofiPageState extends State<LofiPage>
    with SingleTickerProviderStateMixin {
  SynthKitSynth? _pad, _bass, _lead, _arp;
  bool _playing = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _ensure() async {
    if (_pad != null) return;
    _pad = await widget.engine.createSynth(
      const SynthKitSynthOptions(
        waveform: SynthKitWaveform.triangle,
        envelope: SynthKitEnvelope(
          attack: Duration(milliseconds: 200),
          decay: Duration(milliseconds: 400),
          sustain: 0.6,
          release: Duration(milliseconds: 1500),
        ),
        filter: SynthKitFilter.lowPass(cutoffHz: 800),
        volume: 0.35,
      ),
    );
    _bass = await widget.engine.createSynth(
      const SynthKitSynthOptions(
        waveform: SynthKitWaveform.sine,
        envelope: SynthKitEnvelope(
          attack: Duration(milliseconds: 50),
          decay: Duration(milliseconds: 400),
          sustain: 0.8,
          release: Duration(milliseconds: 800),
        ),
        filter: SynthKitFilter.lowPass(cutoffHz: 300),
        volume: 0.6,
      ),
    );
    _lead = await widget.engine.createSynth(
      const SynthKitSynthOptions(
        waveform: SynthKitWaveform.square,
        envelope: SynthKitEnvelope(
          attack: Duration(milliseconds: 20),
          decay: Duration(milliseconds: 200),
          sustain: 0.3,
          release: Duration(milliseconds: 600),
        ),
        filter: SynthKitFilter.lowPass(cutoffHz: 1200),
        volume: 0.2,
      ),
    );
    _arp = await widget.engine.createSynth(
      const SynthKitSynthOptions(
        waveform: SynthKitWaveform.triangle,
        envelope: SynthKitEnvelope(
          attack: Duration(milliseconds: 5),
          decay: Duration(milliseconds: 80),
          sustain: 0.1,
          release: Duration(milliseconds: 200),
        ),
        filter: SynthKitFilter.lowPass(cutoffHz: 1500),
        volume: 0.15,
      ),
    );
  }

  Future<void> _toggle() async {
    await widget.run(() async {
      if (_playing) {
        await widget.engine.transport.stop(clearSequence: true);
        setState(() => _playing = false);
        widget.setStatus('Stopped lo-fi sequence.');
        return;
      }
      await _ensure();
      await widget.engine.transport.stop(clearSequence: true);
      await widget.engine.transport.setBpm(78);

      final chords = [
        ['F3', 'A3', 'C4', 'E4'],
        ['E3', 'G3', 'B3', 'D4'],
        ['D3', 'F3', 'A3', 'C4'],
        ['C3', 'E3', 'G3', 'B3'],
      ];
      final bass = ['F2', 'E2', 'D2', 'C2'];

      for (int i = 0; i < 2; i++) {
        final off = i * 16.0;
        for (int c = 0; c < 4; c++) {
          final ms = off + c * 4.0;
          await widget.engine.transport.schedule(
            synth: _bass!,
            note: SynthKitNote.parse(bass[c]),
            beat: ms,
            durationBeats: 1.5,
          );
          await widget.engine.transport.schedule(
            synth: _bass!,
            note: SynthKitNote.parse(bass[c]),
            beat: ms + 2.5,
            durationBeats: 1.0,
          );
          for (final n in chords[c]) {
            await widget.engine.transport.schedule(
              synth: _pad!,
              note: SynthKitNote.parse(n),
              beat: ms,
              durationBeats: 1.0,
            );
            await widget.engine.transport.schedule(
              synth: _pad!,
              note: SynthKitNote.parse(n),
              beat: ms + 1.5,
              durationBeats: 0.5,
            );
            await widget.engine.transport.schedule(
              synth: _pad!,
              note: SynthKitNote.parse(n),
              beat: ms + 2.5,
              durationBeats: 1.5,
            );
          }
          for (int s = 0; s < 8; s++) {
            final raw = chords[c][s % 4];
            final oct = int.parse(raw[raw.length - 1]) + 1;
            await widget.engine.transport.schedule(
              synth: _arp!,
              note: SynthKitNote.parse(
                '${raw.substring(0, raw.length - 1)}$oct',
              ),
              beat: ms + s * 0.5,
              durationBeats: 0.25,
            );
          }
        }
        final ll = i == 0
            ? [
                ('A5', 0.0, 1.5),
                ('G5', 2.0, 0.25),
                ('F5', 2.5, 1.0),
                ('G5', 4.0, 1.0),
                ('E5', 5.5, 1.5),
                ('F5', 8.0, 1.0),
                ('D5', 9.5, 1.5),
                ('E5', 12.0, 1.0),
                ('C5', 13.5, 2.0),
              ]
            : [
                ('C6', 0.0, 1.5),
                ('A5', 2.0, 0.25),
                ('G5', 2.5, 1.0),
                ('G5', 4.0, 1.0),
                ('E5', 5.5, 1.5),
                ('D5', 8.0, 0.5),
                ('E5', 8.5, 0.5),
                ('F5', 9.0, 0.5),
                ('G5', 9.5, 1.5),
                ('C5', 12.0, 3.0),
              ];
        for (final l in ll) {
          await widget.engine.transport.schedule(
            synth: _lead!,
            note: SynthKitNote.parse(l.$1),
            beat: off + l.$2,
            durationBeats: l.$3,
          );
        }
      }
      await widget.engine.transport.start();
      setState(() => _playing = true);
      widget.setStatus('Playing 8-bar lo-fi at 78 BPM...');
    });
  }

  @override
  Widget build(BuildContext context) {
    const layers = [
      ('PAD', 'Triangle', 'LP 800 Hz', '0.35', SK.purple),
      ('BASS', 'Sine', 'LP 300 Hz', '0.60', SK.neon),
      ('LEAD', 'Square', 'LP 1200 Hz', '0.20', SK.amber),
      ('ARP', 'Triangle', 'LP 1500 Hz', '0.15', Color(0xFFF472B6)),
    ];
    const chords = [
      ('I', 'Fmaj7', 'F A C E'),
      ('vi', 'Em7', 'E G B D'),
      ('ii', 'Dm7', 'D F A C'),
      ('IV', 'Cmaj7', 'C E G B'),
    ];

    return _ExPage(
      icon: Icons.coffee_outlined,
      color: SK.purple,
      title: 'Lo-Fi Beat',
      subtitle: '8 bars · Fmaj7–Em7–Dm7–Cmaj7 · 78 BPM',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label('SYNTH LAYERS'),
          const SizedBox(height: 10),
          ...layers.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: SK.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SK.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 30,
                      decoration: BoxDecoration(
                        color: l.$5,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 40,
                      child: Text(
                        l.$1,
                        style: TextStyle(
                          color: l.$5,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${l.$2} · ${l.$3}',
                        style: const TextStyle(color: SK.textSub, fontSize: 12),
                      ),
                    ),
                    Text(
                      'vol ${l.$4}',
                      style: const TextStyle(
                        color: SK.textMuted,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _Label('CHORD PROGRESSION'),
          const SizedBox(height: 10),
          Row(
            children: chords
                .map(
                  (c) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 6,
                      ),
                      decoration: BoxDecoration(
                        color: SK.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: SK.border),
                      ),
                      child: Column(
                        children: [
                          Text(
                            c.$1,
                            style: const TextStyle(
                              color: SK.textMuted,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c.$2,
                            style: const TextStyle(
                              color: SK.purple,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c.$3,
                            style: const TextStyle(
                              color: SK.textMuted,
                              fontSize: 9,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: _toggle,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final g = _playing ? (_pulse.value * 0.3 + 0.1) : 0.0;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: _playing ? SK.purple.withOpacity(0.12) : SK.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _playing
                          ? SK.purple.withOpacity(0.5 + g)
                          : SK.borderBright,
                      width: 1.5,
                    ),
                    boxShadow: _playing
                        ? [
                            BoxShadow(
                              color: SK.purple.withOpacity(g * 0.5),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _playing
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        color: _playing ? SK.purple : SK.text,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _playing ? 'STOP' : 'PLAY  LO-FI',
                        style: TextStyle(
                          color: _playing ? SK.purple : SK.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared page scaffold ─────────────────────────────────────────────────────

class _ExPage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget child;
  const _ExPage({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final maxW = w > 900 ? 780.0 : double.infinity;
    final hPad = w > 800 ? 48.0 : 24.0;

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withOpacity(0.25)),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: SK.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: SK.textSub,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const Divider(color: SK.border),
                const SizedBox(height: 28),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _PropGrid extends StatelessWidget {
  final List<(String, String)> items;
  const _PropGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SK.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SK.border),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final last = e.key == items.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: last
                ? null
                : BoxDecoration(
                    border: Border(bottom: BorderSide(color: SK.border)),
                  ),
            child: Row(
              children: [
                Text(
                  e.value.$1,
                  style: const TextStyle(color: SK.textSub, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  e.value.$2,
                  style: const TextStyle(
                    color: SK.neon,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

Widget _Label(String t) => Text(
  t,
  style: const TextStyle(color: SK.textMuted, fontSize: 10, letterSpacing: 2),
);

class _Btn extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool ghost;
  const _Btn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.ghost = false,
  });
  @override
  State<_Btn> createState() => _BtnState();
}

class _BtnState extends State<_Btn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: widget.ghost
                ? Colors.transparent
                : widget.color.withOpacity(_h ? 0.18 : 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.color.withOpacity(widget.ghost ? 0.4 : 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: widget.color, size: 17),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

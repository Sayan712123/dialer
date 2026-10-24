import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

// Palette approximated from screenshots of the Xiaomi dialer.
const kGreen = Color(0xFF2DAA4F);
const kMissed = Color(0xFFFA382E);
const kGrey = Color(0xFF8E8E93);

void main() => runApp(const ContactsDialerApp());

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(seedColor: kGreen, brightness: b)
        .copyWith(primary: kGreen, surface: dark ? const Color(0xFF1C1C1E) : Colors.white),
    scaffoldBackgroundColor: dark ? Colors.black : const Color(0xFFF7F7F7),
    splashFactory: NoSplash.splashFactory,
    dividerColor: dark ? Colors.white12 : Colors.black12,
  );
}

class ContactsDialerApp extends StatelessWidget {
  const ContactsDialerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Phone',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const HomeShell(),
      );
}

Color cardColor(BuildContext c) => Theme.of(c).colorScheme.surface;
Color textColor(BuildContext c) => Theme.of(c).colorScheme.onSurface;

String contactName(Contact c) {
  if (c.displayName.trim().isNotEmpty) return c.displayName.trim();
  if (c.phones.isNotEmpty) return c.phones.first.number;
  if (c.emails.isNotEmpty) return c.emails.first.address;
  return '';
}

Future<void> placeCall(BuildContext context, String number) async {
  if (number.trim().isEmpty) return;
  if (await Permission.phone.request().isGranted) {
    await FlutterPhoneDirectCaller.callNumber(number);
  } else {
    await launchUrl(Uri(scheme: 'tel', path: number));
  }
}

const _avatarColors = [
  Color(0xFF2F6BDE), Color(0xFF1BB5C4), Color(0xFF7B42D6),
  Color(0xFF22B86A), Color(0xFFB03CC0), Color(0xFFF08A1C),
];

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  const Avatar(this.name, {super.key, this.size = 52});
  @override
  Widget build(BuildContext context) {
    final c = _avatarColors[(name.isEmpty ? 0 : name.codeUnitAt(0)) % _avatarColors.length];
    final isLetter =
        name.isNotEmpty && RegExp(r'\p{L}', unicode: true).hasMatch(name.characters.first);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        child: isLetter
            ? Text(name.characters.first.toUpperCase(),
                style: TextStyle(color: Colors.white, fontSize: size * .45))
            : Icon(Icons.person, color: Colors.white, size: size * .55),
      ),
    );
  }
}

/// Press feedback: quick shrink + dim, springy release, light haptic.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  const Pressable(
      {super.key,
      required this.child,
      this.onTap,
      this.onLongPress,
      this.scale = .95,
      this.haptic = true});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  void _set(bool v) => setState(() => _down = v);
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Duration(milliseconds: _down ? 80 : 300),
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: AnimatedOpacity(
              opacity: _down ? .7 : 1,
              duration: const Duration(milliseconds: 100),
              child: widget.child),
        ),
      );
}

class FadeSlideIn extends StatelessWidget {
  final int index;
  final Widget child;
  const FadeSlideIn({super.key, required this.index, required this.child});
  @override
  Widget build(BuildContext context) {
    if (index > 12) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + index * 45),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: c)),
      child: child,
    );
  }
}

Route<T> miuiRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, sa, child) {
        final inCurve = CurvedAnimation(
            parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        final outCurve = CurvedAnimation(parent: sa, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween(begin: Offset.zero, end: const Offset(-.25, 0)).animate(outCurve),
          child: SlideTransition(
            position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(inCurve),
            child: child,
          ),
        );
      },
    );

Widget bigHeader(String title, {List<Widget>? actions}) => SliverAppBar.large(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 40)),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      actions: actions,
    );

// ---------------- Shell ----------------
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  bool _keypad = false;
  String _num = '';
  static const _ch = MethodChannel('dialer');
  bool _isDefault = true; // banner stays hidden until we know

  @override
  void initState() {
    super.initState();
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'dial' && mounted) {
        setState(() {
          _num = call.arguments as String;
          _keypad = true;
          _tab = 0;
        });
      }
    });
    _init();
  }

  Future<void> _init() async {
    await _checkDefault();
    try {
      final n = await _ch.invokeMethod<String>('initialNumber');
      if (n != null && n.isNotEmpty && mounted) {
        setState(() {
          _num = n;
          _keypad = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkDefault() async {
    try {
      final v = await _ch.invokeMethod<bool>('isDefault');
      if (mounted) setState(() => _isDefault = v ?? false);
    } catch (_) {}
  }

  Future<void> _makeDefault() async {
    try {
      await _ch.invokeMethod<bool>('requestDefault');
    } catch (_) {}
    _checkDefault();
  }

  Widget _tabPage(int i, Widget page) {
    final active = _tab == i;
    return IgnorePointer(
      ignoring: !active,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: AnimatedSlide(
          offset: active ? Offset.zero : Offset(i == 0 ? -.06 : .06, 0),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: page,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showFab = _tab == 0 && !_keypad;
    return Scaffold(
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            _tabPage(0, const CallsPage()),
            _tabPage(1, const ContactsPage()),
            Positioned(
              right: 24,
              bottom: 16,
              child: IgnorePointer(
                ignoring: !showFab,
                child: AnimatedScale(
                  scale: showFab ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: Pressable(
                    scale: .9,
                    onTap: () => setState(() => _keypad = true),
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle, boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))
                      ]),
                      child: const Icon(Icons.dialpad, color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
        if (!_isDefault)
          Container(
            width: double.infinity,
            color: cardColor(context),
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              const Expanded(
                  child: Text('Make this your default Phone app to handle calls',
                      style: TextStyle(fontSize: 13))),
              TextButton(onPressed: _makeDefault, child: const Text('Set')),
            ]),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                    position: Tween(begin: const Offset(0, .25), end: Offset.zero).animate(a),
                    child: c)),
            child: _keypad
                ? KeypadPanel(
                    key: const ValueKey('kp'),
                    number: _num,
                    onChanged: (v) => setState(() => _num = v),
                    onHide: () => setState(() => _keypad = false))
                : const SizedBox(key: ValueKey('none'), width: double.infinity),
          ),
        ),
      ]),
      bottomNavigationBar: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(children: [
              _NavItem(Icons.call_outlined, Icons.call, 'Calls', _tab == 0,
                  () => setState(() => _tab = 0)),
              _NavItem(Icons.contacts_outlined, Icons.contacts, 'Contacts', _tab == 1,
                  () => setState(() => _tab = 1)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData iconOn;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem(this.icon, this.iconOn, this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) {
    final c = selected ? textColor(context) : kGrey;
    return Expanded(
      child: Pressable(
        onTap: onTap,
        scale: .9,
        child: SizedBox.expand(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedScale(
              scale: selected ? 1.1 : 1,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: Icon(selected ? iconOn : icon, color: c, size: 26),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(color: c, fontSize: 12),
              child: Text(label),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------- Keypad ----------------
class KeypadPanel extends StatelessWidget {
  final String number;
  final ValueChanged<String> onChanged;
  final VoidCallback onHide;
  const KeypadPanel(
      {super.key, required this.number, required this.onChanged, required this.onHide});

  static const _keys = [
    ['1', ''], ['2', 'ABC'], ['3', 'DEF'],
    ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'],
    ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'],
    ['*', ','], ['0', '+'], ['#', ';'],
  ];

  @override
  Widget build(BuildContext context) => GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) onHide();
        },
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
              color: cardColor(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: kGrey.withOpacity(.4), borderRadius: BorderRadius.circular(2))),
            SizedBox(
              height: 52,
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  style: TextStyle(
                      fontSize: number.length > 14 ? 22 : (number.length > 10 ? 27 : 32),
                      fontWeight: FontWeight.w300,
                      color: textColor(context)),
                  child: Text(number, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              childAspectRatio: 1.75,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final k in _keys)
                  Pressable(
                    scale: .85,
                    onTap: () => onChanged(number + k[0]),
                    onLongPress: k[0] == '0' ? () => onChanged('$number+') : null,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(k[0], style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w300)),
                      SizedBox(
                        height: 14,
                        child: k[0] == '1'
                            ? const Icon(Icons.voicemail, size: 15, color: kGrey)
                            : Text(k[1], style: const TextStyle(fontSize: 11, color: kGrey)),
                      ),
                    ]),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              SizedBox(
                width: 64,
                child: Pressable(
                    onTap: onHide,
                    child: Icon(Icons.dialpad, size: 28, color: textColor(context))),
              ),
              Pressable(
                scale: .92,
                onTap: () => placeCall(context, number),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
                  child: const Icon(Icons.call, color: Colors.white, size: 34),
                ),
              ),
              SizedBox(
                width: 64,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: number.isEmpty
                      ? const SizedBox.shrink(key: ValueKey(0))
                      : Pressable(
                          key: const ValueKey(1),
                          onTap: () => onChanged(number.substring(0, number.length - 1)),
                          onLongPress: () => onChanged(''),
                          child: const Icon(Icons.backspace_outlined, size: 28, color: kGrey)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
      );
}

// ---------------- Calls ----------------
class CallsPage extends StatefulWidget {
  const CallsPage({super.key});
  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  List<CallLogEntry>? _entries;
  bool _denied = false;
  bool _missedOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!await Permission.phone.request().isGranted) {
      setState(() => _denied = true);
      return;
    }
    final it = await CallLog.query();
    setState(() {
      _denied = false;
      _entries = it.toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = (_entries ?? [])
        .where((e) => !_missedOnly || e.callType == CallType.missed)
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(slivers: [
        bigHeader('Calls', actions: [
          PopupMenuButton<bool>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) => setState(() => _missedOnly = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: false, child: Text('All calls')),
              PopupMenuItem(value: true, child: Text('Missed calls only')),
            ],
          ),
        ]),
        if (_denied)
          SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                  child: FilledButton(
                      onPressed: _load, child: const Text('Allow call log access'))))
        else if (_entries == null)
          const SliverFillRemaining(
              hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
        else if (list.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No calls')))
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => FadeSlideIn(index: i, child: _CallTile(entry: list[i])),
              childCount: list.length > 300 ? 300 : list.length,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ]),
    );
  }
}

String _when(int? ms) {
  if (ms == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return '${two(d.hour)}:${two(d.minute)}';
  }
  return '${d.year}/${two(d.month)}/${two(d.day)}';
}

class _HdBadge extends StatelessWidget {
  const _HdBadge();
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
            color: kGrey.withOpacity(.25), borderRadius: BorderRadius.circular(3)),
        child: const Text('HD',
            style: TextStyle(fontSize: 8, color: kGrey, fontWeight: FontWeight.bold)),
      );
}

class _CallTile extends StatelessWidget {
  final CallLogEntry entry;
  const _CallTile({required this.entry});
  @override
  Widget build(BuildContext context) {
    final hasName = entry.name?.isNotEmpty ?? false;
    final number = entry.number ?? '';
    final title = hasName ? entry.name! : (number.isEmpty ? 'Unknown' : number);
    final missed = entry.callType == CallType.missed;
    final out = entry.callType == CallType.outgoing;
    final kind = switch (entry.callType) {
      CallType.outgoing => 'Outgoing',
      CallType.missed => 'Missed',
      CallType.rejected => 'Declined',
      _ => 'Incoming',
    };
    return Pressable(
      scale: .98,
      haptic: false,
      onTap: () => placeCall(context, number),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 20, 12),
        child: Row(children: [
          Icon(out ? Icons.north_west : Icons.south_east,
              size: 18, color: missed ? kMissed : kGrey),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 19, color: missed ? kMissed : null)),
              const SizedBox(height: 3),
              Row(children: [
                const _HdBadge(),
                Expanded(
                  child: Text(hasName ? number : kind,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: kGrey)),
                ),
              ]),
            ]),
          ),
          Text(_when(entry.timestamp), style: const TextStyle(fontSize: 14, color: kGrey)),
          const SizedBox(width: 12),
          Pressable(
            onTap: () => Navigator.push(
                context,
                miuiRoute(DetailPage(
                    name: title,
                    phones: number.isEmpty ? const [] : [number],
                    heroTag: 'call-${entry.timestamp}-$number'))),
            child: Icon(Icons.info_outline, size: 28, color: textColor(context)),
          ),
        ]),
      ),
    );
  }
}

// ---------------- Contacts ----------------
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});
  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  static const _rowH = 76.0;
  static const _headH = 44.0;
  static const _appBarH = 152.0; // approx. expanded SliverAppBar.large height
  final _scroll = ScrollController();
  List<Contact>? _all;
  String _q = '';
  bool _denied = false;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!await FlutterContacts.requestPermission()) {
      setState(() => _denied = true);
      return;
    }
    final list = (await FlutterContacts.getContacts(withProperties: true))
        .where((c) => contactName(c).isNotEmpty)
        .toList();
    list.sort((a, b) => contactName(a).toLowerCase().compareTo(contactName(b).toLowerCase()));
    setState(() {
      _denied = false;
      _all = list;
    });
  }

  String _sub(Contact c) {
    if (c.organizations.isEmpty) return '';
    final o = c.organizations.first;
    return o.title.isNotEmpty ? o.title : o.company;
  }

  Widget _row(Contact c) {
    final name = contactName(c);
    final sub = _sub(c);
    return Pressable(
      scale: .98,
      haptic: false,
      onTap: () => Navigator.push(
          context,
          miuiRoute(DetailPage(
            name: name,
            phones: [for (final p in c.phones) p.number],
            emails: [for (final e in c.emails) e.address],
            subtitle: sub.isEmpty ? null : sub,
            contact: c,
            heroTag: 'avatar-${c.id}',
          ))),
      child: SizedBox(
        height: _rowH,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: [
            Hero(tag: 'avatar-${c.id}', child: Avatar(name, size: 52)),
            const SizedBox(width: 18),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20)),
                if (sub.isNotEmpty)
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, color: kGrey)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _head(String t) => SizedBox(
        height: _headH,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 0, 0, 0),
          child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: t == '★'
                    ? const Icon(Icons.star, color: Color(0xFFFFB800), size: 18)
                    : Text(t, style: const TextStyle(fontSize: 16)),
              )),
        ),
      );

  void _jump(String letter, Map<String, double> offsets, List<String> letters) {
    if (!_scroll.hasClients) return;
    var i = letters.indexOf(letter);
    while (i < letters.length && !offsets.containsKey(letters[i])) {
      i++;
    }
    if (i >= letters.length) return;
    final target = _appBarH + offsets[letters[i]]!;
    _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final shown = (_all ?? [])
        .where((c) =>
            _q.isEmpty ||
            contactName(c).toLowerCase().contains(_q.toLowerCase()) ||
            c.phones.any((p) => p.number.contains(_q)))
        .toList();
    final groups = <String, List<Contact>>{};
    final starred = shown.where((c) => c.isStarred).toList();
    for (final c in shown) {
      final nm = contactName(c);
      final l = nm.characters.first.toUpperCase();
      groups.putIfAbsent(RegExp(r'[A-Z]').hasMatch(l) ? l : '#', () => []).add(c);
    }
    final keys = groups.keys.toList()..sort((a, b) => a == '#' ? 1 : (b == '#' ? -1 : a.compareTo(b)));

    final items = <Widget>[];
    final offsets = <String, double>{};
    var y = _searching ? 64.0 : 0.0;
    items.add(Padding(
      padding: const EdgeInsets.fromLTRB(26, 0, 16, 4),
      child: Text('${_all?.length ?? 0} contacts', style: const TextStyle(fontSize: 15, color: kGrey)),
    ));
    y += 28;
    if (starred.isNotEmpty) {
      offsets['★'] = y;
      items.add(_head('★'));
      y += _headH;
      for (final c in starred) {
        items.add(_row(c));
        y += _rowH;
      }
    }
    for (final k in keys) {
      offsets[k] = y;
      items.add(_head(k));
      y += _headH;
      for (final c in groups[k]!) {
        items.add(_row(c));
        y += _rowH;
      }
    }
    final letters = ['★', ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''), '#'];

    return Stack(children: [
      CustomScrollView(controller: _scroll, slivers: [
        bigHeader('Contacts', actions: [
          IconButton(
              icon: Icon(_searching ? Icons.close : Icons.search),
              onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _q = '';
                  })),
          IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                await FlutterContacts.openExternalInsert();
                _load();
              }),
        ]),
        if (_searching)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                    color: cardColor(context), borderRadius: BorderRadius.circular(22)),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: const InputDecoration(
                    hintText: 'Search contacts',
                    prefixIcon: Icon(Icons.search, size: 20, color: kGrey),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          ),
        if (_denied)
          SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                  child: FilledButton(
                      onPressed: _load, child: const Text('Allow contacts access'))))
        else if (_all == null)
          const SliverFillRemaining(
              hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
        else
          SliverList(delegate: SliverChildListDelegate(items)),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ]),
      if (_all != null && !_searching)
        Positioned(
          right: 2,
          top: 190,
          bottom: 90,
          child: LayoutBuilder(builder: (context, box) {
            final step = box.maxHeight / letters.length;
            void pick(double dy) {
              final i = (dy / step).floor().clamp(0, letters.length - 1);
              _jump(letters[i], offsets, letters);
            }
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => pick(d.localPosition.dy),
              onVerticalDragUpdate: (d) => pick(d.localPosition.dy),
              child: SizedBox(
                width: 26,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final l in letters)
                      Text(l == '★' ? '☆' : l, style: const TextStyle(fontSize: 11, color: kGrey)),
                  ],
                ),
              ),
            );
          }),
        ),
    ]);
  }
}

// ---------------- Detail (contact or call info) ----------------
class DetailPage extends StatefulWidget {
  final String name;
  final List<String> phones;
  final List<String> emails;
  final String? subtitle;
  final Contact? contact;
  final String heroTag;
  const DetailPage(
      {super.key,
      required this.name,
      this.phones = const [],
      this.emails = const [],
      this.subtitle,
      this.contact,
      required this.heroTag});
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late bool _starred = widget.contact?.isStarred ?? false;
  List<CallLogEntry> _logs = [];
  bool _all = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    if (widget.phones.isEmpty) return;
    try {
      if (!await Permission.phone.isGranted) return;
      final res = await CallLog.query(number: widget.phones.first);
      if (mounted) setState(() => _logs = res.toList());
    } catch (_) {}
  }

  Future<void> _toggleStar() async {
    final c = widget.contact;
    if (c == null) return;
    c.isStarred = !c.isStarred;
    setState(() => _starred = c.isStarred);
    try {
      await FlutterContacts.updateContact(c);
    } catch (_) {}
  }

  Widget _action(IconData i, String label, VoidCallback onTap) => Expanded(
        child: Pressable(
          onTap: onTap,
          scale: .93,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration:
                BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(24)),
            child: Column(children: [
              Icon(i, size: 28),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 15)),
            ]),
          ),
        ),
      );

  Widget _bottom(IconData i, String label, VoidCallback onTap, {bool on = false}) => Expanded(
        child: Pressable(
          onTap: onTap,
          scale: .9,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, size: 26, color: on ? const Color(0xFFFFB800) : null),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 13)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final first = widget.phones.isEmpty ? null : widget.phones.first;
    final logs = _all ? _logs : _logs.take(3).toList();
    return Scaffold(
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0),
      body: ListView(children: [
        Center(child: Hero(tag: widget.heroTag, child: Avatar(widget.name, size: 148))),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Center(
              child: Text(widget.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w500))),
        ),
        if (widget.subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
                child: Text(widget.subtitle!,
                    style: const TextStyle(fontSize: 17, color: kGrey))),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 16),
          child: Row(children: [
            _action(Icons.call, 'Call', () {
              if (first != null) placeCall(context, first);
            }),
            _action(Icons.message, 'Message', () {
              if (first != null) launchUrl(Uri(scheme: 'sms', path: first));
            }),
            if (widget.emails.isNotEmpty)
              _action(Icons.email, 'Email',
                  () => launchUrl(Uri(scheme: 'mailto', path: widget.emails.first))),
          ]),
        ),
        if (widget.phones.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration:
                BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(24)),
            child: Column(children: [
              for (var i = 0; i < widget.phones.length; i++)
                Pressable(
                  scale: .98,
                  haptic: false,
                  onTap: () => placeCall(context, widget.phones[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(children: [
                      SizedBox(width: 40, child: i == 0 ? const Icon(Icons.call_outlined) : null),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.phones[i], style: const TextStyle(fontSize: 20)),
                        const Text('Mobile', style: TextStyle(fontSize: 14, color: kGrey)),
                      ])),
                    ]),
                  ),
                ),
            ]),
          ),
        if (_logs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Call logs', style: TextStyle(fontSize: 16, color: kGrey)),
              if (_logs.length > 3)
                GestureDetector(
                    onTap: () => setState(() => _all = !_all),
                    child: Text(_all ? 'Show less' : 'View all',
                        style: const TextStyle(fontSize: 16, color: kGreen))),
            ]),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            decoration:
                BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(24)),
            child: Column(children: [
              for (final e in logs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(children: [
                    Icon(e.callType == CallType.outgoing ? Icons.north_west : Icons.south_east,
                        size: 18, color: e.callType == CallType.missed ? kMissed : kGrey),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Text(
                            e.timestamp == null
                                ? ''
                                : DateTime.fromMillisecondsSinceEpoch(e.timestamp!)
                                    .toString()
                                    .substring(0, 16)
                                    .replaceAll('-', '/'),
                            style: const TextStyle(fontSize: 18))),
                    Text(
                        '${e.callType == CallType.outgoing ? 'Outgoing' : (e.callType == CallType.missed ? 'Missed' : 'Incoming')} ${e.duration ?? 0} s',
                        style: const TextStyle(fontSize: 14, color: kGrey)),
                  ]),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 20),
      ]),
      bottomNavigationBar: SafeArea(
        child: Row(children: [
          if (widget.contact != null)
            _bottom(_starred ? Icons.star : Icons.star_border, 'Favorites', _toggleStar,
                on: _starred),
          if (widget.contact != null)
            _bottom(Icons.edit_outlined, 'Edit',
                () => FlutterContacts.openExternalEdit(widget.contact!.id)),
          if (widget.contact == null && first != null)
            _bottom(Icons.person_add_alt, 'Add contact', () async {
              await FlutterContacts.openExternalInsert(Contact(phones: [Phone(first)]));
            }),
        ]),
      ),
    );
  }
}

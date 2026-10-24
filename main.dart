import 'dart:convert';
import 'dart:typed_data';

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

final Map<String, Uint8List> _iconCache = {};

/// Icons cut from the Xiaomi dialer screenshots (white masks, tinted at draw time).
class XIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  const XIcon(this.name, {super.key, this.size = 24, this.color});
  @override
  Widget build(BuildContext context) {
    final b64 = kIconB64[name];
    if (b64 == null) return SizedBox(width: size, height: size);
    final bytes = _iconCache.putIfAbsent(name, () => base64Decode(b64));
    return Image.memory(bytes,
        width: size,
        height: size,
        color: color ?? textColor(context),
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true);
  }
}

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
  final Uint8List? photo;
  const Avatar(this.name, {super.key, this.size = 52, this.photo});
  @override
  Widget build(BuildContext context) {
    final c = _avatarColors[(name.isEmpty ? 0 : name.codeUnitAt(0)) % _avatarColors.length];
    if (photo != null && photo!.isNotEmpty) {
      return Material(
        type: MaterialType.transparency,
        child: ClipOval(
          child: Image.memory(photo!,
              width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
        ),
      );
    }
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
                      child: const Center(child: XIcon('dialpad', size: 34, color: Colors.white)),
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
              _NavItem('tab_call_off', 'tab_call', 'Calls', _tab == 0,
                  () => setState(() => _tab = 0)),
              _NavItem('tab_contacts', 'tab_contacts_on', 'Contacts', _tab == 1,
                  () => setState(() => _tab = 1)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String icon;
  final String iconOn;
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
              child: XIcon(selected ? iconOn : icon, color: c, size: 32),
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
                            ? const XIcon('voicemail', size: 22, color: kGrey)
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
                    child: XIcon('dialpad', size: 34, color: textColor(context))),
              ),
              Pressable(
                scale: .92,
                onTap: () => placeCall(context, number),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
                  child: const Center(child: XIcon('call', size: 44, color: Colors.white)),
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
                          child: const XIcon('backspace', size: 36, color: kGrey)),
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
            icon: const XIcon('kebab', size: 28),
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
            child: XIcon('info', size: 34, color: textColor(context)),
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
    final list = (await FlutterContacts.getContacts(withProperties: true, withThumbnail: true))
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
            Hero(tag: 'avatar-${c.id}', child: Avatar(name, size: 52, photo: c.thumbnail)),
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
              icon: XIcon(_searching ? 'close' : 'search', size: 28),
              onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _q = '';
                  })),
          IconButton(
              icon: const XIcon('plus', size: 30),
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
                    prefixIcon: Padding(padding: EdgeInsets.all(12), child: XIcon('search', size: 20, color: kGrey)),
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
  Uint8List? _photo;
  List<CallLogEntry> _logs = [];
  bool _all = false;

  @override
  void initState() {
    super.initState();
    _photo = widget.contact?.thumbnail;
    _loadLogs();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final c = widget.contact;
    if (c == null) return;
    try {
      final full = await FlutterContacts.getContact(c.id,
          withProperties: false, withThumbnail: false, withPhoto: true);
      if (full?.photo != null && mounted) setState(() => _photo = full!.photo);
    } catch (_) {}
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

  Widget _action(String i, String label, VoidCallback onTap) => Expanded(
        child: Pressable(
          onTap: onTap,
          scale: .93,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration:
                BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(24)),
            child: Column(children: [
              XIcon(i, size: 32),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 15)),
            ]),
          ),
        ),
      );

  Widget _bottom(String i, String label, VoidCallback onTap, {bool on = false}) => Expanded(
        child: Pressable(
          onTap: onTap,
          scale: .9,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              on ? const Icon(Icons.star, size: 30, color: Color(0xFFFFB800)) : XIcon(i, size: 32),
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
          leading: IconButton(
              icon: const XIcon('back', size: 30),
              onPressed: () => Navigator.maybePop(context)),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0),
      body: ListView(children: [
        Center(child: Hero(tag: widget.heroTag, child: Avatar(widget.name, size: 148, photo: _photo))),
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
            _action('call_dark', 'Call', () {
              if (first != null) placeCall(context, first);
            }),
            _action('message', 'Message', () {
              if (first != null) launchUrl(Uri(scheme: 'sms', path: first));
            }),
            if (widget.emails.isNotEmpty)
              _action('mail', 'Email',
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
                      SizedBox(width: 40, child: i == 0 ? const XIcon('phone_small', size: 28) : null),
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
            _bottom('star', 'Favorites', _toggleStar,
                on: _starred),
          if (widget.contact != null)
            _bottom('edit', 'Edit',
                () => FlutterContacts.openExternalEdit(widget.contact!.id)),
          if (widget.contact == null && first != null)
            _bottom('person', 'Add contact', () async {
              await FlutterContacts.openExternalInsert(Contact(phones: [Phone(first)]));
            }),
        ]),
      ),
    );
  }
}

// Icon masks (base64 PNG), cut from the provided Xiaomi dialer screenshots.
const Map<String, String> kIconB64 = {
  'dialpad': 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAFR0lEQVR42u2bIZbjOBCGv55tEli0oehC04W+Qq4wdK+w55grNA00DRQNFA0sarYLUpZlJ7Llbvds5z0FzJt2l+X65WpV1Sfl5V+e+/ODKqAKqAKqgCrgE5/XYkuhwSFAwBMK7mhwOMTsddXe0SAIoHRFT9ggQGhocTiUgODxq+43JjkAQlhxyUV7MblFEl6KMrGjpaVB7OeAp6NbmNWWo83nzR3F82vBpdQelEDH++okFb+Bhp8IgqKAS0Ijb9+CuSI4QBYCr6HlGKXe3rcAQrfHH7GL0Y85pQhN8kbm4XakRaMzRKeabHg29j+x8RVHY5Owg4Bx4PSqywpw0W3MZnhzeftx9PRN7xJCkjgqmev39pK8L+zKLQxz9jp5ipatLtvygHxiwdZP/v4TAnQ2N+MVXbDXaCVJGGnGfrxDt01WSQiFGARpXGs2OenkjlR2yNj7uP6X2G8WoATCLPoVn80DSofQIuhk7colv5uAZvY3FehK8sAf/6zb9EkA9PT0BDwnvP0mF8+9/dtzxeMXygPlQG/3HYArgY6Oc/YJmwTAFaU3l3quXDhxWhi8tzt6u/tMx4nLSpgqBw5WRJzK3C8tJcZsMOSD9eJMknygRcWcJBknlBZzL5VKVAFVQBVQBfxOAbKxIpUPVLCb7njdYOusB9NCKjHah8JENjSSAV9aXpdTidaowdDSrz2ioaXFxTJuDZQ0xj3GQs6XOFaWiRtaozxj/fi+QCXEnHdJYbxEJSShHmJlo+e95D1soRIkzUZjZXMOkvy0uVdzqlmkEi5SCYwiOROyE5W4b99lRiruEZXMejFoF6iE3PVvgsvYbxYwVqFj/S4LVIIZhBmpRFNAMVilGB/CKvOOVlepRDnHkMl13bag/via1TkjSgvGlwkS251K6ITchAL7kQrN0VgeAmxIgCUCRmIpM/c126SHB/MasoLnI4lh/LCXgJDMndo1v9Cie3wkEiNJ8gtY5X4yQlkqK2vqB8ZwsLY7WNudpxKDtXCg50rgvEglMC5xiKF25sRlPZGVUglPzwHhzZw5Le4O9Fy4cuANAS6cOa1SiQs94DjQc6HjnXNJPVTe1IsVZ6GYGQzF3DQEl58wcOriYm4bldhAjX/Xp2KVKqAKqAKqgE9xjC1nJVzsDEqphLPGMhSelXAbT2NsEOBim662vfS+ckdrIEAilfArTzjSRgGFBw1Ka6GGv/mLP62YA+ENIWSLOceRIw1vcQ94PMKRf0KDxPGFN3orCnd4Ay3HWLkLxD3FLuvOMVY1ihRRiTYClduVG5/YiUrcHzWQWKo9pgzNXZe7dlZivgOdt/9gU5+6o8l+Vgll0Mje8vZpy6T2hB0F6KwgLqES+oBiyILgkVBI+YJa1tRvoQuP7kpndhkCTBmF7rOM6mTHffnBUxIx7SPyTc3jJ5Q0QRupROpQWBDweL0Ji039veQdqcRIDQYpA3nIUwnueGdYOCuRCtDJKLsksn6CANXOSpwXqcSQ8A4cuFru1uz4PQL0vHGIVOLdGv1dWspxg8MTipjNuMFxs/arxy5bywdq9jtucIzF1vxY0p7FnEQeXWb/m5p6+VqOUalEFVAFVAFVwKc+r182ckoxQtkh1u8kwMVvfBBLD/88AgYIIxEBDF9eeRIBDUfrZ0fGIOWw6v/+I3bWvs93NtuSJv07CJAHGEAtsJ5kGc1TBXkOAZoRpc/xBvTBz1LOGb6DAJ98YWJEWuFZViGloyP9BtkGyvA98oDnFxoz8a2UeKpMDB4lJFQifE0a+8piLiRhFL4m/mtTXwVUAVVAFVAF/Ac8qnT2VS4r3QAAAABJRU5ErkJggg==',
  'tab_call': 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAFE0lEQVR42u2cO5bjKhCGf/s6IaxUIemEpB06veHdz93PbEFb0BZIHVZKNhNQIDRGD2TL0GdEn9M97rY99VHvEvLlF773uuIEOAFOgBPgBHhh3Vb+TrjDgAAQCIAFw2KABbcBcPk1LzpByxfJbxgARwTbMoCGgYGBzv6VYdGjbwFhzoQ07jCy9xzFRtSF/zlgaBPAiPD8ZOmcPCfoojkAjTvuEYBmPSQA2bYACAZ3mMRwaMYPSJ7FNSPSLeu+9z9sPic+QNAwEpMaSmQ6MY61xQKhWwTYIn7QQ1MA2AwQgHUB9AcAKBs0l4oNHWNSY8Ucb0CgaETUHsAWLTAYDI17LT+4zrhmmUdUjETPAGOhTBttm0CxbmogkdmFAiJnXFQctw4G4KJmhXYG34N9YE+/xS1pwG6yfkq+V2sxc2HUN4wogKjYJV9nGsaxEt2SygJyM4nMxjqfN+y/L6i5LYDtBsF1AW6LJcJyT0Zx9/t6Pdl1FsBOEOb3f6g7XpkDsOgxLLQ3JE3/gKGe+SyZkBUhlzIso0dfV/ylctouunKYzQ0tzoXShEYy2uWJ+bDY/lB/uHhdAUh1wEl6a2Y2utyR+YlPrqTgVgbs15UkZSfhdBr/m1hrFzgsegmZja61pp6jrVObEOtTCYv+yYwagtlykW/MCDTJxE2sf/5ff46DgoJCB0ABUHBgAA6P7wEAMBwUNDo4AA6AknTG3wPAgaGgoaHgpMBWUGA84L4DgDcjL7R/5LWgBO4bAHihCZ0IDTEjVzullQCwBFA3CaaPup6wHSDogGSY6GJEcjU9oQQAYAmoJD4AeVzRjMoAEBMaiUaU+MWjVk4oBQAektQ6KAEI8YhrGFI5gF+dNPUuFhYKXANhDwCLDlT0hFDcuc8j7NOAS1obNUlsH0e47XoVx8MFOrkgZUQPffsAUwSK7T7hDgIKZ0XhMu14paHgNNhtN3pA8KltRCjVgj9cMl5ptrAl8769USh1WQLQSXWE6N5bfEHL0Z6ggZAmCR00OnRYvT7xCsCI0IEEARFhvU71B6sMdHR/H4hJSvcf6CQ4HwaQakFNxi5hL+d30J/KM7LP06FNJ+84hmd3FIBHeMBJy+nndwoQE1Cw2f/c4F984WtSniOaoYv/6vBj2SBvb4hkjAEs50zDb/wjBsFmHNqI8dDM0CzVU1gzTv26BjDZ9+DAFIttSNuTE98bB8NJYZgzluDWlPeGdwGEGUUHikK42P6rpPj+whfu0BJhODEgl/jRtBsPnWDGHG/vkj/mBSOux3JU2WdoE/cvhMzxNBKtvG84TsI5c3wfQJjiMTQMwklrL55JRBnFKlsEgwH6zxz9XgDvzmaih1Ho0sNs0+eFo+iHAoRahpPaJhQZ+/f/+cz2oQDh0ivifQfj1QQuHgrT2vmxIwAAxk8McoDfRIeml96RPqeBoIUw09aJJvaLz5/UQOrSHKtNTgxiOw4tnxc4EiAgWPz3gvmk4mdy8bEAPir57zqplniHOVH+VccD+B6rl+YlDCbL8gAlFVcFgNQf7KT/5QIPQL5X/hRA0ISVU74mMaY1hHH3uS6Ar+otLAw4SXNYLTFIhLf1TAgTQ/CHGExiTrzhVdmjJZ8HCIW3lrKPYnG9Jn62J7tUvKfedwo6BliavV/Kn0zK3mp0qf6hAF50HW++e149fs4f7bk08qkGQRM6me6xfC1O6S5NfSwDTW4pCsIvrsv5uRInwAlwApwAfzXAb6BzHh2fOvYBAAAAAElFTkSuQmCC',
  'tab_call_off': 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAFcklEQVR42u2cu3LjOgyG/+y6UYlWJVqXal36wc5DnVKvoNYlW5do1e0WBElQVzuJQ3pW8jjjcZyEH3EHqHz8wXtfv3AAHAAHwAFwAHzhOj34OTKv5d0AGGQABIBAasE47e484wrW16IADg5DHQinzaUTGIwu7n8AIBAIA1zNAIwOnS6VjOYTROEIfXmE0wPLXzJl0ucAV1aVPv4sL/+qy9/2SA4Degy1ScBrPutSrddJEvEG3QGQsjJYBggLJd1n//C63ylckBWjK+mR1gHC8gUOAwYIRPfdL9zKy9UFwMbviGq5KIwHuSqmh/IIFUrAa/40ZDkQBgBdtAzOZFNBMpcnDvOFBZuYmnzVyRyyZG4wzpTK2sFeOk2rCD6RoOiLuB4VkkyZeBXBGUAGr8AWAZBFe5h/SiIw1QlAs2xoKqkUo1GTCtlF0YZ2V1AR/NpZ1roMZMfQiwI4dYp+aZ0pabBiHcWKzHUVEhOoupkaUUzqKEOuJA64LLfhmZMkdFoxFC/yTxtOMmk4a+q2vPy1lKOgBHyRIpMSh0y5GaRSWIHWUwmJRYxddDJpMv7HlQT4/d8aAKEB9NmgwQjBHS0uYDAaQL/r0JdssKxno071nmLRwrFTZL3VMDH5agDEIATTnYatQR+oFYC1aLSZKcVaWcoqz35B4xEQY7LNisTUBNXlQlNflCcPNClpUK8EvCHzJLkLkdeV1f1HS8rg4yUzYCnreZ4p6gW9hi9Eh+pqGnDsz8hEO9C0W2RWCuB70Kk+yJu8bwEQjDaV8MV6EJ8HCDKQhey06LWWzOXXaLRfNJEDxho80WMAgGBEEwNZ2Pubor0BgFeeRqUwAiCMkPIyeBwgLNu/GrVG8I+3AZC4WA/ToIHg/i4AHiEtvkWr71U25NtzqKlT4Wtlf/ig6jgw71jAFPa+yfImErBNl7z5W8gjPWcDyYAb1f8x9i6Aewl/9BmA1I8bTetlzL5TOUBKLoBGPVPqHlVvA8EbCdJQPMwRfrzUOX36J8MIPOWlrJVb/8Rv8W36aZv4iYL19AV4iTP8JAeOseKRxRO6OD5xWrSmhpo8YlOftQHEnMhnqQzCiFExmofM+YIrOrRoTKe10ZTxrB1Y2fNspy+qoOjO8UQp+l1b4DhjsA0bW3P7371zlOdrEghSIBAa3HX/ziqNLSkQLrigzd5rJg8ytcgLAUI4G3URhFbdK1adKuOMs35uz05yx/0SgNBoHxUg7KUHuq/s/tmEQsENNzhIzHcbkD4bMNp1OXwPABTA/0kxCwgSynf/gisYIwQNRtxxw//oMeCGO+64q/xa/UpoNUSO32/EU3NGrJqTYVNmDWlYFd4PR9p8D8o7V4kj3HQeZnGM9X0ACYFjQ5g0uKUTv/nJx9CwGbIw5qMC64FCmEbOgmf7ToC5FJZOWiTfQhpzp216wRADWfp5P9rqXwuQEEj3HWZItdzvW54ypFwr9cUZ9HqAFNpg0rzly+0MSRxCV5wU4MU2kO8exfPXS3UCYUCPfidah7xoYyNeARB2z0XtxSLG/ogqTOmwfqzzVQD+z/uMiCdnLQJKBzw84Ze1SuOVAB7BoYv3gEwrATyBgBIAiIrEpmaA8e1QZyormRDHckdKAUAHVN3CsakQnMJ5l6lN2I5TARuYazDHm1fmmb+Di+HLJh0pEVnsPP0MQLCHcGSEZ/fmeLDOKArpjFrMaL0oQIoQyTPlJx9Js6B8jChGQsUBgkUsH5fN461VsI0zYT8PEJShAzbuksLsHoahHgCbbtgbjkjPASCrBELC50p6oTUExByfZoWPbZ9tJB0fFfxXA46VA2d+aTvhrggg7yhhcsfOztzh4/i/EgfAAXAAHAD/NMBfIgts4fYLSyMAAAAASUVORK5CYII=',
  'tab_contacts': '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',
  'tab_contacts_on': 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAEb0lEQVR42u1c7ZGsIBDs3TKBSYEUSMEUXpSXgimYAil0CPd+AIofKCC6bp1uXd3VHeL0fDHT4L1+8d3XGw+AB8AD4AHwADhwNQX3aCgIBApEhx6MjlIQAAY9zOoogYaGgAAMDPprAAAC5QCoyEMtQCscITszEYSKKOIEAMppV4EwEQgKChraicVVCwgUFFoICAMDc34MiNOt/YyaXhvjHcj/jAiAcb71UYcsEIo6NTqcZgV6AQETYQiBQG+4z6iIFhzmtdHDPbu8freDVS0AwAHA8AhuWMpC4Oqoqf3GMRzmoAttUwJA4x90JPzC33LH5TARislzjeANftDlupBCi9Zph7txkRI9EoUQm0vclwLBWIptonmmTRQt72L2WIGgjUfDO6IJDZX0OAaffZFZCEPFM1SzsQyZzKWFq64gUf9OmU9cRlKxe5rNjM8E3z7vSpr7qUYfAH8GAL8dgDwd2a6JJaIvcRXm7WMgXI0Z/IbfYYFQ35yILq72/xIAGBp0BuWYBs6B0FTPEgY9OphJJSUwMGhde8Q7AqATzaDHz6J2pyNWWujaEJqK+rdtRxdpPTh0VaomhJouZNCj3yCnLARZ6bJvkEbHFpybjuZbdLkngH6XnDIRHuMWC1mKaCxl4K6pRpk4Ru7mQsxu1W9mAcnoj+WOAM5xtosBpOX3yqtAXQukEOQbDM9nAdg9Fr0LIGXMB0oJDkXzBg07iC81Y6CpJD4HARndlFBDQX3bnnjcZeGK77f19V+/I7N7Ohp9UNh54fVQdN/MAhK4kThqXgVlm9+vDHfWbgCAURKdADR0IKzMQN7AAtzoyuagKnt9PRfibIUNSRVMGCEJ7CAzwuVDACQQLnQeujTKWVxIsArL5M6DEVEniGU40OE34zhZ4ry4fj9eu41vHg/q5lDu8d+NYyPWO+JptyDu/IQKQvtjFrAgvPAmMXJ6GPTQw8rwQQDW3zt0mX0u0blV4jCE5qD4lgkqadONIyBtdSpXAuCQP7ooD5cGwTiO6IAV3sWeT3QrLGiJHfoj4fwudp9S15lf4zxylQtJQBGiCoQO4ykk5rEYpS5ksjPPnhsVLmfvbNfxD61Zno1rCK+JAVZuS7ihEN6T2Ip11hdZ4DwIl6XR2ueEihm797WPi1IBxfO9CzTvG3Wppv3xCPhlLqTclmkN8Vu00KUx0BQGmyVPfEVZemnXncmszbykJxZ3KDXeiaU4zgHd1+mJrSuZoR9mQgz5zliVnVevS6uI0yAHMpG7wnvxl0V0Ae3VHA5BX5/K7AQvV4TH4q0DThok5DNGRwEw0GzY7GDGC03T8PQYlES5JuwzR7X2B7CgrDjR+GkrfM39gWU2IfKYUbk+Cy0LMTmxYjrVAkuHuuRqKpW380qGQXY6Uk7v3l1zozstLkrVxXwLpL1bJynJbvE3JutatjNZk4D3jEMc+Y6VZQH/YuZHDtCswu1zAXS1t0MPZDWZEC+zK/YinJy7NZdtgWjP8Xr+r8QD4AHwAHgA/GkA/wH0KLJ1Yiek7AAAAABJRU5ErkJggg==',
  'voicemail': 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAD8ElEQVR42u2bO2/bMBCAv6ReNN7qkatHrh2z9j/1h2XNqNUjV49ctaWD+JJNUpTTFi1wNBAkkHzkd3e8F5CXT/7v9YoCKIACKIACKIACKIACKIACKIACKIACKIACKIACKIACKMDfXqehtywWi0HCZ10Ox4xjZn56f4PlLcjOa5X8zoz/OoAgmHR4IAldn4APn6OrlAx+Iz3Kdri+kJfP/hYGwWIw4aikrST87fC48PGHdJ8/W8WssqPcuS/3tHN8i8EmHflCWNScQfA43sOm465jC+2XVpTCWQVh7rlSH8AmzftwfBc0Jbi0UXyXQYSoGFMc3hVOGGXHd+m50qmrIxP0G7dYj+eDkVeA6MUmfG8eOP4bdmNTF34vb0eWbhBmqCOcdrQkhSeWXuqDXrKblajs2NViw7vzg+R8CwRbuBP1QPHtZ32bCz+wTHgcM1ccnuXhrSU51xRcaWGpvpkPdsHyhgS5c1PygmcChDNnJhZu3EYtEK9YjPM9nfoUJ0wKq3PHriaEx5n33SA5F5faYGrWfe1cXymcp798ihRShMWWY0qw64jkmZn3ILlMol2AeC190O7I8iEPxOTUyyvsR/e7rBwtXJH8Ws2PEgCOpKa4TUNTG+v4/Qz7oBo2sW4HYPW3YwD57TZAfOKeVI0ZcaFSS0dKgy1A24GaAXEH4ZAFcobkEEKZTVvHl0MOxKZYHLrEMQcetQCFZusOlH8+J1fGAeTLfYbsQv6jHZkvKqX68z/eUvqewYaalPr9uS+Xf4/U3wwgXR/vXsYdqc3o1QM4qqccJGsI/k418mct8KyecqvZu8DtYqNXgAwD5KrmCIIUFVQ90sQnxyUftkCneOq2n3LX3bZtO+6eOxXUqbqNFAhjfe7aQZAmFO1yI7aLdrd3y/2b2RR1Ax3ZxIQwsQATC0unx1p7pu9YzizcuHLtHmzinFxt7b32jv+dCc+VD26jACvChCCpWfTNw1+wWM5M4fi3psWWoBiDsATpLYhSMlyD5MGeeEkizmGTeqcrGC5cuAT/v+Fw3LpapZAqTEz4CkKUvN6sGzMfdbmnZgGby9c8mym9WVIXvJ2tSbUS9eE7+algkqXcJndIKupNMRdp3MRTpwafIWjAbLz2PnVJGjuau4OVpV0OoCbkC0ktqL8rxaWIUy70z/6Z2agJQyhT3AJfmd/kQs1Xirbt0JaHhOfvvluOkdehZaczf/kcGQPaaurx3WK6hiBNvLq0OBVxz06ns6OYYg7aKpG/3kVs7edbsf8oAJusLA+D8LH2xg8D+OK33ST6ov8AoQAKoAAKoAAKoAAKoAAKoAAKoAAKoAAKoAAKoAAKoAAKcHT9AoCq6TXWiohKAAAAAElFTkSuQmCC',
  'call': 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAFEklEQVR42u2cLZuzOBSG73YxkcciY1+JHYmtHPvK/R37f2pXYkdiV8ZWxuJ2BUkILRRoyyRzbZlrRFtazpPznM8cOPzLzz6OvAG8AbwBvAG8ATxxFItnaDQVGkEAsBgMhhb7EwD0wusAwDoYAhhMegCHu5G4po6E9xrwfy0tTb4aEGpqqpHwfu17XWgES5snAC++Hgk/PkOoAUlrDXMAPh15pkXHkUlTIwjn3AAIFdXidwXQgEHS6eA46zplhjq3MPTKM78NQE8MZtl/bQmaeoZsSQBoKud71q6rdsaeDQBNtYHV4ixG8qGQbBLGOh3U+QCw2FX8z4JGx0nxzY3Pz9YX3QIwmBH/ZVH0wRtJHhq4hrDGjLfbzq42YIJ5boGh8wFgNwpv3fon0MF0KmE2Q4ihZAHAbKSPt51MkrlHhNlq+jt3JewmGlkXPTIC0G4Ux9CmKfGLWQDeLcoqw205pylqjnc5bVYSqE1XFxd3xVpOECxgOKfrTdwD0CALGWZvug1NuhbXcYEaS4K1nFOKv9Tc7TugY3dqr1b/nLa1dVygiA9PdhLemSZ1i/e4wsPYibTBu87k7d0lACaENJtL6NquAZ9U2NnCM2MAgw5s6sT5UQBEuzGZCL0ukMW+noldgqQd0W0agDZkOwOVMoHwx1/rzrsAJYICOgA6t0/W5U8h7430aM2FCjCpd8nWagAsCqFERRAkVR32CADfxi2d8J5Mio7LzwDQcUEoAeX00KEQoKNLZQtbAPSCqmDMoACFIFxSaaHYeL6PCRLZQcKmyiPDHibKjWyICGt2NTOgkOc9gUSdsweF0KVI74oHvtMXMZ/oMPpBiBBN/hrwcVkhkTcaPJP9Xn/0GIA+hVCUgUSKDtxr8xMAeAiDO+2cQ31MC0KJpqTcGlGKJ8C3CIQdYj+CU7vP7AbhdZRnbZwGewaA5XwTFUDziSCr+xWaz9FkgMXQ0q5tbBZPUrAdhTMPop+1WIagqcMuv9ejddMXNqpCdrEBr4WL476KUj7lxOnuXr7ixIk68mY4V1Ci+YV2tmX3BNBfoIsg9B5JhZxpjgg1Jz6ckIQMV0Wvcb9R3gPxPIA+pejcmg9xwXe2u0mfVPHBR1QgyUhwwlKIW5rZ3aJXAPAQeuIoV276hEPcp2Pun6iD+FPCE2W7mpJurnh9DYDed3TOmAdtKLeKcIkuX/GbE7+c2Pd3H8TV4n0qb/cD0Jc7FxQlpQtlnaNS/15vmjpwX4KerEsQ5zRAWIYJIhW87rA0TE1M9ANR5mY/Xzb8sm8h3EB4nQaG0j9Ouz2VSgRxPkVdsb4Lxs+sLagA5J99AXShT6EisSTEBjVhsmpBfCL33PG1H4V8ktd3ris38z4m03PHxJ7d6wEMLfnhcvZFTciJaZg9AHgQOD3sOoRT7PbLloaGij/vjpAnLGjWFp8XFw/UrLdf7yAMF/7+Lg0MCbfFUAP6gXHOhBQa+yWwzis9Y9A7R+L79tBSUYex8q2+yUb/CQDEd95U4caKbeLPjD7sbcTXRuhLxHXR10b1heWLhq/rpLrgew9Lg6V1elif1Pm7124odEhyQ7RGqFxJI7Nphh05gpmxkiKF/BhnFf4OQVnwTsZ1KMgFgHeubbh94np430Z6sS6qkxeAwav37NYu4ZCrz734M0X9IZuHAsjotlOhH/1sl/Z+Dpk91UBHEwBmzfDtIcPHMvhG46re6OH9XIk3gDeAN4A3gP81gP8AwJ3YE+gmXvYAAAAASUVORK5CYII=',
  'backspace': 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAE20lEQVR42u2bLZLjSBCFv/aKGCZtWLRhXUF0oK+w59hzzBVMG+oKog1FDZOazYJKlWRbP6UfK2IiSmhmYiTlq3wv82Wq++MPf/d1IgPIADKADCADyAAygAwgA8gAMoAMIAPIAFZdxaa7BUHeHmODvgOAIDjcIQCacRDrAZR43CEZUGqUhppmPwCekgsynd6dLqEElN9DAE6rHugpcegBwT++dYCwazLgKPGW3GMyIAiKw1M/v28dAI8D1AT27suZ1gZrXrFKvGIn01BTvx1Ae1yCez2uYvFpXIz9zihUH0ChJp68bgPgI/sBaq4HhN8FLVv7gKOkNFGF8KtD6pA8yHk1AGetq+2O9UHhd2HLUBZOyQ/xFr4ADdVh4TNFoFQAQklpp68Wfr3uhSOn+2Y7HTqvAIpSJ4Xfl/t0UdgEoUhif2fbmjFT9aKXCzVMAnV4PCBb6Fgksj80c+z8NVEvzQQEZ7RU/JZuUiTTR1Hjv87e0cq9tII7rqowVQi/ZyHoukbmLZwQfAp9WqggvaqlA+H7RMHr2gwEKpQWEmiCeNvxA7w5SPiXiusLebyFJlRbOvpptnVJDCv9NcHkqbWeVqyP4bfPvW4zJEWCeEPxrBa9pqbq1Xhv1lttLHFWEnbwU8Vk62pDaBa/RqnMCIf65RFqy4frmfG0Y1mxlfBcou/RJw6n0uiKcjGuOxxlLxBFrKO/ZS/UNw66eupSKqtERDum8W/1QlIuAOB74UO9YeoKEDolPeanSj4YWQKgP/0L9UbbHIhUxpmqsyPVPtP0aYA+rfBkl71D2KppXMKoldn08GUZgOfZfw/XL0/EWrZRWtiJK4g5wBhcbwjdWdOS3gF56wE7QCgGUl6ZDkL5u0x6ytRBqHOzxKWwvK6p9hBxEF43g4p5oeWSc70thpiaOoK2TlW3aaCYqB1dNfImxKULqQsOF8Vb01huNfYHtrayYrR2hCYUapGjhIWVo+RinkdQm6I1ZjX04mBWru8AEEqdi54+vCq1dofwfaw5YYfUeaTSgAU5b9ru/fPfVAW/8Ylw5pMzAHdu3BO4/4tfuHhPxTd1vE9puHPmK44+Z+7cJp73xZdp54cbP0smsnA2ZSyIJSQk3PXUE2boasCpStxw+8kiIdNCPs16mSYKuJ0QUrc945YtaKIxMcvMlzaZ6gRzM7HaYOKiTypnvVFDHYvvmJNqtdCZjZWdeEoD7e03PvkCzihnvoBmUgnKjRtnfvjmZ5QaIat3bnxTTWjgbhq4D3uolMVWW1Jd/NDTzDSgJg6Wzcxz3Wwzk+2bOahQLrGLBjFXM6D7QKacqmyzi6nr9dATvNXvkvmvY6lNb6PbTf/M2taN1k92M/ORl6wHoDZaBvE521ocHbSuBxBE9wjBHxD+jIlc9qW+5kpzOITJn4pZ+pm1ijvn0NZ0JL26I3FcbxzSrQBC+bxYe3dcHtZV7wHQFu/BnlCs4GSNswf2B5O9IXQzdBM3JLtkoFsaDgcqu+0y+iJubBW5C4BQj3jaNiw7XV30fwOIash0rP2Bp3bjRtw0TNHoOWB9+pfprIV1wMjHrY8/W1j6+iNnspggQ/dobxHT7jNGRp6P3X6TT17+pBt43z+YyVb2kX8VMQPIADKADCADyAAygAwgA8gAMoAMIAPIAP7O63+kffG5zUoQdAAAAABJRU5ErkJggg==',
  'kebab': 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAACmElEQVR42u2b4Y3zIAyG30ZZwCt4BVbICjdlV8gKrMAKHuG7HyEQklzv9J1dgc7kR6UgtTzYGPuFPv5h7DbBARzAARzAAX7RZqPvDSAwCAQBIEhISBY/9DDYyAiMAAYDBUCQsFogzAbDX7CAEUDl3QZAeOojWAAELODTu82ZEgTSOwCDi+NUAEBAYDCSLsKkvnj55Dr1k0+9XVqgHSKd3AiIEN11MKk7EH0Tn5QtMBks4rv5ryuiewDBW5tlKiG31pG+AeQb15LeASLirbdT7lXPiCwA0gVhc52I9YDX6T4gSIh5z20dawNI/acSgpgTCi6LVjJY1I9RDxNdqCbUVKwS9RewHUBN6qiUM0b7w8OVOQdwAAdwAAdwAAf4wwCz6beTfZk/mw29akBSnkEAuDy1yNlrggEACNzI61JKTWjLihYAWy0WDsUMFbssEEAbYVZ3n1AE3tbrCSHbI/UMUCvhFoAAMIDQu7BV1We5hNM9Ng0QRr9Wokn7pybD4d+/6/yE5s3i+vvUabJCtLAAfZkDkb4F9AEkb15yM9zUv7gbc6ynm+ELon4+ZCOvcz6bb2c/4qmvT1too+GwH9dTsYQV6xjyOpVqgJqVEceS16mJRjKqvE7WW5ufDziAAziAAziAAzhAR/XAsbXq9GAAdNCn98sew8jr7WWbWg3EcW6vfxxmf9ciEp5j3F5nLFhO9TABWZte+5fX+VAHS1PUMD76l9ePnl+Vir0vIIxw+Zt+UCd3DTD0Tvx6hmtM6j6VkP/o6QJASuR51dsxQHo596J/UjyrA5yj/xFgEHk95XBJl+HH/gHq7fVrPBoCYBvmdsjBF7Bhbq9zrgeoXDlIVhfArcRdOvwJQrJVTJqr0w7gAA7gAH8b4BMvuvbVubKj+wAAAABJRU5ErkJggg==',
  'info': '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',
  'search': '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',
  'close': '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',
  'plus': 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAACG0lEQVR42u2c63GDMBCENxka2BbUAi247LTgFq6FKyH5gcCAITxswRxe8QcPHuk+9h5Cwv76Rez2DQEIQAACEMAnA1TFeq5RI4EAAIfBcIfHAWDv8O6zR1KASKizAgYCuMdyISKBGSDBunMF8TEAjA7QILBDYTyAoRIeFeASlZjRATQXEoAABCAAAQhAAJ8IwCMmdFLgygA+cy4FzgAIGcQ84qHymBjw2C7kV4iBcFnIJ0z2SADsrUazZChXM4Onl1yFSL0ePPd4exGhUdXWANzy1oTvBmC3vdS0lDc8trpTvw+DwZcBmoH6ABwMy3+Nb7/BjDHtVHMI4+t8uurLLsSeC3FTPeUi4vME22f75uSttTUx8Eq4cdEU3zgSB3pwXRCXLP77cJiTga9Po0Xr5/smhdWE4QaDvYjAyaAc9+mbzG3tWgHwA+zalvZBGuAoP7XHtlvDXhWwNVkI+e6zK0LbAJqyVQNIvczU6rpHWQ5uwaosZNlwn8kInEyADydJo7zfDH3Pb0v4YrrdEJXVhsnYo4slTzYQNpqOOGz0ssFb0kSpydyzt3qs2ehhyfi4VQlGBfCyWmhd6NwIkALnBK4UEIAAlEblQoEAiq6MqpCdj6AYOM95pMDqEsadew1SQA/13UqoK4hPBAi8rOK41MpcoVYVDWDrKoCV0qIqaj4Gv6X0eAq0Jtv07so72pf+lkEAAhCAAAQQuf0BJT6fNxf4GMUAAAAASUVORK5CYII=',
  'back': 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAADmElEQVR42u2bPXLbMBBGnxM1KLdliTYlr4Ar8Ao+R86RK+gKvALblGhVomXnFFhSkEQ7JGWB5AwwY81YY3H2Yb/9g+C3D469flAACkABKAAFoAAUgAJQAApAASgAzy6hxh4XQKipsUhugNM3me9w1HRAe0QAxzsOAE/AE44koWH3ASwOlzcSngeocVgCgQDY3KH8nISsmi9A0NesAnoOQGhwiGYeQehoaemOAlDjcKDiAY+nozuKB4ZwDSoedP+zmr8+iB0Oh4y7H80/5zYf3j7Wat+O2o/i2cT8dRJyNGOqHDLPOb941knoPvNAoKPNHbrrAWocNUIA/Ynm+63a6SUxIEnoxhXwtHR5M//aGBAaGmrdeUEIdNtpf6mEhpbtXvsbmz/fAw3NmPV3ZP48ABlbtsHcmPfb7UJ3GUB9k/cFv3XmWQIg1DSj9q+ZZwfimQMQy1Y9imcnmWc+gKPRhhl97fiTe2xfD3Bbc4fQ7eAIAILVUT0k6u+263mWAYiOK0PTFhD83bQrI9bjp1+1wlwAxzt18ueC18nLJmcO8tlDX7Z8MkB9CjCI5zptDTnIAvXDDucDCHT4+xg8TZStOkmcjM2b/UQg4aWiedyq/wLYcVi8V7xMmprvOFfGmPyyG72qTPRDjMPLlGDCoy5f7oUvPeARfNI2czN/ycMjQhIl2c2fBkCjgLs4CJlzzqNU/WMDeZqg9LTYmzQ6vB827EAFpjrg06SjWqC5CWaL1wdsWYlnF7JbBNHs5O9ktYv18/f0+z0XDCBU9Ikbey7J77vuRgMtQXPvUImHaTgcASDmI4GkLg/VuDvKQOM5ExBtq0XrdPTCzmMgjQWACgP0mKQ290cAgJ6OQMUvDD09YLCYTWvCIoChvRDNSiQt1Q68MA8gmmqoqOhHP1R78MJ8gKA7b0DNN3vwwlwACFy4IFhETRYs1dalbclXTHGsF71WwJhU2fKga74HrlIyY4PRYzAIPX+PAhAFYwGj6jcIcNHQ3j0AmoWMVmYDGHqEfptwXg4wTMGxMlxzUjyG6fccxLdtXjwAkxEmlrjs4bz2rkSczOpkUrK8IzoK7VxC6ciTntMYDH3u0rYeICIE1b8hAD0VgtcOdtcSus4Lw6wmD61elvXsnblAy5mO61n1ga6cpeEsevDU5f728jvujcbME7B4zse5cnaPEE/Oso/7b+W/WQtAASgABaAAFIACUAAKQAEoAAVgo/UPbf9YutvUXXcAAAAASUVORK5CYII=',
  'call_dark': 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAFX0lEQVR42u2cq5bjRhBArycmDYsKNh0oOtB04dDA/EJoaH4hvzC/IBooGtjUsKjYLuhSq/WwJdtjSz6x5uw5s16vXLfr0VXVJe9+8tzXGy+AF8AL4AXwArjh2s/8u8dTUuIReyVQUVOj2wcQvP0IYgCK4A1EtwCx+3l67Q8ckuiSXlcTvKai2q4GovhlElwBsRWPOoj/srop7ReLT09UwXNAUOrtAUgmfi60DvRRIgSUsDUAn6KODsBymPjKHwj/rInwNhk4PX4k/vCKruz5pNzWRpbH/CWXXPj+h2iAhTFek8nJlgAuEUbX1sHbhEnIAnHa7UyT1zxlMqcWXMv1dPB2Irqw0A80y5k2AnBdkrbM8B4GQErglsKs5shjgNr2VblCB5tIJYLpYBjtSTqZgpPtOHEXIjnp4DoSn7XS6mmAsRZOmc089CoANQFdbBaSoDelgcs2tNWqgumdOBiCnI030hNftwSghqAzZhNTv5qv9Wrjt5NGEWb8oOtWRAC2B5DvyKcQAhXVtkrKviNPaUAzI6qp1u1LnE6nQ2bXUzuv2upX63aGzrUW6xnTqNcX/3xBo9bE7fuBJBOr1xd/riKr+LJYNAyhsUe9gebu+fZ6oMq2Le3Zf71uR25pTRwyMyILqxtprs8DdJmpDCLSRg445rsSbTiV9YqW2wDGOgDW7ARd4sRdOPWmg7ZwiUX8Bszot7/m39NwxOHwgKMBwKEcOT4HADQogrOfBnA4FNZHWAYASoNQIEADhtOsj7Bf/M5AjbcDvmj7pb2uz6ABaGgQPC797hAaFDW/2DgAKM5ikaOhweEoKDiuibC/6N2xdPlMGWmsicOah62XaCBGI2cxaBxqnwAgWn+DQwwhegPmC08AEAOqGzTTnW1t+gwAsZFVUKQoFF35Hfj3OQDIslOH2v68UkjdX/n/6l55054Xf/Lw+ZVrAWJRSe+IWyhRuKJP3Z9JuqhRvL8aPVDZEWsuxgGhgosQupkwsQWQ5QnK/gbttf1rn9Vq3lDqhVubz2ZjpFdChWWa3N04/C2U/MnBYlPrD0rN14KBtJJPG2sb19ixKzXbd70uCuUbW6CwdXfksxMNOrM7e37wO++WmmPxS3AUCAU+ZV3N/QC6BKNA7KPiH2freurDD3zygTcBj+l9DQ1qd3GWvjenPWL/DZGsTmF0OJIWvSFMGF6cRi3pz+NJ9nexe7R3DffTQFznmOYVWdEpFBRpVfPrgx984K0s7ey/M6T2d0eTtHu8HwAcLcEQ+9B4FVaGNoYR9VRysJUdnjo3hi8p223sLmKfcTeAVgvgcRTJhmPREwNtgfDOgR+UFBPid2khg9eclVL/jT1qz/ddbdwuLSpp2t4En7amcjDSJmeOUcjuUyLU49D8fRpoTSmYxRc9s8By1sLMoxmtsJvdcRzHsRntv1d+lBol2PbUN5Jb28IxdoX7AuSNljKDGBqInjWacwjcHwCUCkV7ehgKf60OHgJA6lOUeHyab8y1oTA6vJoroiZ0dr9HUJSKv22uOn+AgsGkxY2jOnvueSkVoCkdkG+440MBIkIYPYczFkgW2P/kCOK9AdrxqYCOEKYPSM75xUSx+ZjHsJTAF19WhMrowFAuuM/DNdA5akw1Dtnso0ysumwToKscqvSIhU9oHYKeyYgmD9cfCxATvracIXsaatg0m9Lg5GzAbpUnusXq5n5s0smoJIZdTz8/uF9DfvMISUPO/Q7fUHw185ns+a0DkKcbIelDsmalDGy/OtXq2m3iSwG69pYf7BVxLuzMUOFuM99q4HuayJ3+bIdut6mvZRgOlCxI83av75V4AbwAXgAvgP81wC8AFB1E/gyRXwAAAABJRU5ErkJggg==',
  'message': 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAADUUlEQVR42u2c25XbIBCG//jQwN8CLaiFrSVFpYW0oBbUAi1MCckDXixZICEuAiewD+tjr6z55s6Isz/+4LPXAwNgAAyAATAABsAHLxX8hNDQIDQAQm6Wi+6VgWDBchVgwuSEX3/dnUue9xYQGgtMPIDGT3yBwK2aD92PEAhm/PIhKO8FEybo1ZexgevI6h0+ZZI9oPL6/gTtvkQaRMAWwQJoTDAw77I8AsH7Er/VEvfb6v07qeAcgCtvZDMAbmQRZ4cIgHfztUTAyg5eWR4RF7df3GBEFrJ9Ro4LuHiBZGdtv+5xVErVZWOWsxgT/pqxLiS3ZhtuQjaMyVQL3OHfPLULP70blZoAzQreo7AjdLQfSAGQww6WNWymCmWRmN5JEurLqZVVtvjpLZ8EU+dtFhAIDEwCAt3WSZ8CsCaAwYIl2Z8Jja88G+S6kMGy32RcsoMBMbVMo5KRTyTr6kyAcpmfbQDKZPPsavBI1pq4n3YumBzEL6PbWUGcdn2uEpNGKwCIS4KATsxCduLGNgDrPI7NCOwaQJNKLLs9Ek/sFNNH3QjA6CTI04xTIBXnVmJGzSsqbnfyu9G4z8Wj9yKzP5WRg+wr49Ex39plbuY6UnL/VqaZ8wF8iz/ltGr19wPH3aiNEA3tGdI33lLSWcAEK/E6TXKXMnlBTawzVpHGTxCSAXhJk6w7cvkvH3TLSrdn+q3+pFNlBPCrnTvKQrouhLqs/a34E3QwC/HNBuwBgDsNy/7B26Zh7jAGrsdKt5W4ungjjQ6AATAAOlj8NywgNQCkeK2Vi0/ZsgqZHHRJ12YXoX3ce2OSfFol7qZSsH2WzVYU7tiTKQcgBy12jRC24he2QN0+iBvHNP6To6qA8FJJfHkKbu8QOL2rMpyHz8CqgyArv7fHj6NP7p6NzF+fG99JzuIgh7MnFeXb3+aUzajEYMYMU6EaVNvQ0OVja9Tf4VPlfQEIXmfJ8TwOfzxU7ABAvEnNij+HQqoXAAnM+63ul+qBW9CFXiex7Ch9zjibchuAeOyxOL/vbKmTQi7uTFCHwh8XMj4LuMHcq/BnWcg6ztxTyMYDGOc6C7peKth/fIDwfgBzU5NWFQD9Bu37+jH+KcAAGAADYAAMgAEwANLXX45SJdS4IliAAAAAAElFTkSuQmCC',
  'mail': 'iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAQAAABIkb+zAAAELklEQVR42u2b7XWzPAyGrz6HBbSCV/AKrJAVOlRXYAVW8ApeQSP0/WFhnBQSoFDIeU3/NKdtosuSbn1AP7557+sfFaACVIAKUAEqQAWoABWgApx1NU9+5hBAL2ClzlsxByC4CwFElLgGwNHiL+WBSE+YsqWZNP/Gzcy/yhURmEJoJoKn5dO4r4KggAeU8BrA4XFEizk5HULt/MXs0tcAAghquX9mDogdodhBOtyjD6ZCSIrICycDCA6fbZqIh2aSGtOfswFA8EA7r4fNZMxRBJGengFuWyuhdzhv1wtprsbnXkkTnxzkv6fxlyryuea3+GdS3rwAEKuA5yRwi8fj0Pmi2jzVYGfa29P/eTZ4brkfe5KNzdMUTjKWvPCXCILj08QzNdNufTsdCxDHJ57uj0LJWy9cykmS9ZUhNEbeUMrl8MImeDytma8TMbGwEt9/N6RUyoZ4qPm3B9XRH5YsViHNlVBQ06TkhWP8kES7bBs0R4FsA4j0OD4RBCWasEU6vg5RndYkE/vEnmDt3AoPaJEBgR5Bsh6M5U0JO4aSw9HSFkNs+vSOmP0+M9o3L3cBkS9CTqz05t6yod8p8m+0duZqpgb74i6AZB3AOA+pDXWu0KQWpqfU1Yrvc8OiFrhphI+vViqvW4lBfZWAEnNfolmVul8VOMHTFgGa2pb+QSZkK8C9J4J5YiwxoyrFTRBiquNsgZC83T0ItWzfzOmP1z2RlhafJdbjCfR0qxFS0ro8sitKR/+j2v8ihKYQgmmzK0ZPDwj9Cj88tslikt3NKJtuBZDJFVNHtHop2Q8OR7cwpV1WnXH6DotqvG7PgcdQAsXZ/nSYW9Xy4XWv43N1V1P8sKhFkX0ABvkcm65k/A3/IwV/pu0Q+UPBDFawNmrZVoBSlcZi4wE3s4ZNteNW7HaESDTZXH3yvwVIEB3BVKnMhpaerwc/pGrri0ZNiPRzO+el5q9VoemUTs1FuT3z3O7O1RWYY5+15OwPC6F7P0Sr0uMEd0OsCRlUZ0h3yX3uLpNFs915D9WBojpgLXDacY83SyT3OmGF+XqsB8aUbq06qPX3nmiD0PBbrjj7nUaifQCG6qBFgSObLjmwlJ5u10liR4ChV7pZ/OvDflVQOr723mw0+74dkd46VmdGS56v4h6qczQABNMk7rZqoRhRLg4w9kpDxzNoziHrmCMAAPpco/VFf3RRgCGlvakT7wcw7BYOvurjNhXgUAB9dwCpIVQBKkBVoapC7x5C5UNOuhwg3eyRi5i/eTvtaA+8K7zkcnc3/ljy2KXe/XF7eiIPz0sMO6UFAFo47/wgUsYnWOMSD0QCbUF+vvmSb4IsusERCYRLJPB9UIfprcbH91TUebv7ch2EOPeExsf3XPb7Cz3+HYhz0/VH/X/iClABKkAFqAAVoAJUgApQAf63AP8BPGi0aWZT0joAAAAASUVORK5CYII=',
  'phone_small': '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',
  'star': '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',
  'edit': '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',
  'person': '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',
};

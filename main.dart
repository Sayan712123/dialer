import 'package:call_log/call_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

// Approximate Xiaomi (MIUI/HyperOS) palette. Only the missed-call red (#FA382E)
// was read from the original APK; the rest are visual approximations.
const kBlue = Color(0xFF0D84FF);
const kGreen = Color(0xFF34B948);
const kMissed = Color(0xFFFA382E);

void main() => runApp(const ContactsDialerApp());

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: ColorScheme.fromSeed(seedColor: kBlue, brightness: b)
        .copyWith(primary: kBlue, surface: dark ? const Color(0xFF1C1C1E) : Colors.white),
    scaffoldBackgroundColor: dark ? Colors.black : const Color(0xFFF7F7F7),
    splashFactory: NoSplash.splashFactory,
    highlightColor: dark ? Colors.white10 : Colors.black12,
    dividerColor: dark ? Colors.white12 : Colors.black12,
  );
}

class ContactsDialerApp extends StatelessWidget {
  const ContactsDialerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Contacts and dialer',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const HomeShell(),
      );
}

Color cardColor(BuildContext c) => Theme.of(c).colorScheme.surface;
Color subText(BuildContext c) =>
    Theme.of(c).brightness == Brightness.dark ? Colors.white54 : Colors.black45;

Future<void> placeCall(BuildContext context, String number) async {
  if (number.trim().isEmpty) return;
  if (await Permission.phone.request().isGranted) {
    await FlutterPhoneDirectCaller.callNumber(number);
  } else {
    await launchUrl(Uri(scheme: 'tel', path: number));
  }
}

const _avatarColors = [
  Color(0xFF5B9BF8), Color(0xFF4CC38A), Color(0xFFF5A623),
  Color(0xFFEF6F6C), Color(0xFF9B7EDE), Color(0xFF3FB5C9),
];

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  const Avatar(this.name, {super.key, this.size = 44});
  @override
  Widget build(BuildContext context) {
    final c = _avatarColors[(name.isEmpty ? 0 : name.codeUnitAt(0)) % _avatarColors.length];
    return Material(
        type: MaterialType.transparency,
        child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withOpacity(.18), shape: BoxShape.circle),
      child: Text(name.isEmpty ? '#' : name.characters.first.toUpperCase(),
          style: TextStyle(color: c, fontSize: size * .42, fontWeight: FontWeight.w500)),
    ));
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

/// Staggered entrance for list rows (first dozen only).
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

/// Page push: slides in from the right while the page below drifts left.
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

/// Rounded "group" card used for every list, as in MIUI settings-style lists.
class GroupCard extends StatelessWidget {
  final List<Widget> children;
  const GroupCard({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
            color: cardColor(context), borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(height: .5, indent: 76, color: Theme.of(context).dividerColor),
          ]
        ]),
      );
}

class SearchPill extends StatelessWidget {
  final String hint;
  final ValueChanged<String>? onChanged;
  const SearchPill({super.key, required this.hint, this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white12
                  : Colors.black.withOpacity(.05),
              borderRadius: BorderRadius.circular(20)),
          child: TextField(
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: subText(context), fontSize: 15),
              prefixIcon: Icon(Icons.search, size: 20, color: subText(context)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      );
}

/// Large collapsing title like MIUI apps.
Widget miuiHeader(String title, {List<Widget>? actions}) => SliverAppBar.large(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
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
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Expanded(
            child: Stack(children: [
              _tabPage(0, const RecentsPage()),
              _tabPage(1, const ContactsPage()),
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
          color: cardColor(context),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: Row(children: [
                _NavItem(Icons.access_time, 'Recents', _tab == 0, () => setState(() => _tab = 0)),
                // Centre round keypad toggle, like the original dialer.
                Expanded(
                  child: Center(
                    child: Pressable(
                      scale: .88,
                      onTap: () => setState(() => _keypad = !_keypad),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(color: kBlue, shape: BoxShape.circle),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (c, a) => RotationTransition(
                              turns: Tween(begin: .75, end: 1.0).animate(a),
                              child: ScaleTransition(scale: a, child: c)),
                          child: Icon(
                              _keypad ? Icons.keyboard_arrow_down : Icons.dialpad,
                              key: ValueKey(_keypad),
                              color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
                _NavItem(Icons.person_outline, 'Contacts', _tab == 1, () => setState(() => _tab = 1)),
              ]),
            ),
          ),
        ),
      );
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem(this.icon, this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) {
    final c = selected ? kBlue : subText(context);
    return Expanded(
      child: Pressable(
        onTap: onTap,
        scale: .9,
        child: SizedBox.expand(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedScale(
              scale: selected ? 1.12 : 1,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: c),
                duration: const Duration(milliseconds: 200),
                builder: (_, col, __) => Icon(icon, color: col, size: 24),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                  color: c,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
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
    ['*', ''], ['0', '+'], ['#', ''],
  ];

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
            color: cardColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 52,
            child: Row(children: [
              const SizedBox(width: 48),
              Expanded(
                  child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 150),
                      style: TextStyle(
                          fontSize: number.length > 14 ? 20 : (number.length > 10 ? 25 : 30),
                          fontWeight: FontWeight.w300,
                          color: Theme.of(context).colorScheme.onSurface),
                      child: Text(number,
                          textAlign: TextAlign.center, overflow: TextOverflow.ellipsis))),
              SizedBox(
                width: 48,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: number.isEmpty
                      ? const SizedBox.shrink(key: ValueKey(0))
                      : GestureDetector(
                          key: const ValueKey(1),
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            onChanged('');
                          },
                          child: IconButton(
                              icon: const Icon(Icons.backspace_outlined),
                              onPressed: () => onChanged(number.substring(0, number.length - 1))),
                        ),
                ),
              ),
            ]),
          ),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            childAspectRatio: 1.9,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final k in _keys)
                Pressable(
                  scale: .85,
                  onTap: () => onChanged(number + k[0]),
                  onLongPress: k[0] == '0' ? () => onChanged('$number+') : null,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(k[0], style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w300)),
                    SizedBox(
                        height: 12,
                        child: Text(k[1], style: TextStyle(fontSize: 9, color: subText(context)))),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Pressable(
            scale: .92,
            onTap: () => placeCall(context, number),
            child: Container(
              height: 52,
              width: 160,
              decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(26)),
              child: const Icon(Icons.call, color: Colors.white, size: 26),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      );
}

// ---------------- Recents ----------------
class RecentsPage extends StatefulWidget {
  const RecentsPage({super.key});
  @override
  State<RecentsPage> createState() => _RecentsPageState();
}

class _RecentsPageState extends State<RecentsPage> {
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

  String _when(int? ms) {
    if (ms == null) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final t = '${two(d.hour)}:${two(d.minute)}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) return t;
    return '${two(d.month)}/${two(d.day)} $t';
  }

  @override
  Widget build(BuildContext context) {
    final list = (_entries ?? [])
        .where((e) => !_missedOnly || e.callType == CallType.missed)
        .toList();
    return CustomScrollView(slivers: [
      miuiHeader('Recents', actions: [
        TextButton(
            onPressed: () => setState(() => _missedOnly = !_missedOnly),
            child: Text(_missedOnly ? 'All' : 'Missed')),
      ]),
      const SliverToBoxAdapter(child: SearchPill(hint: 'Search contacts and numbers')),
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
        SliverToBoxAdapter(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(_missedOnly),
              child: GroupCard(children: [
                for (final e in list.take(200).toList().asMap().entries)
                  FadeSlideIn(
                      index: e.key,
                      child: _RecentTile(entry: e.value, when: _when(e.value.timestamp))),
              ]),
            ),
          ),
        ),
    ]);
  }
}

class _RecentTile extends StatelessWidget {
  final CallLogEntry entry;
  final String when;
  const _RecentTile({required this.entry, required this.when});
  @override
  Widget build(BuildContext context) {
    final name = (entry.name?.isNotEmpty ?? false) ? entry.name! : (entry.number ?? 'Unknown');
    final missed = entry.callType == CallType.missed;
    final kind = switch (entry.callType) {
      CallType.outgoing => 'Outgoing',
      CallType.missed => 'Missed',
      CallType.rejected => 'Declined',
      _ => 'Incoming',
    };
    return Pressable(
      scale: .97,
      haptic: false,
      onTap: () => placeCall(context, entry.number ?? ''),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Avatar(name),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, color: missed ? kMissed : null)),
              const SizedBox(height: 2),
              Text(kind, style: TextStyle(fontSize: 13, color: subText(context))),
            ]),
          ),
          Text(when, style: TextStyle(fontSize: 13, color: subText(context))),
          const SizedBox(width: 12),
          Icon(Icons.info_outline, size: 22, color: subText(context)),
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
  List<Contact>? _all;
  String _q = '';
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!await FlutterContacts.requestPermission()) {
      setState(() => _denied = true);
      return;
    }
    final list = await FlutterContacts.getContacts(withProperties: true);
    list.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    setState(() {
      _denied = false;
      _all = list;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = (_all ?? [])
        .where((c) =>
            c.displayName.toLowerCase().contains(_q.toLowerCase()) ||
            c.phones.any((p) => p.number.contains(_q)))
        .toList();
    // Group by first letter
    final groups = <String, List<Contact>>{};
    for (final c in shown) {
      final l = c.displayName.isEmpty ? '#' : c.displayName.characters.first.toUpperCase();
      groups.putIfAbsent(RegExp(r'[A-Z]').hasMatch(l) ? l : '#', () => []).add(c);
    }
    return CustomScrollView(slivers: [
      miuiHeader('Contacts', actions: [
        IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await FlutterContacts.openExternalInsert();
              _load();
            }),
      ]),
      SliverToBoxAdapter(
          child: SearchPill(hint: 'Search contacts', onChanged: (v) => setState(() => _q = v))),
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
        SliverList(
          delegate: SliverChildListDelegate([
            for (final e in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 4, 16, 6),
                child: Text(e.key,
                    style: TextStyle(fontSize: 13, color: subText(context), fontWeight: FontWeight.w500)),
              ),
              GroupCard(children: [
                for (final c in e.value)
                  Pressable(
                    scale: .97,
                    haptic: false,
                    onTap: () => Navigator.push(context, miuiRoute(ContactDetail(contact: c))),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(children: [
                        Hero(tag: 'avatar-${c.id}', child: Avatar(c.displayName)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.displayName, style: const TextStyle(fontSize: 17)),
                            if (c.phones.isNotEmpty)
                              Text(c.phones.first.number,
                                  style: TextStyle(fontSize: 13, color: subText(context))),
                          ]),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ],
            const SizedBox(height: 24),
          ]),
        ),
    ]);
  }
}

class ContactDetail extends StatelessWidget {
  final Contact contact;
  const ContactDetail({super.key, required this.contact});

  Widget _action(BuildContext context, IconData i, String label, VoidCallback onTap) => Expanded(
        child: Pressable(
          onTap: onTap,
          scale: .93,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration:
                BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Icon(i, color: kBlue),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final first = contact.phones.isEmpty ? null : contact.phones.first.number;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton(
              onPressed: () => FlutterContacts.openExternalEdit(contact.id),
              child: const Text('Edit')),
        ],
      ),
      body: ListView(children: [
        Center(
            child: Hero(
                tag: 'avatar-${contact.id}',
                child: Avatar(contact.displayName, size: 88))),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
              child: Text(contact.displayName,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600))),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          child: Row(children: [
            _action(context, Icons.call, 'Call', () => first == null ? null : placeCall(context, first)),
            _action(context, Icons.message_outlined, 'Message',
                () => first == null ? null : launchUrl(Uri(scheme: 'sms', path: first))),
            _action(context, Icons.email_outlined, 'Email', () {
              if (contact.emails.isNotEmpty) {
                launchUrl(Uri(scheme: 'mailto', path: contact.emails.first.address));
              }
            }),
          ]),
        ),
        if (contact.phones.isNotEmpty)
          GroupCard(children: [
            for (final p in contact.phones)
              ListTile(
                title: Text(p.number, style: const TextStyle(fontSize: 17)),
                subtitle: Text(p.label.name),
                onTap: () => placeCall(context, p.number),
                trailing: IconButton(
                    icon: const Icon(Icons.message_outlined, color: kBlue),
                    onPressed: () => launchUrl(Uri(scheme: 'sms', path: p.number))),
              ),
          ]),
        if (contact.emails.isNotEmpty)
          GroupCard(children: [
            for (final e in contact.emails)
              ListTile(title: Text(e.address), subtitle: Text(e.label.name)),
          ]),
      ]),
    );
  }
}

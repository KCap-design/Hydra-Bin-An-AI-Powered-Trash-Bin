import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hydra_bin/models/leaderboard_item.dart';
import 'package:hydra_bin/screens/auth_screen.dart';
import 'package:hydra_bin/screens/connect_screen.dart';
import 'package:hydra_bin/services/cache_service.dart';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:http/http.dart' as http;

// ─── Palette ─────────────────────────────────────────────────────────────────
const Color _bg      = Color(0xFF0D0F1A);
const Color _surface = Color(0xFF141622);
const Color _card    = Color(0xFF1A1D2E);
const Color _card2   = Color(0xFF1E2235);
const Color _border  = Color(0xFF2A2F45);
const Color _accent  = Color(0xFF22C55E);
const Color _textPri = Color(0xFFF0F4FF);
const Color _textSec = Color(0xFF6B7280);
const Color _gold    = Color(0xFFFFD93D);
const Color _silver  = Color(0xFFCBD5E1);
const Color _bronze  = Color(0xFFCD7F32);
const Color _red     = Color(0xFFEF4444);
const Color _online  = Color(0xFF22C55E);
const Color _offline = Color(0xFF374151);

// ─── Store data ───────────────────────────────────────────────────────────────
class _StoreItem {
  final String id;
  final String name;
  final int cost;
  final String type; // 'frame' | 'bg'
  final Color? color;
  final String? emoji;
  const _StoreItem({required this.id, required this.name, required this.cost, required this.type, this.color, this.emoji});
}

const _frames = <_StoreItem>[
  _StoreItem(id: 'none',    name: 'Default',       cost: 0,   type: 'frame', color: Colors.transparent),
  _StoreItem(id: 'green',   name: 'Eco Warrior',   cost: 50,  type: 'frame', color: Color(0xFF22C55E)),
  _StoreItem(id: 'gold',    name: 'Gold Champion', cost: 100, type: 'frame', color: Color(0xFFFFD93D)),
  _StoreItem(id: 'silver',  name: 'Silver Elite',  cost: 75,  type: 'frame', color: Color(0xFFCBD5E1)),
  _StoreItem(id: 'blue',    name: 'Ocean Master',  cost: 80,  type: 'frame', color: Color(0xFF3B82F6)),
  _StoreItem(id: 'purple',  name: 'Cosmic Ring',   cost: 120, type: 'frame', color: Color(0xFFA855F7)),
  _StoreItem(id: 'red',     name: 'Fire Blaze',    cost: 90,  type: 'frame', color: Color(0xFFEF4444)),
  _StoreItem(id: 'rainbow', name: 'Rainbow Aura',  cost: 200, type: 'frame', emoji: '🌈'),
];

const _bgs = <_StoreItem>[
  _StoreItem(id: 'default',  name: 'Dark Space',    cost: 0,   type: 'bg', color: Color(0xFF0D0F1A)),
  _StoreItem(id: 'forest',   name: 'Forest Night',  cost: 60,  type: 'bg', color: Color(0xFF0D1A0F)),
  _StoreItem(id: 'ocean',    name: 'Deep Ocean',    cost: 60,  type: 'bg', color: Color(0xFF0D1224)),
  _StoreItem(id: 'purple',   name: 'Mystic Purple', cost: 80,  type: 'bg', color: Color(0xFF150D24)),
  _StoreItem(id: 'ember',    name: 'Ember Red',     cost: 90,  type: 'bg', color: Color(0xFF1A0D0D)),
  _StoreItem(id: 'gold',     name: 'Golden Hour',   cost: 100, type: 'bg', color: Color(0xFF1A1500)),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  StreamSubscription<DocumentSnapshot>? _userSub;
  StreamSubscription<QuerySnapshot>?    _lbSub;
  StreamSubscription<DocumentSnapshot>? _announceSub;

  // ── User state ─────────────────────────────────────────────────────────────
  int    _points     = 0;
  int?   _lastPoints;
  int    _streak     = 0;
  String _userName   = 'User';
  String _myEmail    = '';
  String _myUid      = '';
  String _activeFrame = 'none';
  List<String> _unlockedFrames = ['none'];
  String? _profileUrl;          // from Google
  String? _profileB64;          // uploaded from device (stored in Firestore)
  String? _customBgId;          // custom background theme id
  String? _cachedBg;            // device-uploaded background (base64)
  bool   _confetti   = false;
  String? _announce;

  // ── Roblox Redemption ────────────────────────────────────────────────────────
  final TextEditingController _robloxController = TextEditingController();
  Map<String, dynamic>? _robloxUser;
  String? _robloxError;
  bool _robloxLoading = false;
  bool _redeemSuccess  = false;
  bool _awaitingAwesome = false; // confirm dialog
  bool _isRedeeming    = false;  // suppress confetti during redemption
  int  _selectedTierIdx = -1;
  bool _connectHover   = false;

  static const List<Map<String, int>> _robuxTiers = [
    {'points': 100, 'robux': 500},
    {'points': 150, 'robux': 1000},
    {'points': 500, 'robux': 5250},
  ];

  // ── Leaderboard ─────────────────────────────────────────────────────────────
  List<LeaderboardItem> _lb = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _loadCache();
    _setupFCM();
    
    // Listen for PWA installability
    html.window.addEventListener('pwa-install-available', (e) {
      if (mounted) setState(() {});
    });

    _listenUser();
    _listenLb();
    _listenAnnounce();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userSub?.cancel();
    _lbSub?.cancel();
    _announceSub?.cancel();
    _robloxController.dispose();
    super.dispose();
  }

  Future<void> _loadCache() async {
    final d  = await CacheService.getUserData();
    final bg = await CacheService.getCustomBackground();
    final ph = await CacheService.getProfilePhoto();
    if (!mounted) return;
    setState(() {
      if (d != null) {
        _points = (d['points'] as num?)?.toInt() ?? 0;
        _streak = (d['streak'] as num?)?.toInt() ?? 0;
        _userName = d['name'] as String? ?? 'User';
        _activeFrame = d['activeFrame'] as String? ?? 'none';
        // Seed _lastPoints so the first Firestore snapshot never looks like an increase
        _lastPoints = _points;
      }
      _cachedBg   = bg;
      _profileB64 = ph;
    });
  }

  Future<void> _setupFCM() async {
    try {
      // Request permission (shows browser popup on web)
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await FirebaseMessaging.instance.getToken(
          vapidKey: 'BBKqJdH8SzaJkiOczuEUQUo1fIV3M6JMU0VKI0_KkifaBp7HJB2VTiGrLhIophrDIGIg9Hf2vq5i2YKJMvPt3Wc',
        );
        if (token != null && _myUid.isNotEmpty) {
          FirebaseFirestore.instance.collection('users').doc(_myUid).update({'fcmToken': token});
        }
      }
      // Handle foreground messages (show snackbar)
      FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        if (n != null && mounted) {
          _snack('🔔 ${n.title ?? 'Hydra Bin'}: ${n.body ?? ''}', _accent);
        }
      });
    } catch (_) {}
  }

  void _listenAnnounce() {
    _announceSub = FirebaseFirestore.instance.collection('system').doc('announcements').snapshots().listen((s) {
      if (s.exists && mounted) setState(() => _announce = s.data()?['text'] as String?);
    });
  }

  void _listenUser() {
    if (_myUid.isEmpty) return;
    _userSub = FirebaseFirestore.instance.collection('users').doc(_myUid).snapshots().listen((s) {
      if (!s.exists || !mounted) return;
      final d = s.data()!;
      final pts = (d['points'] as num?)?.toInt() ?? 0;
      if (_lastPoints != null && pts > _lastPoints! && !_isRedeeming) {
        // Only trigger confetti if points ACTUALLY increased from a previous KNOWN state.
        setState(() => _confetti = true);
      }
      _lastPoints = pts;
      setState(() {
        _points = pts;
        _streak = (d['streak'] as num?)?.toInt() ?? 0;
        _userName = d['name'] as String? ?? 'User';
        _myEmail = d['email'] as String? ?? '';
        _activeFrame = d['activeFrame'] as String? ?? 'none';
        _unlockedFrames = List<String>.from(d['unlockedFrames'] ?? ['none']);
        _profileUrl = d['profileImageUrl'] as String?;
        _profileB64 = (d['profileImageBase64'] as String?)?.isNotEmpty == true ? d['profileImageBase64'] as String : null;
        _customBgId = d['activeBg'] as String?;
      });
      CacheService.saveUserData({'points': pts, 'streak': _streak, 'name': _userName, 'activeFrame': _activeFrame});
    });
  }

  void _listenLb() {
    _lbSub = FirebaseFirestore.instance.collection('users').orderBy('points', descending: true).limit(20).snapshots().listen((s) {
      if (!mounted) return;
      final list = s.docs.asMap().entries.map((e) {
        final d = e.value.data();
        return LeaderboardItem(
          rank: e.key + 1,
          name: d['name'] as String? ?? 'User',
          points: (d['points'] as num?)?.toInt() ?? 0,
          email: d['email'] as String? ?? '',
          profileImageUrl: d['profileImageUrl'] as String?,
          profileImageBase64: (d['profileImageBase64'] as String?)?.isNotEmpty == true ? d['profileImageBase64'] as String : null,
          isOnline: d['isOnline'] as bool? ?? false,
          activeFrame: d['activeFrame'] as String? ?? 'none',
        );
      }).toList();
      setState(() => _lb = list);
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _gravatar(String email) {
    final h = md5.convert(utf8.encode(email.trim().toLowerCase())).toString();
    return 'https://www.gravatar.com/avatar/$h?d=identicon&s=200';
  }

  Color _frameColor(String frame) {
    final f = _frames.firstWhere((e) => e.id == frame, orElse: () => const _StoreItem(id: 'none', name: '', cost: 0, type: 'frame', color: Colors.transparent));
    return f.color ?? Colors.transparent;
  }

  bool _isRainbow(String frame) => frame == 'rainbow';

  Color _bgColor() {
    final id = _customBgId ?? 'default';
    final bg = _bgs.firstWhere((e) => e.id == id, orElse: () => _bgs.first);
    return bg.color ?? _bg;
  }

  Widget _avatar(double r, {
    required String email,
    String? url,
    String? b64,
    String frame = 'none',
    bool online = false,
    bool offlineDimmed = false,
  }) {
    ImageProvider? img;
    if (b64 != null && b64.isNotEmpty) {
      img = MemoryImage(base64Decode(b64));
    } else if (url != null && url.isNotEmpty) {
      img = NetworkImage(url);
    } else if (email.isNotEmpty) {
      img = NetworkImage(_gravatar(email));
    }

    final fc = _frameColor(frame);
    final isRainbow = _isRainbow(frame);

    Widget circle = Container(
      padding: isRainbow ? const EdgeInsets.all(3) : EdgeInsets.all(frame == 'none' ? 0 : 2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isRainbow ? const LinearGradient(colors: [Colors.red, Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple]) : null,
        border: (!isRainbow && frame != 'none') ? Border.all(color: fc, width: 3) : null,
      ),
      child: CircleAvatar(
        radius: r,
        backgroundColor: _surface,
        backgroundImage: img,
        child: img == null ? Icon(Icons.person_rounded, color: _textSec, size: r) : null,
      ),
    );

    if (offlineDimmed) {
      circle = Opacity(opacity: 0.55, child: circle);
    }

    return Stack(clipBehavior: Clip.none, children: [
      circle,
      Positioned(
        right: 0, bottom: 0,
        child: Container(
          width: r * 0.52, height: r * 0.52,
          decoration: BoxDecoration(
            color: online ? _online : _offline,
            shape: BoxShape.circle,
            border: Border.all(color: _bgColor(), width: 2),
            boxShadow: online ? [BoxShadow(color: _online.withValues(alpha: 0.6), blurRadius: 6)] : [],
          ),
        ),
      ),
    ]);
  }

  // ── Store logic ─────────────────────────────────────────────────────────────

  Future<void> _buyOrEquip(_StoreItem item) async {
    final uid = _myUid;
    if (uid.isEmpty) return;
    final field  = item.type == 'frame' ? 'unlockedFrames' : 'unlockedBgs';
    final active = item.type == 'frame' ? 'activeFrame'    : 'activeBg';
    final owned  = item.type == 'frame' ? _unlockedFrames  : (_customBgId != null ? [_customBgId!] : <String>[]);

    if (owned.contains(item.id) || item.cost == 0) {
      // Just equip
      await FirebaseFirestore.instance.collection('users').doc(uid).update({active: item.id});
      _snack('✓ Equipped "${item.name}"', _accent);
    } else {
      // Buy
      if (_points < item.cost) {
        _snack('Not enough points! Need ${item.cost} pts.', _red);
        return;
      }
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'points': FieldValue.increment(-item.cost),
        field: FieldValue.arrayUnion([item.id]),
        active: item.id,
      });
      _snack('✓ Purchased & equipped "${item.name}"!', _accent);
    }
  }

  void _snack(String msg, Color col) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: col, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _pickProfilePhoto() async {
    final p = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, imageQuality: 80);
    if (p == null) return;
    final b = base64Encode(await p.readAsBytes());
    await FirebaseFirestore.instance.collection('users').doc(_myUid).update({'profileImageBase64': b});
    await CacheService.saveProfilePhoto(b);
    setState(() => _profileB64 = b);
    _snack('Profile photo updated!', _accent);
  }

  Future<void> _pickBg() async {
    final p = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 70);
    if (p == null) return;
    final b = base64Encode(await p.readAsBytes());
    await CacheService.saveCustomBackground(b);
    setState(() => _cachedBg = b);
    _snack('Background updated!', _accent);
  }

  // ── Roblox helpers ─────────────────────────────────────────────────────────

  // Tries to GET from Roblox through an exhaustive list of CORS proxies.
  // Shuffles and tries EVERY proxy in the list before giving up.
  Future<http.Response?> _robloxGet(String pathOrFullUrl) async {
    final String target = pathOrFullUrl.startsWith('http') ? pathOrFullUrl : 'https://thumbnails.roblox.com$pathOrFullUrl';
    final endpoints = [
      'https://api.allorigins.win/get?url=${Uri.encodeComponent(target)}',
      'https://api.allorigins.win/raw?url=${Uri.encodeComponent(target)}',
      'https://corsproxy.io/?$target',
      'https://api.codetabs.com/v1/proxy?quest=${Uri.encodeComponent(target)}',
      'https://proxy.cors.sh/$target',
      'https://thingproxy.freeboard.io/fetch/$target',
      'https://corsproxy.org/?$target',
      target.replaceFirst('roblox.com', 'roproxy.com'),
      target.replaceFirst('roblox.com', 'rbxapi.com'),
    ];
    endpoints.shuffle();
    
    for (final url in endpoints) {
      try {
        final r = await http.get(Uri.parse(url), headers: {
          if (url.contains('proxy.cors.sh')) 'x-cors-api-key': 'temp_c2fde9a02fb4206c',
        }).timeout(const Duration(seconds: 8)); // Slightly shorter timeout to rotate faster
        
        if (r.statusCode == 200) {
          if (url.contains('allorigins.win/get')) {
            final outer = jsonDecode(r.body) as Map<String, dynamic>;
            return http.Response(outer['contents'] as String, 200);
          }
          return r;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _lookupRoblox() async {
    final username = _robloxController.text.trim().replaceAll(RegExp(r'\s+'), '');
    if (username.isEmpty) return;
    setState(() { 
      _robloxLoading = true; 
      _robloxError = null; 
      _redeemSuccess = false; 
    });

    try {
      // Try multiple times with exponential backoff and proxy rotation
      http.Response? res;
      for (int i = 0; i < 4; i++) {
        res = await _robloxGet('https://users.roblox.com/v1/users/search?keyword=$username&limit=100');
        if (res != null && res.statusCode == 200) break;
        // Exponential backoff: 500ms, 1000ms, 2000ms
        await Future.delayed(Duration(milliseconds: 500 * (1 << i)));
      }
      
      if (res == null || res.statusCode != 200) {
        setState(() { 
          _robloxError = 'Roblox servers are slow. Please retry once.'; 
          _robloxLoading = false; 
        });
        return;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final users = (data['data'] as List?) ?? [];
      
      Map<String, dynamic>? exactUser;
      final targetLower = username.toLowerCase();
      
      // Match Priority: Name (Case-insensitive) -> DisplayName (Case-insensitive)
      for (var u in users) {
        final uname = (u['name'] as String).toLowerCase();
        final dname = (u['displayName'] as String).toLowerCase();
        if (uname == targetLower || dname == targetLower) {
          exactUser = u as Map<String, dynamic>;
          break;
        }
      }

      if (exactUser == null) {
        setState(() { 
          _robloxError = 'User "$username" not found. Check spelling.'; 
          _robloxLoading = false; 
          _robloxUser = null; 
          _selectedTierIdx = -1;
        });
        return;
      }

      final int id = (exactUser['id'] as num).toInt();
      final String name = exactUser['name'] as String;

      // Fetch avatar with the same robust proxy logic
      String avatarUrl = '';
      try {
        final ar = await _robloxGet('https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=$id&size=150x150&format=Png&isCircular=true');
        if (ar != null) {
          final aList = ((jsonDecode(ar.body) as Map)['data'] as List?);
          avatarUrl = (aList?.first as Map?)?['imageUrl'] as String? ?? '';
        }
      } catch (_) {}

      setState(() { 
        _robloxUser = {'id': id, 'name': name, 'avatarUrl': avatarUrl}; 
        _robloxLoading = false; 
      });
    } catch (e) {
      setState(() { 
        _robloxError = 'Error connecting to Roblox. Retry search.'; 
        _robloxLoading = false; 
        _robloxUser = null;
        _selectedTierIdx = -1;
      });
    }
  }

  Future<void> _redeemRobux() async {
    if (_isRedeeming) return;
    if (_selectedTierIdx < 0 || _robloxUser == null) return;
    final tier  = _robuxTiers[_selectedTierIdx];
    final pts   = tier['points']!;
    final robux = tier['robux']!;
    if (_points < pts) { _snack('Not enough points! Need $pts pts.', _red); return; }
    setState(() => _isRedeeming = true);
    try {
      // Write redemption log INSIDE the user's own doc (avoids needing extra Firestore rules)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_myUid)
          .update({
            'points': FieldValue.increment(-pts),
            'lastRedemption': {
              'robloxUsername': _robloxUser!['name'],
              'robloxId': _robloxUser!['id'],
              'robux': robux,
              'pointsSpent': pts,
              'timestamp': FieldValue.serverTimestamp(),
              'status': 'pending',
            },
          });

      if (!mounted) return;
      setState(() {
        _redeemSuccess = true;
        _isRedeeming = false;
      });
    } catch (e) {
      print('DEBUG: Redemption error: $e');
      if (!mounted) return;
      setState(() => _isRedeeming = false);
      String errorMsg = e.toString();
      if (errorMsg.contains('permission-denied')) {
        errorMsg = 'Permission denied. Contact support.';
      } else if (errorMsg.contains('not-found')) {
        errorMsg = 'User data not found.';
      }
      _snack('Redemption failed: $errorMsg', _red);
    }
  }

  // ─── Tabs ──────────────────────────────────────────────────────────────────

  Widget _buildHomeTab() {
    final top = _lb.take(3).toList();
    final rest = _lb.skip(3).toList();
    return ListView(padding: EdgeInsets.zero, children: [
      // Announcement
      if (_announce != null)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _accent.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            const Icon(Icons.campaign_rounded, color: _accent, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(_announce!, style: const TextStyle(color: _textPri, fontWeight: FontWeight.w600, fontSize: 13))),
          ]),
        ),

      // Stats row
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          Expanded(child: _statCard('$_points', 'TOTAL POINTS', Icons.bolt_rounded, _gold)),
          const SizedBox(width: 12),
          Expanded(child: _statCard('${_streak}d', 'STREAK', Icons.local_fire_department_rounded, const Color(0xFFFF6B35))),
        ]),
      ),

      // Connect button
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: MouseRegion(
          onEnter: (_) => setState(() => _connectHover = true),
          onExit:  (_) => setState(() => _connectHover = false),
          child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectScreen())),
            child: AnimatedScale(
              scale: _connectHover ? 1.025 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: _connectHover
                      ? [const Color(0xFF22C55E), const Color(0xFF15803D)]
                      : [const Color(0xFF22C55E), const Color(0xFF16A34A)]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(
                    color: _accent.withValues(alpha: _connectHover ? 0.55 : 0.35),
                    blurRadius: _connectHover ? 36 : 24,
                    offset: const Offset(0, 8),
                  )],
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.qr_code_scanner_rounded, color: Colors.black, size: 26),
                  SizedBox(width: 12),
                  Text('CONNECT TO SMART BIN', style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                ]),
              ),
            ),
          ),
        ),
      ),

      // Leaderboard header
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 28, 16, 8),
        child: Row(children: [
          Icon(Icons.emoji_events_rounded, color: _gold, size: 20),
          SizedBox(width: 8),
          Text('LEADERBOARD', style: TextStyle(color: _textSec, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)),
        ]),
      ),

      // Podium
      if (top.isNotEmpty) _buildPodium(top),

      // Rest of list
      ...rest.map(_buildRankRow),
      const SizedBox(height: 100),
    ]);
  }

  Widget _statCard(String val, String label, IconData ic, Color col) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card, borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ic, color: col, size: 22),
        const SizedBox(height: 10),
        Text(val, style: TextStyle(color: col, fontSize: 26, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(color: _textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
      ]),
    );
  }

  Widget _buildPodium(List<LeaderboardItem> top) {
    // Order: 2nd, 1st, 3rd
    final order = [
      if (top.length > 1) top[1],
      top[0],
      if (top.length > 2) top[2],
    ];
    final heights = [
      if (top.length > 1) 105.0,
      140.0,
      if (top.length > 2) 85.0,
    ];
    final medalColors = [
      if (top.length > 1) _silver,
      _gold,
      if (top.length > 2) _bronze,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [_card2, _surface],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: _border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(order.length, (i) {
            final u    = order[i];
            final isMe = u.email == _myEmail;
            final rank = u.rank;
            return Expanded(
              flex: i == 1 ? 5 : 4,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Crown/medal
                Icon(
                  rank == 1 ? Icons.workspace_premium_rounded :
                  rank == 2 ? Icons.military_tech_rounded :
                  Icons.military_tech_rounded,
                  color: rank == 1 ? _gold : rank == 2 ? _silver : _bronze,
                  size: i == 1 ? 26 : 22,
                ),
                const SizedBox(height: 4),
                // Avatar
                _avatar(i == 1 ? 32 : 26,
                    email: u.email, url: u.profileImageUrl, b64: u.profileImageBase64,
                    frame: u.activeFrame, online: u.isOnline),
                const SizedBox(height: 8),
                Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                    style: TextStyle(color: isMe ? _accent : _textPri, fontSize: i == 1 ? 13 : 11, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                // Podium bar
                Container(
                  height: heights[i],
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [medalColors[i].withValues(alpha: 0.35), medalColors[i].withValues(alpha: 0.08)],
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    border: Border(
                      top: BorderSide(color: medalColors[i].withValues(alpha: 0.6), width: 2),
                      left: BorderSide(color: medalColors[i].withValues(alpha: 0.3)),
                      right: BorderSide(color: medalColors[i].withValues(alpha: 0.3)),
                    ),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('#$rank', style: TextStyle(color: medalColors[i], fontSize: i == 1 ? 26 : 20, fontWeight: FontWeight.w900)),
                    Text('${u.points} pts', style: TextStyle(color: _textSec, fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildRankRow(LeaderboardItem u) {
    final isMe = u.email == _myEmail;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? _accent.withValues(alpha: 0.05) : _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isMe ? _accent.withValues(alpha: 0.3) : _border),
      ),
      child: Row(children: [
        SizedBox(width: 26, child: Text('${u.rank}', style: const TextStyle(color: _textSec, fontWeight: FontWeight.w900, fontSize: 14))),
        _avatar(18, email: u.email, url: u.profileImageUrl, b64: u.profileImageBase64, frame: u.activeFrame, online: u.isOnline),
        const SizedBox(width: 12),
        Expanded(child: Text(u.name, style: TextStyle(color: isMe ? _accent : _textPri, fontWeight: FontWeight.w700, fontSize: 13))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isMe ? _accent.withValues(alpha: 0.15) : _surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('${u.points} pts', style: TextStyle(color: isMe ? _accent : _textSec, fontWeight: FontWeight.w800, fontSize: 12)),
        ),
      ]),
    );
  }

  // ─── Store Tab ─────────────────────────────────────────────────────────────

  Widget _buildStoreTab() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Points header with fade-in
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 600),
        builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_gold.withValues(alpha: 0.15), _gold.withValues(alpha: 0.04)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _gold.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.bolt_rounded, color: _gold, size: 24),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_points', style: const TextStyle(color: _gold, fontSize: 32, fontWeight: FontWeight.w900)),
              const Text('POINTS AVAILABLE', style: TextStyle(color: _textSec, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ]),
          ]),
        ),
      ),

      const SizedBox(height: 24),
      const Text('REDEEM ROBUX', style: TextStyle(color: _textSec, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
      const SizedBox(height: 12),
      _buildRobuxSection(),
      const SizedBox(height: 24),
      _storeSection('Profile Borders', _frames),
      const SizedBox(height: 24),
      _storeSection('Background Themes', _bgs),
      const SizedBox(height: 80),
    ]);
  }

  Widget _storeSection(String title, List<_StoreItem> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title.toUpperCase(), style: const TextStyle(color: _textSec, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
      const SizedBox(height: 12),
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.15),
        itemCount: items.length,
        itemBuilder: (context, i) => TweenAnimationBuilder<double>(
          key: ValueKey('${title}_$i'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 350 + i * 60),
          builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child)),
          child: _storeCard(items[i]),
        ),
      ),
    ]);
  }

  Widget _storeCard(_StoreItem item) {
    final isFrame = item.type == 'frame';
    final owned = isFrame ? _unlockedFrames.contains(item.id) : false;
    final equipped = isFrame
        ? _activeFrame == item.id
        : _customBgId == item.id || (item.id == 'default' && _customBgId == null);
    final col = item.color ?? _accent;

    return Container(
      decoration: BoxDecoration(
        color: equipped ? col.withValues(alpha: 0.1) : _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: equipped ? col.withValues(alpha: 0.5) : _border, width: equipped ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _buyOrEquip(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Preview
            Row(children: [
              if (item.emoji != null)
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Colors.red, Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple])),
                  child: const Icon(Icons.color_lens_rounded, color: Colors.white, size: 20),
                )
              else if (isFrame)
                Container(width: 36, height: 36, decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: col, width: 3),
                  color: _surface,
                ), child: isFrame ? null : null)
              else
                Container(width: 36, height: 36, decoration: BoxDecoration(
                    color: col, borderRadius: BorderRadius.circular(10))),
              const Spacer(),
              if (equipped)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: col.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                  child: Text('ON', style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
            ]),
            const SizedBox(height: 12),
            Text(item.name, style: const TextStyle(color: _textPri, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 4),
            if (item.cost == 0)
              const Text('FREE', style: TextStyle(color: _accent, fontSize: 11, fontWeight: FontWeight.w900))
            else if (owned || equipped)
              const Text('OWNED', style: TextStyle(color: _textSec, fontSize: 11, fontWeight: FontWeight.w700))
            else
              Row(children: [
                const Icon(Icons.bolt_rounded, color: _gold, size: 14),
                const SizedBox(width: 4),
                Text('${item.cost} pts', style: const TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.w800)),
              ]),
          ]),
        ),
      ),
    );
  }

  // ─── Robux Redemption Section ──────────────────────────────────────────────

  Widget _buildRobuxSection() {
    const rc = Color(0xFF00B4D8);
    final canRedeem = _robloxUser != null && _selectedTierIdx >= 0 &&
        _points >= _robuxTiers[_selectedTierIdx]['points']! && !_isRedeeming;
    return TweenAnimationBuilder<double>(
      key: const ValueKey('roblox_redemption_anim'), // Prevent flicker on rebuild
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 700),
      builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [rc.withValues(alpha: 0.12), rc.withValues(alpha: 0.03)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: rc.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: rc.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.sports_esports_rounded, color: rc, size: 22)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('REDEEM ROBUX', style: TextStyle(color: Color(0xFF00B4D8), fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              const Text('Trade your points for Roblox currency', style: TextStyle(color: _textSec, fontSize: 11)),
            ]),
          ]),
          const SizedBox(height: 20),
          // Username field
          const Text('ROBLOX USERNAME', style: TextStyle(color: _textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(
              controller: _robloxController,
              style: const TextStyle(color: _textPri, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Enter Roblox username...',
                hintStyle: TextStyle(color: _textSec.withValues(alpha: 0.6)),
                filled: true, fillColor: _card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00B4D8), width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefixIcon: const Icon(Icons.person_search_rounded, color: Color(0xFF00B4D8), size: 20),
              ),
              onSubmitted: (_) => _lookupRoblox(),
            )),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _robloxLoading ? null : _lookupRoblox,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: _robloxLoading
                    ? [_border, _border] : [rc, const Color(0xFF0077B6)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _robloxLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search_rounded, color: Colors.white, size: 20),
              ),
            ),
          ]),
          // Error
          if (_robloxError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: _red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: _red.withValues(alpha: 0.4))),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded, color: _red, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_robloxError!, style: const TextStyle(color: _red, fontSize: 12, fontWeight: FontWeight.w600))),
              ]),
            ),
          ],
          // Profile card
          if (_robloxUser != null) ...[
            const SizedBox(height: 14),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              builder: (_, v, child) => Opacity(opacity: v, child: Transform.scale(scale: 0.85 + 0.15 * v, child: child)),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _surface, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: rc.withValues(alpha: 0.5)),
                  boxShadow: [BoxShadow(color: rc.withValues(alpha: 0.15), blurRadius: 16)],
                ),
                child: Row(children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: rc, width: 2), color: _card),
                    clipBehavior: Clip.antiAlias,
                    child: (_robloxUser!['avatarUrl'] as String).isNotEmpty
                      ? Image.network(_robloxUser!['avatarUrl'] as String, fit: BoxFit.cover,
                          errorBuilder: (_, __, _e) => const Icon(Icons.person_rounded, color: _textSec, size: 28))
                      : const Icon(Icons.person_rounded, color: _textSec, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('VERIFIED ✓', style: TextStyle(color: Color(0xFF00B4D8), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    const SizedBox(height: 2),
                    Text(_robloxUser!['name'] as String, style: const TextStyle(color: _textPri, fontSize: 16, fontWeight: FontWeight.w800)),
                    Text('ID: ${_robloxUser!['id']}', style: TextStyle(color: _textSec.withValues(alpha: 0.7), fontSize: 11)),
                  ])),
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF00B4D8), size: 24),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 20),
          // Tiers
          const Text('SELECT TIER', style: TextStyle(color: _textSec, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 10),
          Row(children: List.generate(_robuxTiers.length, (i) {
            final tier = _robuxTiers[i];
            final pts   = tier['points']!;
            final robux = tier['robux']!;
            final sel   = _selectedTierIdx == i;
            final afford = _points >= pts;
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _selectedTierIdx = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: sel ? LinearGradient(colors: [rc.withValues(alpha: 0.25), rc.withValues(alpha: 0.08)]) : null,
                  color: sel ? null : _card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: sel ? rc : _border, width: sel ? 2 : 1),
                  boxShadow: sel ? [BoxShadow(color: rc.withValues(alpha: 0.3), blurRadius: 12)] : [],
                ),
                child: Column(children: [
                  Text('R\$', style: TextStyle(color: sel ? rc : _textSec, fontSize: 10, fontWeight: FontWeight.w900)),
                  Text('$robux', style: TextStyle(color: sel ? rc : _textPri, fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    decoration: BoxDecoration(color: (afford ? _gold : _red).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.bolt_rounded, color: _gold, size: 12),
                      const SizedBox(width: 4),
                      Text('$pts pts', style: TextStyle(color: afford ? _gold : _red, fontSize: 9, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ]),
              ),
            ));
          })),
          const SizedBox(height: 16),
          // AnimatedSwitcher toggles between redeem button and success card
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            switchInCurve: Curves.elasticOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: Tween<double>(begin: 0.7, end: 1.0).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: _redeemSuccess
                // ── SUCCESS CARD ──────────────────────────────────────────
                ? Container(
                    key: const ValueKey('success'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [_accent.withValues(alpha: 0.25), _accent.withValues(alpha: 0.06)]),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _accent.withValues(alpha: 0.7), width: 1.5),
                      boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 8))],
                    ),
                    child: Column(children: [
                      const Icon(Icons.check_circle_rounded, color: _accent, size: 64),
                      const SizedBox(height: 10),
                      const Text('REWARD GRANTED!', style: TextStyle(color: _accent, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      const Text('Your Robux request has been submitted!', style: TextStyle(color: _textPri, fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _gold.withValues(alpha: 0.35)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.schedule_rounded, color: _gold, size: 16),
                          const SizedBox(width: 6),
                          const Text('Robux will arrive in 3–7 business days', style: TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () => setState(() { _redeemSuccess = false; _robloxUser = null; _robloxController.clear(); _selectedTierIdx = -1; _robloxError = null; }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                          decoration: BoxDecoration(color: _accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: _accent.withValues(alpha: 0.5))),
                          child: const Text('Redeem Again', style: TextStyle(color: _accent, fontWeight: FontWeight.w800, fontSize: 14)),
                        ),
                      ),
                    ]),
                  )
                // ── REDEEM BUTTON ─────────────────────────────────────────
                : SizedBox(
                    key: const ValueKey('redeem'),
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: canRedeem ? () => setState(() => _awaitingAwesome = true) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: canRedeem ? const LinearGradient(colors: [Color(0xFF00B4D8), Color(0xFF0077B6)]) : null,
                          color: canRedeem ? null : _border,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: canRedeem ? [BoxShadow(color: rc.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 6))] : [],
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.redeem_rounded, color: canRedeem && !_isRedeeming ? Colors.white : _textSec, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            _isRedeeming ? 'PROCESSING...'
                              : _selectedTierIdx < 0 ? 'SELECT A TIER'
                              : _robloxUser == null ? 'ENTER USERNAME FIRST'
                              : !canRedeem ? 'NOT ENOUGH POINTS' : 'REDEEM NOW',
                            style: TextStyle(color: canRedeem && !_isRedeeming ? Colors.white : _textSec, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                          ),
                        ]),
                      ),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  // ─── Profile Tab ───────────────────────────────────────────────────────────

  Widget _buildProfileTab() {
    return ListView(padding: const EdgeInsets.all(24), children: [
      Center(child: Stack(clipBehavior: Clip.none, children: [
        _avatar(56, email: _myEmail, url: _profileUrl, b64: _profileB64, frame: _activeFrame, online: true),
        Positioned(right: -4, bottom: -4, child: GestureDetector(
          onTap: _pickProfilePhoto,
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: _accent, shape: BoxShape.circle, border: Border.all(color: _bg, width: 2)),
            child: const Icon(Icons.camera_alt_rounded, color: Colors.black, size: 18),
          ),
        )),
      ])),
      const SizedBox(height: 16),
      Text(_userName, textAlign: TextAlign.center, style: const TextStyle(color: _textPri, fontSize: 26, fontWeight: FontWeight.w900)),
      Text(_myEmail, textAlign: TextAlign.center, style: const TextStyle(color: _textSec, fontSize: 13)),
      const SizedBox(height: 8),
      Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: _gold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _gold.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.bolt_rounded, color: _gold, size: 18),
          const SizedBox(width: 6),
          Text('$_points pts', style: const TextStyle(color: _gold, fontWeight: FontWeight.w900)),
        ]),
      )),
      const SizedBox(height: 32),
      _profileAction('Change Background', Icons.wallpaper_rounded, _pickBg),
      _profileAction('Customize in Store', Icons.store_rounded, () => _tabController.animateTo(1)),
      
      if (js.context.hasProperty('isPwaInstallable') && js.context.callMethod('isPwaInstallable') == true)
        _profileAction('Install App', Icons.download_rounded, () {
          js.context.callMethod('triggerPwaInstall');
          // Optimistically hide the button after a moment
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() {});
          });
        }),
      if (_profileB64 != null)
        _profileAction('Remove Profile Photo', Icons.no_accounts_rounded, () async {
          await FirebaseFirestore.instance.collection('users').doc(_myUid).update({'profileImageBase64': ''});
          await CacheService.saveProfilePhoto(null);
          setState(() => _profileB64 = null);
        }),
      _profileAction('Sign Out', Icons.logout_rounded, () async {
        await FirebaseFirestore.instance.collection('users').doc(_myUid).update({'isOnline': false});
        await CacheService.clearAll();
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
      }, red: true),
    ]);
  }

  Widget _profileAction(String label, IconData ic, VoidCallback tap, {bool red = false}) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: _card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: red ? _red.withValues(alpha: 0.25) : _border),
        ),
        child: Row(children: [
          Icon(ic, color: red ? _red : _accent, size: 21),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(color: red ? _red : _textPri, fontWeight: FontWeight.w700)),
          const Spacer(),
          Icon(Icons.chevron_right_rounded, color: _textSec, size: 20),
        ]),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bgCol = _bgColor();
    return Scaffold(
      backgroundColor: bgCol,
      body: Stack(children: [
        // Custom BG image
        if (_cachedBg != null)
          Positioned.fill(child: Opacity(opacity: 0.15, child: Image.memory(base64Decode(_cachedBg!), fit: BoxFit.cover))),

        // Dot grid
        Positioned.fill(child: CustomPaint(painter: _DotGridPainter(bgCol))),

        SafeArea(
          child: Column(children: [
            // App bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.recycling_rounded, color: _accent, size: 22),
                ),
                const SizedBox(width: 10),
                const Text('HYDRA BIN', style: TextStyle(color: _textPri, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const Spacer(),
                GestureDetector(
                  onTap: () => _tabController.animateTo(2),
                  child: _avatar(18, email: _myEmail, url: _profileUrl, b64: _profileB64, frame: _activeFrame, online: true),
                ),
              ]),
            ),

            // Tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(color: _accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: _accent.withValues(alpha: 0.4))),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: _accent, unselectedLabelColor: _textSec,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Dashboard'),
                  Tab(text: 'Store'),
                  Tab(text: 'Profile'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Expanded(child: TabBarView(
              controller: _tabController,
              children: [_buildHomeTab(), _buildStoreTab(), _buildProfileTab()],
            )),
          ]),
        ),

        // Redemption Confirm overlay
        if (_awaitingAwesome)
          GestureDetector(
            onTap: () => setState(() => _awaitingAwesome = false),
            child: Container(
              color: Colors.black.withValues(alpha: 0.88),
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: Color(0xFF22C55E), size: 48),
                ),
                const SizedBox(height: 20),
                const Text('CONFIRM REDEMPTION', style: TextStyle(color: Color(0xFF22C55E), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Trade ${_robuxTiers[_selectedTierIdx]['points']} pts for ${_robuxTiers[_selectedTierIdx]['robux']} R\$?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFF0F4FF), fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('Your recycling makes a difference!', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                    SizedBox(width: 6),
                    Icon(Icons.eco_rounded, color: Color(0xFF22C55E), size: 16),
                  ]),
                ),
                const SizedBox(height: 28),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  GestureDetector(
                    onTap: () => setState(() => _awaitingAwesome = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _border),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: _textSec, fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () {
                      setState(() => _awaitingAwesome = false);
                      _redeemRobux();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF15803D)]),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: const Color(0xFF22C55E).withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: const Text('Confirm?', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                ]),
              ])),
            ),
          ),

        if (_confetti)
          GestureDetector(
            onTap: () => setState(() => _confetti = false),
            child: Container(
              color: Colors.black.withValues(alpha: 0.85),
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.celebration_rounded, color: _accent, size: 90),
                const SizedBox(height: 16),
                const Text('POINTS EARNED!', style: TextStyle(color: _textPri, fontSize: 32, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text('Your recycling makes a difference!', style: TextStyle(color: _textSec)),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () => setState(() => _confetti = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(16)),
                    child: const Text('Awesome!', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                ),
              ])),
            ),
          ),
      ]),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final Color base;
  const _DotGridPainter(this.base);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.035);
    for (double x = 0; x < size.width; x += 32) {
      for (double y = 0; y < size.height; y += 32) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }
  @override
  bool shouldRepaint(_DotGridPainter old) => old.base != base;
}



import os

file_content = """import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:hydra_bin/models/leaderboard_item.dart';
import 'package:hydra_bin/screens/auth_screen.dart';
import 'package:hydra_bin/screens/connect_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  StreamSubscription<DocumentSnapshot>? _userSubscription;
  StreamSubscription<QuerySnapshot>? _leaderboardSubscription;
  StreamSubscription<DocumentSnapshot>? _announcementSubscription;

  int _points = 0;
  int? _lastPoints;
  int _streak = 0;
  String _activeTheme = 'Dark Mode';
  String _activeFrame = 'Default';
  List<String> _unlockedThemes = ['Dark Mode'];
  List<String> _unlockedFrames = ['Default'];
  String _userName = 'User';

  List<LeaderboardItem> _leaderboard = [];
  String? _leaderboardError;
  String? _pointsError;
  bool _showCelebration = false;
  
  String? _announcementText;
  
  final Map<String, int> _themePrices = {
    'Dark Mode': 0,
    'Forest Green': 50,
    'Ocean Blue': 50,
  };
  
  final Map<String, int> _framePrices = {
    'Default': 0,
    'Bronze': 20,
    'Silver': 50,
    'Gold': 100,
  };

  @override
  void initState() {
    super.initState();
    _setupFCM();
    _listenToUser();
    _listenToLeaderboard();
    _listenToAnnouncements();
  }

  Future<void> _setupFCM() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && token != null) {
        FirebaseFirestore.instance.collection('users').doc(uid).update({
          'fcmToken': token,
        });
      }
    } catch (e) {
      debugPrint("FCM Error: $e");
    }
  }

  void _listenToAnnouncements() {
    _announcementSubscription = FirebaseFirestore.instance
        .collection('system')
        .doc('announcements')
        .snapshots()
        .listen((snap) {
          if (snap.exists && mounted) {
            final data = snap.data();
            setState(() {
              _announcementText = data?['text'] as String?;
            });
          } else if (mounted) {
            setState(() {
               _announcementText = null;
            });
          }
        }, onError: (e) {
            debugPrint("Announcement error: $e");
        });
  }

  void _listenToUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
          (snap) {
            if (!snap.exists || !mounted) return;
            
            final data = snap.data()!;
            final newPoints = (data['points'] as num?)?.toInt() ?? 0;
            final streak = (data['streak'] as num?)?.toInt() ?? 0;
            final theme = data['activeTheme'] as String? ?? 'Dark Mode';
            final frame = data['activeFrame'] as String? ?? 'Default';
            final uThemes = List<String>.from(data['unlockedThemes'] ?? ['Dark Mode']);
            final uFrames = List<String>.from(data['unlockedFrames'] ?? ['Default']);
            final name = data['name'] as String? ?? 'User';

            if (_lastPoints != null && newPoints > _lastPoints!) {
              final delta = newPoints - _lastPoints!;
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('You earned +$delta points!'),
                    backgroundColor: Colors.green,
                  ),
                );
                setState(() => _showCelebration = true);
                
                if (delta > 0 && delta <= 100) {
                     FirebaseFirestore.instance
                         .collection('users')
                         .doc(uid)
                         .collection('recent_activity')
                         .add({
                           'title': 'Points Earned',
                           'description': 'Recycle complete! +$delta points added.',
                           'points': delta,
                           'timestamp': FieldValue.serverTimestamp(),
                         });
                }
              }
            }

            _lastPoints = newPoints;

            if (mounted) {
              setState(() {
                _points = newPoints;
                _streak = streak;
                _activeTheme = theme;
                _activeFrame = frame;
                _unlockedThemes = uThemes;
                _unlockedFrames = uFrames;
                _userName = name;
                _pointsError = null;
              });
            }
          },
          onError: (e) {
            if (!mounted) return;
            setState(() => _pointsError = e.toString());
          },
        );
  }

  void _listenToLeaderboard() {
    _leaderboardSubscription = FirebaseFirestore.instance
        .collection('users')
        .orderBy('points', descending: true)
        .snapshots()
        .listen(
          (snap) {
            final validUsers = snap.docs.where((doc) {
              final data = doc.data();
              final name = data['name'] as String?;
              final points = (data['points'] as num?)?.toInt() ?? 0;
              return name != null && name.isNotEmpty && points > 0;
            }).toList();

            validUsers.sort((a, b) {
              final aPoints = (a.data()['points'] as num?)?.toInt() ?? 0;
              final bPoints = (b.data()['points'] as num?)?.toInt() ?? 0;
              if (aPoints != bPoints) return bPoints.compareTo(aPoints);
              
              final aTime = a.data()['updatedAt'] as Timestamp?;
              final bTime = b.data()['updatedAt'] as Timestamp?;
              if (aTime != null && bTime != null) {
                return aTime.compareTo(bTime);
              } else if (aTime != null) return -1;
              else if (bTime != null) return 1;

              final aName = a.data()['name'] as String? ?? '';
              final bName = b.data()['name'] as String? ?? '';
              return aName.compareTo(bName);
            });

            final list = validUsers.asMap().entries.map((e) {
              final d = e.value.data();
              return LeaderboardItem(
                rank: e.key + 1,
                name: d['name'] as String? ?? 'Player ${e.key + 1}',
                points: (d['points'] as num?)?.toInt() ?? 0,
              );
            }).toList();

            if (mounted) {
              setState(() {
                _leaderboard = list;
                _leaderboardError = null;
              });
            }
          },
          onError: (e) {
            if (!mounted) return;
            setState(() => _leaderboardError = 'Failed to load leaderboard: ${e.toString()}');
          },
        );
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _leaderboardSubscription?.cancel();
    _announcementSubscription?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Map<String, dynamic> _getRankDetails(int points) {
    if (points <= 100) return {'title': 'Eco-Novice', 'icon': Icons.eco, 'color': Colors.green.shade300};
    if (points <= 250) return {'title': 'Litter Literate', 'icon': Icons.spa, 'color': Colors.green.shade400};
    if (points <= 450) return {'title': 'Green Guardian', 'icon': Icons.recycling, 'color': Colors.green.shade500};
    if (points <= 700) return {'title': 'Sustainability Scout', 'icon': Icons.park, 'color': Colors.green.shade600};
    if (points <= 900) return {'title': 'Waste Warrior', 'icon': Icons.shield, 'color': Colors.green.shade700};
    if (points <= 1000) return {'title': 'Eco-Elite', 'icon': Icons.public, 'color': Colors.green.shade800};
    return {'title': 'Planet Architect', 'icon': Icons.emoji_events, 'color': Colors.amber};
  }

  Color _getFrameColor(String frame) {
    switch(frame) {
      case 'Gold': return Colors.amber;
      case 'Silver': return Colors.grey.shade300;
      case 'Bronze': return Colors.brown.shade400;
      default: return Colors.transparent;
    }
  }

  Future<void> _buyTheme(String theme, int price) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_points < price) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Not enough points!'), backgroundColor: Colors.red),
        );
        return;
    }
    
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'points': FieldValue.increment(-price),
        'unlockedThemes': FieldValue.arrayUnion([theme]),
        'activeTheme': theme,
    });
    
    await FirebaseFirestore.instance.collection('users').doc(uid).collection('recent_activity').add({
       'title': 'Purchased Theme',
       'description': 'Unlocked $theme theme.',
       'points': -price,
       'timestamp': FieldValue.serverTimestamp(),
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unlocked $theme!'), backgroundColor: Colors.green),
    );
  }
  
  Future<void> _buyFrame(String frame, int price) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_points < price) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Not enough points!'), backgroundColor: Colors.red),
        );
        return;
    }
    
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'points': FieldValue.increment(-price),
        'unlockedFrames': FieldValue.arrayUnion([frame]),
        'activeFrame': frame,
    });
    
    await FirebaseFirestore.instance.collection('users').doc(uid).collection('recent_activity').add({
       'title': 'Purchased Frame',
       'description': 'Unlocked $frame frame.',
       'points': -price,
       'timestamp': FieldValue.serverTimestamp(),
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unlocked $frame!'), backgroundColor: Colors.green),
    );
  }
  
  Future<void> _setTheme(String theme) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({'activeTheme': theme});
  }

  Future<void> _setFrame(String frame) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({'activeFrame': frame});
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_announcementText != null && _announcementText!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.campaign, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _announcementText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Points', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('$_points', style: Theme.of(context).textTheme.displaySmall),
                  if (_pointsError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Points listener error: $_pointsError',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConnectScreen()),
            ),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Connect to Smart Bin'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
          const SizedBox(height: 24),
          Text('Leaderboard', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_leaderboardError != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Error: $_leaderboardError', style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
            ),
          ..._leaderboard.map((e) {
            final rankDetails = _getRankDetails(e.points);
            Color bgColor = Theme.of(context).cardColor;
            Color rankColor = Colors.grey;
            Widget? trailingWidget;

            if (e.rank == 1) {
              bgColor = Colors.amber.shade900.withOpacity(0.2);
              rankColor = Colors.amber;
              trailingWidget = const Icon(Icons.star, color: Colors.amber);
            } else if (e.rank == 2) {
              bgColor = Colors.grey.shade400.withOpacity(0.2);
              rankColor = Colors.grey.shade400;
            } else if (e.rank == 3) {
              bgColor = Colors.brown.shade400.withOpacity(0.2);
              rankColor = Colors.brown.shade400;
            } else {
              bgColor = Colors.grey.shade900;
              rankColor = Colors.grey.shade600;
            }

            return Card(
              color: bgColor,
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
              elevation: e.rank <= 3 ? 2 : 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: e.rank <= 3 ? BorderSide(color: rankColor.withOpacity(0.5), width: 1) : BorderSide.none,
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: rankColor.withOpacity(0.2),
                  foregroundColor: rankColor,
                  child: Text('${e.rank}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                title: Text(e.name, style: TextStyle(fontWeight: e.rank <= 3 ? FontWeight.bold : FontWeight.normal)),
                subtitle: Row(
                  children: [
                    Icon(rankDetails['icon'], size: 14, color: rankDetails['color']),
                    const SizedBox(width: 4),
                    Text(rankDetails['title'], style: TextStyle(color: rankDetails['color'], fontSize: 12)),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${e.points} pts', style: TextStyle(fontWeight: FontWeight.bold, color: rankColor, fontSize: 16)),
                    if (trailingWidget != null) trailingWidget,
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _getFrameColor(_activeFrame),
                  width: _activeFrame == 'Default' ? 0 : 4,
                ),
                gradient: _activeFrame == 'Default' ? null : LinearGradient(
                  colors: [
                    _getFrameColor(_activeFrame),
                    _getFrameColor(_activeFrame).withOpacity(0.5),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: CircleAvatar(
                radius: 40,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  _userName.isNotEmpty ? _userName[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _userName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          if (_streak >= 7)
            Center(
              child: Chip(
                avatar: const Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
                label: Text('$_streak Day Streak!'),
                backgroundColor: Colors.orange.withOpacity(0.2),
                side: const BorderSide(color: Colors.orange),
              ),
            )
          else
            Center(
              child: Chip(
                avatar: const Icon(Icons.calendar_today, size: 16),
                label: Text('$_streak Day Streak'),
              ),
            ),
          const SizedBox(height: 24),
          Text('Customize', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                const ListTile(title: Text('Themes', style: TextStyle(fontWeight: FontWeight.bold))),
                ..._themePrices.entries.map((e) {
                  final theme = e.key;
                  final price = e.value;
                  final isUnlocked = _unlockedThemes.contains(theme);
                  final isActive = _activeTheme == theme;
                  
                  return ListTile(
                    title: Text(theme),
                    trailing: isActive ? const Icon(Icons.check_circle, color: Colors.green) :
                              isUnlocked ? FilledButton.tonal(
                                onPressed: () => _setTheme(theme),
                                child: const Text('Equip')
                              ) :
                              FilledButton(
                                onPressed: () => _buyTheme(theme, price),
                                child: Text('$price pts')
                              ),
                  );
                }),
                const Divider(),
                const ListTile(title: Text('Avatar Frames', style: TextStyle(fontWeight: FontWeight.bold))),
                ..._framePrices.entries.map((e) {
                  final frame = e.key;
                  final price = e.value;
                  final isUnlocked = _unlockedFrames.contains(frame);
                  final isActive = _activeFrame == frame;
                  
                  return ListTile(
                    title: Text(frame),
                    trailing: isActive ? const Icon(Icons.check_circle, color: Colors.green) :
                              isUnlocked ? FilledButton.tonal(
                                onPressed: () => _setFrame(frame),
                                child: const Text('Equip')
                              ) :
                              FilledButton(
                                onPressed: () => _buyFrame(frame, price),
                                child: Text('$price pts')
                              ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Recent Activity', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser?.uid)
                .collection('recent_activity')
                .orderBy('timestamp', descending: true)
                .limit(10)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No recent activity.', textAlign: TextAlign.center),
                  ),
                );
              }
              return Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final d = docs[index].data() as Map<String, dynamic>;
                    final pts = (d['points'] as num?)?.toInt() ?? 0;
                    final title = d['title'] as String? ?? 'Activity';
                    final desc = d['description'] as String? ?? '';
                    final ts = d['timestamp'] as Timestamp?;
                    
                    String dateStr = '';
                    if (ts != null) {
                      final dt = ts.toDate();
                      dateStr = '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                    }
                    
                    return ListTile(
                      title: Text(title),
                      subtitle: Text('$desc\n$dateStr'),
                      trailing: Text(
                        pts > 0 ? '+$pts' : '$pts',
                        style: TextStyle(
                           color: pts > 0 ? Colors.green : Colors.red,
                           fontWeight: FontWeight.bold,
                           fontSize: 16,
                        ),
                      ),
                      isThreeLine: true,
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hydra Bin V2'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Stack(
        children: [
          _currentIndex == 0 ? _buildHomeTab() : _buildProfileTab(),
          if (_showCelebration)
            GestureDetector(
              onTap: () => setState(() => _showCelebration = false),
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.celebration, size: 64, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 16),
                          Text('Points earned!', style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          Text('Tap to dismiss', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
"""

with open(r"c:\Users\Lorna C. Caballero\Desktop\Hydra Bin\lib\screens\home_screen.dart", "w", encoding="utf-8") as f:
    f.write(file_content)

print("Successfully wrote home_screen.dart")

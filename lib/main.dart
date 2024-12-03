import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'dart:math';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(MaterialApp(home: ToiletLocatorApp()));
}

class ToiletLocatorApp extends StatefulWidget {
  @override
  _ToiletLocatorAppState createState() => _ToiletLocatorAppState();
}

class _ToiletLocatorAppState extends State<ToiletLocatorApp> {
  late GoogleMapController mapController;
  final LatLng _initialCenter = const LatLng(35.6895, 139.6917);
  final Set<Marker> _markers = {};
  LatLng? _currentPosition;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  // 現在地の取得
  Future<void> _getCurrentLocation() async {
  try {
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);

      // 現在地のマーカーを追加
      _markers.add(
        Marker(
          markerId: MarkerId('current_location'),
          position: _currentPosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: '現在地',
          ),
        ),
      );
    });
    _loadToilets(); // 他のトイレマーカーをロード
  } catch (e) {
    print("現在地を取得できませんでした: $e");
  }
}

  // Firestoreからトイレデータを取得してマーカーを設定
  Future<void> _loadToilets() async {
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    QuerySnapshot snapshot = await firestore.collection('toilets').get();

    setState(() {
      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        _markers.add(
          Marker( 
            markerId: MarkerId(doc.id),
            position: LatLng(data['latitude'], data['longitude']),
            infoWindow: InfoWindow(
              title: data['name'],
              snippet: data['openHours'],
            ),
            onTap: () => _showToiletDetails(data),
          ),
        );
      }
    });
  }

  // トイレ詳細情報を新しいページで表示
  void _showToiletDetails(Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ToiletDetailPage(toiletData: data),
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('トイレマップ'),
        actions: [
          IconButton(
            icon: Icon(Icons.filter_list),
            onPressed: () {
              // フィルタリングダイアログを表示
              showDialog(
                context: context,
                builder: (context) => FilterDialog(onFilterApply: _applyFilter),
              );
            },
          ),
        ],
      ),
      body: _currentPosition == null
          ? Center(child: CircularProgressIndicator())
          : GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: _currentPosition!,
                zoom: 16.0,
              ),
              markers: _markers,
            ),
    );
  }

  void _applyFilter(bool isAccessible, bool hasBabyChanging) {
    setState(() {
      // Firestoreクエリでフィルタリング（例: バリアフリー対応）
_markers.removeWhere((marker) {
  var data = _getMarkerDataById(marker.markerId.value);

  var isAccessible = data['isAccessible'] ?? false;
  var hasBabyChanging = data['hasBabyChanging'] ?? false;

  return (isAccessible && !(isAccessible as bool)) ||
         (hasBabyChanging && !(hasBabyChanging as bool));
});

    });
  }
}

// トイレ詳細ページ
class ToiletDetailPage extends StatelessWidget {
  final Map<String, dynamic> toiletData;

  ToiletDetailPage({required this.toiletData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(toiletData['name']),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('説明: ${toiletData['description']}', style: TextStyle(fontSize: 16)),
            SizedBox(height: 10),
            Text('バリアフリー: ${toiletData['isAccessible'] ? 'はい' : 'いいえ'}'),
            Text('オムツ替え台: ${toiletData['hasBabyChanging'] ? 'あり' : 'なし'}'),
            Text('営業時間: ${toiletData['openHours']}'),
            SizedBox(height: 20),
            Expanded(
              child: ReviewSection(toiletId: toiletData['id']),
            ),
          ],
        ),
      ),
    );
  }
}

// レビューページ
class ReviewSection extends StatelessWidget {
  final String toiletId;

  ReviewSection({required this.toiletId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('toiletId', isEqualTo: toiletId)
          .snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();
        return ListView(
          children: snapshot.data!.docs.map((doc) {
            return ListTile(
              title: Text('評価: ${doc['rating']}'),
              subtitle: Text(doc['comment']),
            );
          }).toList(),
        );
      },
    );
  }
}

// フィルタリングダイアログ
class FilterDialog extends StatelessWidget {
  final Function(bool, bool) onFilterApply;

  FilterDialog({required this.onFilterApply});

  @override
  Widget build(BuildContext context) {
    bool isAccessible = false;
    bool hasBabyChanging = false;

    return AlertDialog(
      title: Text('フィルタリング'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            title: Text('バリアフリー対応'),
            value: isAccessible,
            onChanged: (value) {
              isAccessible = value!;
            },
          ),
          CheckboxListTile(
            title: Text('オムツ替え台あり'),
            value: hasBabyChanging,
            onChanged: (value) {
              hasBabyChanging = value!;
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text('キャンセル'),
        ),
        TextButton(
          onPressed: () {
            onFilterApply(isAccessible, hasBabyChanging);
            Navigator.pop(context);
          },
          child: Text('適用'),
        ),
      ],
    );
  }
}

Map<String, dynamic> _getMarkerDataById(String id) {
  // Firestoreなどからデータを取得するロジックを追加
  // 以下は仮のデータ取得例
  return {
    "isAccessible": true,
    "hasBabyChanging": false,
    "openHours": "24時間営業",
    "name": "駅前トイレ",
  };
}


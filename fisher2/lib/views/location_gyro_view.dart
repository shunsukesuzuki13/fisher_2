import 'dart:async';
import 'dart:math';
import 'dart:io' as io;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:flutter/material.dart';
import 'package:location/location.dart' as loc;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:logging/logging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:fisher2/plugins/google_sign_in_plugin.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationGyroView extends StatefulWidget {
  const LocationGyroView({super.key, required this.title});

  final String title;

  @override
  State<LocationGyroView> createState() => _LocationGyroViewState();

  static Future<loc.LocationData?> getLocationData() async {
    final location = loc.Location();
    try {
      return await location.getLocation();
    } catch (e) {
      Logger('LocationGyroView').severe('位置情報の取得中にエラーが発生しました', e);
      return null;
    }
  }

  static Future<GyroscopeEvent?> getGyroData() async {
    try {
      return await gyroscopeEventStream().first;
    } catch (e) {
      Logger('LocationGyroView').severe('ジャイロデータの取得中にエラーが発生しました', e);
      return null;
    }
  }

  static Future<void> uploadToGoogleDrive(
      io.File file, AuthClient authClient, String folderID) async {
    try {
      final driveApi = drive.DriveApi(authClient);
      final driveFile = drive.File();

      final dateFormat = DateFormat('yyyy-MM-dd_HH-mm-ss');
      final formattedDate = dateFormat.format(DateTime.now());
      driveFile.name = 'DriveSampleUploadTest_$formattedDate.txt';
      driveFile.parents = [folderID];

      final response = await driveApi.files.create(
        driveFile,
        uploadMedia: drive.Media(file.openRead(), file.lengthSync()),
      );

      Logger('LocationGyroView').info('ファイルのアップロードに成功しました: ${response.id}');
    } catch (e, stackTrace) {
      Logger('LocationGyroView')
          .severe('Google Driveへのアップロード中にエラーが発生しました', e, stackTrace);
      if (e is Exception) {
        Logger('LocationGyroView').severe('APIリクエストエラー: ${e.toString()}');
      } else {
        Logger('LocationGyroView').severe('予期しないエラー: $e');
      }
    }
  }
}

class _LocationGyroViewState extends State<LocationGyroView> {
  loc.LocationData? _currentLocation;
  loc.LocationData? _previousLocation;
  GyroscopeEvent? _currentGyroData;
  Timer? _timer;
  final loc.Location location = loc.Location();
  final Logger _logger = Logger('LocationGyroView');
  bool _isLoggingSetup = false;
  DateTime? _startTime;
  DateTime? _endTime;
  double _totalDistance = 0.0;
  AuthClient? _authClient;
  final List<loc.LocationData> _locationDataList = [];
  
  @override
  void initState() {
    super.initState();
    _setupLogging();
    _requestPermissions();
  }

  void _setupLogging() {
    if (!_isLoggingSetup) {
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        if (record.loggerName == 'LocationGyroView' &&
            record.message.contains('アップロード')) {
          if (record.level == Level.SEVERE) {
            _logger.severe(
                '${record.level.name}: ${record.time}: ${record.message}');
          } else if (record.level == Level.WARNING) {
            _logger.warning(
                '${record.level.name}: ${record.time}: ${record.message}');
          } else {
            _logger.info(
                '${record.level.name}: ${record.time}: ${record.message}');
          }
        }
      });
      _isLoggingSetup = true;
    }
  }

  Future<void> _saveDataLocally(String data) async {
    try {
      // ダウンロードフォルダのパスを取得
      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      // 現在の日付を取得してフォーマット
      final now = DateTime.now();
      final formattedDate = DateFormat('yyyyMMdd_HHmmss').format(now);

      // 日付を含むファイルパスを作成
      final path = '${directory.path}/$formattedDate.txt';
      final file = File(path);

      // ディレクトリが存在しない場合は作成
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }

      // データをファイルに書き込む
      await file.writeAsString(data);

      // スナックバーで保存完了を通知
      _showErrorSnackBar('データがローカルストレージに保存されました: ${file.path}');
    } catch (e) {
      _showErrorSnackBar('データの保存中にエラーが発生しました: $e');
    }
  }

  Future<void> _saveDataToFile() async {
    await _requestPermissions(); // パーミッションをリクエスト

    try {
      // 計測時間を計算
      final duration = _endTime!.difference(_startTime!);
      final formattedDuration =
          (duration.inSeconds / 60).toStringAsFixed(2); // 分単位に変換
      final formattedDistance = _totalDistance.toStringAsFixed(2);

      // 保存するデータを準備
      final data = '''
Measurement Duration: $formattedDuration minutes
Total Distance: $formattedDistance meters
Current Location: ${_currentLocation?.toString()}
Previous Location: ${_previousLocation?.toString()}
Current Gyro Data: ${_currentGyroData?.toString()}
Location Data List: ${_locationDataList.map((loc) => loc.toString()).join('\n')}
''';

      // データをローカルストレージに保存
      await _saveDataLocally(data);
    } catch (e) {
      _logger.severe('データの保存中にエラーが発生しました: $e');
      _showErrorSnackBar('データの保存中にエラーが発生しました: $e ここまで通りました');
    }
  }

  Future<void> _requestPermissions() async {
    try {
      _logger.info('権限リクエストを開始します');

      // 位置情報の権限をリクエスト
      final status = await perm.Permission.location.request();

      // 権限が付与されていない場合
      if (status != perm.PermissionStatus.granted) {
        _showErrorSnackBar('位置情報の権限が付与されていません');
      } else {
        _logger.info('位置情報の権限が付与されました');

        // 位置情報の権限をリクエスト
        await location.requestPermission();
        _logger.info('位置情報の権限がリクエストされました');

        // バックグラウンドモードを有効にする
        await location.enableBackgroundMode(enable: true);
        _logger.info('バックグラウンドモードが有効になりました');
        // 位置情報の更新間隔を設定
        location.changeSettings(interval: 10000); // 10秒ごとに更新
        _logger.info('位置情報の更新間隔が設定されました');
      }
    } catch (e) {
      _logger.info('権限のリクエスト中にエラーが発生しました: $e');
    }
  }

  void _startLocationAndGyroData() {
    _startTime = DateTime.now();
    _totalDistance = 0.0;
    _locationDataList.clear(); // リストをクリア
    _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final locationData = await LocationGyroView.getLocationData();
      final gyroData = await LocationGyroView.getGyroData();
      setState(() {
        if (_previousLocation != null && locationData != null) {
          _totalDistance +=
              _calculateDistance(_previousLocation!, locationData);
        }
        _previousLocation = locationData;
        _currentLocation = locationData;
        _currentGyroData = gyroData;
        if (locationData != null) {
          _locationDataList.add(locationData); // 位置データをリストに追加
        }
      });
    });
  }

  void _stopLocationAndGyroData() {
    if (_timer == null || !_timer!.isActive) {
      return;
    }
    _endTime = DateTime.now();
    _timer?.cancel();
    _showSummary();
    _saveDataToFile(); // データを保存する
  }

  double _calculateDistance(loc.LocationData start, loc.LocationData end) {
    const double earthRadius = 6371000; // メートル
    final double dLat = _degreesToRadians(end.latitude! - start.latitude!);
    final double dLon = _degreesToRadians(end.longitude! - start.longitude!);
    final double a = (sin(dLat / 2) * sin(dLat / 2)) +
        (cos(_degreesToRadians(start.latitude!)) *
            cos(_degreesToRadians(end.latitude!)) *
            sin(dLon / 2) *
            sin(dLon / 2));
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  void _handleError(String message, [dynamic error]) {
    _logger.severe(message, error);
    _showErrorSnackBar(message);
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showSummary() async {
    _logger.info('サマリー表示を開始します');

    final duration = _endTime!.difference(_startTime!);
    final summary =
        '開始時刻: $_startTime\n終了時刻: $_endTime\n移動距離: $_totalDistance メートル\n経過時間: ${duration.inSeconds} 秒';
    _showErrorSnackBar(summary);

    final directory = await getApplicationDocumentsDirectory();
    final file = io.File('${directory.path}/summary.txt');
    await file.writeAsString(summary);

    // ファイルの存在を確認
    if (await file.exists()) {
      try {
        // アップロードを試行
        await LocationGyroView.uploadToGoogleDrive(
            file, _authClient!, "0AIbRNZKDNmrIUk9PVA");
        _showErrorSnackBar('ファイルがアップロードされました');
      } catch (e) {
        _logger.info('ファイルのアップロード中にエラーが発生しました: $e');
      }
    }
  }

  Future<void> _onSignIn(GoogleSignInAccount? account) async {
    if (account == null) {
      _handleError('Googleサインインに失敗しました');
      return;
    }

    try {
      final authHeaders = await account.authHeaders;
      _logger.info('authHeaders: $authHeaders'); // 追加: authHeadersの内容をログに出力

      final authClient = authenticatedClient(
          http.Client(),
          AccessCredentials(
            AccessToken(
                authHeaders['token_type']!,
                authHeaders['access_token']!,
                DateTime.now().add(Duration(hours: 1))),
            null,
            ['https://www.googleapis.com/auth/drive.file'],
          ));

      setState(() {
        _authClient = authClient;
      });
      _logger.info('Googleサインインに成功しました');
    } catch (e, stackTrace) {
      _handleError('認証クライアントの初期化中にエラーが発生しました', e);
      _logger.severe('認証クライアントの初期化中にエラーが発生しました', e, stackTrace);
    }
  }

  @override
  void dispose() {
    _stopLocationAndGyroData();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GoogleSignInPlugin plugin = GoogleSignInPlugin();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                'Location: $_currentLocation\nGyroscope: $_currentGyroData',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            plugin.renderSignInButton(_onSignIn), // コールバック関数を渡す
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _startLocationAndGyroData,
                  child: const Text('Start'),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _stopLocationAndGyroData,
                  child: const Text('Stop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

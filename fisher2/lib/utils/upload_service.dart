import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:csv/csv.dart';
import 'package:logging/logging.dart';
//import 'package:fisher2/views/location_gyro_view.dart';

// ログ設定
final Logger _logger = Logger('UploadService');

// Google Drive APIの認証設定
final _scopes = [drive.DriveApi.driveFileScope];
final _clientId = ClientId('719937867729-plihpcoh7l3dn90ro89tgv5ap4mucvv0.apps.googleusercontent.com');

// 画像を動画に圧縮する関数
Future<File> compressImagesToVideo(List<File> images, String outputPath) async {
  String inputs = images.map((file) => '-i ${file.path}').join(' ');
  var session = await FFmpegKit.execute('-r 1 $inputs -vcodec mpeg4 $outputPath');
  var returnCode = await session.getReturnCode();

  if (ReturnCode.isSuccess(returnCode)) {
    _logger.info('Video compressed successfully: $outputPath');
  } else {
    _logger.severe('Failed to compress video');
    throw Exception('Failed to compress video');
  }
  return File(outputPath);
}

// ジャイロ情報をCSV形式に変換する関数
Future<File> convertDataToCSV(List<Map<String, dynamic>> data, String outputPath) async {
  List<List<dynamic>> rows = [];
  rows.add(data.first.keys.toList()); // ヘッダー行
  for (var row in data) {
    rows.add(row.values.toList());
  }
  String csv = const ListToCsvConverter().convert(rows);
  File file = File(outputPath);
  await file.writeAsString(csv);
  return file;
}

// Google Driveにファイルをアップロードする関数
Future<void> uploadFileToGoogleDrive(File file) async {
  final authClient = await clientViaUserConsent(_clientId, _scopes, (url) {
    // ユーザーに認証URLを表示し、認証を促す
    _logger.info('Please go to the following URL and grant access:');
    _logger.info('  => $url');
    _logger.info('');
  });

  final driveApi = drive.DriveApi(authClient);
  var media = drive.Media(file.openRead(), file.lengthSync());
  var driveFile = drive.File();
  driveFile.name = file.path.split('/').last;
  await driveApi.files.create(driveFile, uploadMedia: media);
  _logger.info('File uploaded successfully: ${file.path}');
}

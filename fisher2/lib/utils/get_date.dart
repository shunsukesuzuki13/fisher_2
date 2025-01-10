import 'package:location/location.dart';
import 'package:logger/logger.dart';
import 'package:sensors_plus/sensors_plus.dart';

class GetDate {
  static final _logger = Logger();

  static Future<Map<String, dynamic>> getPositionAndGyroData(
      Location location) async {
    final currentLocation = await location.getLocation();

    // ジャイロスコープデータのストリームを取得
    Stream<GyroscopeEvent> gyroscopeStream = gyroscopeEventStream();
    // 最初のジャイロスコープデータを取得
    GyroscopeEvent gyroscopeData = await gyroscopeStream.first;

    _logger.i(
        'Date:${DateTime.now()}\nLocation:$currentLocation\nGyroscope:$gyroscopeData');

    // 位置情報とジャイロスコープ情報を返す
    return {
      'location': currentLocation,
      'gyroscope': gyroscopeData,
    };
  }
}

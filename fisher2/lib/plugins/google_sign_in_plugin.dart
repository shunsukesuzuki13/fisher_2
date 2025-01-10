import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:logging/logging.dart';

class GoogleSignInPlugin {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
    serverClientId:
        '719937867729-plihpcoh7l3dn90ro89tgv5ap4mucvv0.apps.googleusercontent.com',
  );

  GoogleSignInAccount? _currentUser;
  final Logger _logger = Logger('GoogleSignInPlugin');

  void setupGoogleSignIn(
      Function setState, Function(GoogleSignInAccount?) signIn) {
    _googleSignIn.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
      setState(() {
        _currentUser = account;
      });
      if (_currentUser != null) {
        signIn(_currentUser);
      }
    });

    _googleSignIn.signInSilently().then((account) {
      setState(() {
        _currentUser = account;
      });
      if (account != null) {
        signIn(account);
      }
    }).catchError((error) {
      _logger.severe('Silent sign in error: $error');
    });
  }

  Widget renderSignInButton(Function(GoogleSignInAccount?) signIn) {
    return ElevatedButton(
      onPressed: () async {
        _logger.info('Sign in button pressed');
        try {
          _currentUser = await _googleSignIn.signIn();
          if (_currentUser != null) {
            _logger.info('Sign in successful: ${_currentUser!.email}');
            signIn(_currentUser);
          } else {
            _logger.warning('Sign in failed or cancelled');
          }
        } catch (error) {
          _logger.severe('Sign in error: $error');
        }
      },
      child: const Text('Sign in with Google'),
    );
  }

  Future<void> signIn(GoogleSignInAccount? account) async {
    if (account == null) {
      throw Exception('GoogleSignInAccount is null');
    }
    try {
      final GoogleSignInAuthentication auth = await account.authentication;
      if (auth.accessToken != null) {
        final http.Client client = http.Client();
        final authenticatedClient =
            AuthenticatedClient(client, auth.accessToken!);
        final driveApi = drive.DriveApi(authenticatedClient);

        // driveApiを使用してファイルをリストする
        var fileList = await driveApi.files.list();
        fileList.files?.forEach((file) {
          _logger.info('Found file: ${file.name} (${file.id})');
        });

        client.close();
      } else {
        // accessTokenがnullの場合の処理
        throw Exception('Failed to obtain access token');
      }
    } catch (error) {
      _logger.severe('Authentication error: $error');
    }
  }
}

class AuthenticatedClient extends http.BaseClient {
  final http.Client _client;
  final String _accessToken;

  AuthenticatedClient(this._client, this._accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _client.send(request);
  }
}

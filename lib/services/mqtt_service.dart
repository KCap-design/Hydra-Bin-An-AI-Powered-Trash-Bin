import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:io';

class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? client;
  bool isConnected = false;

  final String serverUri = 'broker.hivemq.com';
  final int port = 1883;
  // A unique topic name for your application
  final String topic = 'hydra_bin/classification_result';

  Future<void> initializeMqttClient() async {
    if (isConnected) return;

    // Use a unique client ID
    final clientId = 'hydra_flutter_client_${DateTime.now().millisecondsSinceEpoch}';

    client = MqttServerClient(serverUri, clientId);
    client!.port = port;
    client!.logging(on: false);
    client!.keepAlivePeriod = 60;
    client!.onDisconnected = onDisconnected;
    client!.onConnected = onConnected;
    
    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillTopic('hydra_bin/willtopic') // If you set this you must set a will message
        .withWillMessage('My Will message')
        .startClean() // Non persistent session for testing
        .withWillQos(MqttQos.atLeastOnce);
        
    print('MQTT client connecting....');
    client!.connectionMessage = connMess;

    try {
      await client!.connect();
    } on NoConnectionException catch (e) {
      print('MQTT client exception - $e');
      client!.disconnect();
    } on SocketException catch (e) {
      print('MQTT socket exception - $e');
      client!.disconnect();
    }

    if (client!.connectionStatus!.state == MqttConnectionState.connected) {
      print('MQTT client connected');
      isConnected = true;
    } else {
      print('ERROR: MQTT client connection failed - disconnecting, status is ${client!.connectionStatus}');
      client!.disconnect();
    }
  }

  void publishMessage(String className) {
    if (!isConnected || client == null) {
      print('MQTT Cannot publish: Not connected');
      // Attempt to connect and publish might be a bad idea if internet is out, 
      // but in a background task it could queue this up.
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(className);

    print('MQTT Publishing message "$className" to topic "$topic"');
    client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void onConnected() {
    print('MQTT Connected callback....');
    isConnected = true;
  }

  void onDisconnected() {
    print('MQTT Disconnected callback....');
    isConnected = false;
  }
}

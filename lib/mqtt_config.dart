/// MQTT connection settings. Stored in secure storage, never uploaded to cloud.
class MqttConfig {
  const MqttConfig({
    required this.enabled,
    required this.broker,
    required this.port,
    required this.username,
    required this.password,
    required this.topicPrefix,
  });

  final bool enabled;
  final String broker;
  final int port;
  final String username;
  final String password;
  final String topicPrefix;

  String get stateTopic => '$topicPrefix/state';
  String get commandTopic => '$topicPrefix/command';

  factory MqttConfig.fromJson(Map<String, dynamic> json) => MqttConfig(
        enabled: json['enabled'] == true,
        broker: (json['broker'] as String?) ?? '',
        port: (json['port'] as int?) ?? 1883,
        username: (json['username'] as String?) ?? '',
        password: (json['password'] as String?) ?? '',
        topicPrefix: (json['topicPrefix'] as String?) ?? 'smarthome',
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'broker': broker,
        'port': port,
        'username': username,
        'password': password,
        'topicPrefix': topicPrefix,
      };

  MqttConfig copyWith({
    bool? enabled,
    String? broker,
    int? port,
    String? username,
    String? password,
    String? topicPrefix,
  }) {
    return MqttConfig(
      enabled: enabled ?? this.enabled,
      broker: broker ?? this.broker,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      topicPrefix: topicPrefix ?? this.topicPrefix,
    );
  }
}

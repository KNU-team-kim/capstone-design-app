class StreamEntity {
  final String name;
  final bool isConnected;
  final dynamic streamObject;

  const StreamEntity({
    required this.name,
    this.isConnected = false,
    this.streamObject,
  });

  StreamEntity copyWith({
    String? name,
    bool? isConnected,
    dynamic streamObject,
  }) {
    return StreamEntity(
      name: name ?? this.name,
      isConnected: isConnected ?? this.isConnected,
      streamObject: streamObject ?? this.streamObject,
    );
  }
}
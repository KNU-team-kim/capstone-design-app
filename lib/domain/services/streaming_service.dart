abstract class StreamingService {
  Future<void> initialize();
  Future<bool> connectToStream(String streamName);
  Future<void> disconnectStream(String streamName);
  Future<void> disconnectAll();
  dynamic getStreamObject(String streamName);
  bool isConnected(String streamName);
}
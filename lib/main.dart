import 'package:capstone_design_app/env/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // WebRTC 초기화를 위해 필요함
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter WebRTC Receiver',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // WebRTC 관련 변수들
  final _remoteRenderer = RTCVideoRenderer();
  MediaStream? _remoteStream;
  RTCPeerConnection? _peerConnection;
  bool _isConnected = false;
  String _connectionStatus = '연결 대기 중...';
  String _errorLog = ''; // 에러 로그 추가

  // WebSocket 채널
  StompClient? _stompClient;

  // ICE 관련 상태 변수
  bool _remoteDescriptionSet = false;
  bool _isGatheringIceCandidates = false;
  bool _iceGatheringComplete = false;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void dispose() {
    _disposeResources();
    super.dispose();
  }

  void _disposeResources() {
    try {
      // 미디어 스트림 해제
      _remoteStream?.getTracks().forEach((track) {
        track.stop();
      });
      _remoteStream?.dispose();
      _remoteStream = null;

      // 렌더러 해제
      _remoteRenderer.srcObject = null;
      _remoteRenderer.dispose();

      // 피어 연결 해제
      _peerConnection?.close();
      _peerConnection = null;

      // STOMP 클라이언트 해제
      _stompClient?.deactivate();
      _stompClient = null;
    } catch (e) {
      print('자원 해제 중 오류: $e');
    }
  }

  void initialize() async {
    try {
      await _initializeRenderer();
      _connectToSignalingServer();
    } catch (e) {
      _logError('초기화 오류: $e');
    }
  }

  // 오류 로깅 함수
  void _logError(String error) {
    print(error);
    setState(() {
      _errorLog = error;
      _connectionStatus = '오류 발생';
    });
  }

  // 렌더러 초기화
  Future<void> _initializeRenderer() async {
    await _remoteRenderer.initialize();
  }

  // 시그널링 서버 연결
  void _connectToSignalingServer() {
    setState(() {
      _connectionStatus = '신호 서버에 연결 중...';
    });

    try {
      _stompClient = StompClient(
        config: StompConfig(
          url: Env.signalingServerURL,
          onConnect: _onStompConnect,
          onStompError: (dynamic error) {
            print('STOMP 오류: $error');
            _logError('STOMP 오류: $error');
          },
          onWebSocketError: (dynamic error) {
            print('WebSocket 오류: $error');
            _logError('WebSocket 오류: $error');
          },
          reconnectDelay: const Duration(seconds: 5),
        ),
      );

      _stompClient!.activate();
      print('STOMP 활성화: ${_stompClient!.isActive}');
    } catch (e) {
      _logError('시그널링 서버 연결 오류: $e');
    }
  }

  // 신호 서버 연결 후 실행되는 함수
  void _onStompConnect(StompFrame frame) {
    print('신호 서버에 연결됨');
    setState(() => _connectionStatus = '신호 서버에 연결됨');

    try {
      // answer 수신을 위한 구독 설정
      _stompClient!.subscribe(
        destination: "/topic/answer/1",
        callback: (StompFrame frame) {
          print('answer 수신: ${frame.body}');
          if (frame.body != null) {
            try {
              Map<String, dynamic> message = json.decode(frame.body!);
              _handleSignalingMessage(message);
            } catch (e) {
              _logError('Answer 메시지 파싱 오류: $e');
            }
          }
        },
      );

      // WebRTC 연결 설정 시작
      _createPeerConnection().then((_) {
        // 연결 설정 후 즉시 offer 생성 및 전송
        _createAndSendOffer();
      });
    } catch (e) {
      _logError('구독 설정 오류: $e');
    }
  }

  // offer 생성 및 전송 (ICE 수집 및 통합 방식 적용)
  Future<void> _createAndSendOffer() async {
    try {
      if (_peerConnection == null) {
        _logError('PeerConnection이 없습니다');
        return;
      }

      setState(() {
        _connectionStatus = 'Offer 생성 및 ICE 후보 수집 중...';
        _isGatheringIceCandidates = true;
      });

      // offer 생성
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      print('임시 Offer 생성 완료');

      // ICE 후보 수집 완료 대기 (타임아웃 설정)
      int attemptCount = 0;
      const maxAttempts = 200; // 최대 20초 대기 (1초 * 20)

      while (!_iceGatheringComplete && attemptCount < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 1000));
        attemptCount++;
        print('ICE 후보 수집 대기 중... ($attemptCount/$maxAttempts)');
      }

      // 최종 LocalDescription 가져오기 (완전한 SDP 포함)
      RTCSessionDescription? completeOffer = await _peerConnection!.getLocalDescription();

      if (completeOffer == null) {
        throw Exception('최종 LocalDescription을 가져올 수 없습니다');
      }

      print('최종 Offer 생성 완료 (모든 ICE 후보 포함)');

      if (_stompClient != null && _stompClient!.connected) {
        print('완전한 Offer 전송 중...');

        _stompClient!.send(
          destination: '/app/offer/1',
          body: json.encode({
            'type': 'offer',
            'offer': completeOffer.toMap(),
            'id': '1'
          }),
        );

        setState(() {
          _connectionStatus = '완전한 Offer 전송됨, Answer 대기 중...';
          _isGatheringIceCandidates = false;
        });
      }
    } catch (e) {
      _logError('Offer 생성 및 전송 오류: $e');
      setState(() => _isGatheringIceCandidates = false);
    }
  }

  // 시그널링 메시지 처리
  void _handleSignalingMessage(Map<String, dynamic> message) async {
    try {
      String type = message['type'];
      print('메시지 타입: $type');
      print('메시지 내용: $message');

      switch (type) {
        case 'answer':
          try {
            print('Answer 메시지 원본: $message');

            // Answer SDP 추출
            String? sdp;
            if (message.containsKey('answer') && message['answer'] != null) {
              Map<String, dynamic> answerObj = message['answer'];
              if (answerObj.containsKey('sdp')) {
                sdp = answerObj['sdp'];
                print('Answer SDP 찾음: $sdp');
              }
            }

            if (sdp == null) {
              throw Exception('유효한 SDP를 찾을 수 없습니다');
            }

            // RTCSessionDescription 생성
            RTCSessionDescription description = RTCSessionDescription(
                sdp,
                'answer'
            );

            if (_peerConnection != null) {
              print('원격 설명 설정 중...');
              await _peerConnection!.setRemoteDescription(description);
              _remoteDescriptionSet = true;

              setState(() {
                _connectionStatus = 'Answer 수신됨, 연결 설정 중...';
              });
            }
          } catch (e, stackTrace) {
            print('SDP 처리 중 상세 오류: $e');
            print('스택 트레이스: $stackTrace');
            print('오류 발생 시 메시지 구조: $message');
            _logError('SDP 처리 오류: $e');
          }
          break;

        default:
          print('처리할 수 없는 메시지 타입: $type');
      }
    } catch (e) {
      _logError('시그널링 메시지 처리 오류: $e');
    }
  }

  // WebRTC 연결 설정
  Future<void> _createPeerConnection() async {
    setState(() {
      _connectionStatus = 'WebRTC 연결 설정 중...';
    });

    try {
      // STUN 서버 설정
      Map<String, dynamic> configuration = {
        'iceServers': [
          // {
          //   'urls': [
          //     "stun:stun.l.google.com:19302",
          //   ]
          // }
          {
            'urls': Env.turnURL,
            'username': Env.turnUsername,
            'credential': Env.turnCredential
          }
        ]
      };

      // 미디어 제약 조건 설정
      final Map<String, dynamic> offerSdpConstraints = {
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': true,
        },
        'optional': [],
      };

      print('PeerConnection 생성 중...');
      _peerConnection = await createPeerConnection(configuration, offerSdpConstraints);
      print('PeerConnection 생성 완료');

      // 원격 스트림 이벤트 처리
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        print('트랙 수신됨: ${event.track.kind}');
        if (event.streams.isNotEmpty) {
          setState(() {
            _remoteStream = event.streams[0];
            _remoteRenderer.srcObject = _remoteStream;
            _isConnected = true;
            _connectionStatus = '스트림 수신 중';
          });
        }
      };

      // ICE 후보 수집 상태 이벤트 처리
      _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
        print('ICE 수집 상태 변경: $state');

        if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
          print('ICE 후보 수집 완료');
          setState(() {
            _iceGatheringComplete = true;
          });
        }
      };

      // ICE 후보 이벤트 처리 (로깅용으로만 사용)
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        print('로컬 ICE 후보 발견: ${candidate.candidate}');
        // 개별 ICE 후보 전송하지 않음 (대신 SDP에 포함시킴)
      };

      // 연결 상태 변경 이벤트 처리
      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        print('연결 상태 변경: $state');
        setState(() {
          _connectionStatus = '연결 상태: ${state.toString().split('.').last}';

          if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
            _isConnected = true;
          } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
              state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
              state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
            _isConnected = false;
          }
        });
      };

      // ICE 연결 상태 변경 이벤트
      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        print('ICE 연결 상태 변경: $state');
      };

    } catch (e) {
      _logError('PeerConnection 생성 오류: $e');
    }
  }

  // 연결 재시도
  void _reconnect() {
    _disposeResources();
    setState(() {
      _isConnected = false;
      _remoteDescriptionSet = false;
      _isGatheringIceCandidates = false;
      _iceGatheringComplete = false;
      _connectionStatus = '재연결 중...';
      _errorLog = '';
    });

    // 약간의 지연 후 재연결 시도
    Future.delayed(const Duration(seconds: 1), () {
      initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_remoteStream != null) {
      print('렌더러에 스트림 설정: ${_remoteStream?.id}');
      _remoteRenderer.srcObject = _remoteStream;
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('WebRTC 스트림 수신기'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: _isConnected
                  ? RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                placeholderBuilder: (context) {
                  return Container(color: Colors.blue.shade900, child: const Center(child: Text('비디오 로딩 중...', style: TextStyle(color: Colors.white))));
                },
                mirror: false,
                filterQuality: FilterQuality.medium,
              )
                  : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '스트림 연결 대기 중...',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    const SizedBox(height: 20),
                    CircularProgressIndicator(),
                  ],
                ),
              ),
            ),
          ),

          // 상태 표시 및 제어 버튼
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            color: Colors.grey[900],
            child: Column(
              children: [
                // 연결 상태
                Text(
                  _connectionStatus,
                  style: TextStyle(color: Colors.white),
                ),

                // 에러 로그가 있을 경우 표시
                if (_errorLog.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      _errorLog,
                      style: TextStyle(color: Colors.red, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                const SizedBox(height: 8),

                // 버튼 행
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 재연결 버튼
                    TextButton.icon(
                      icon: const Icon(Icons.refresh, color: Colors.blue),
                      label: const Text('재연결', style: TextStyle(color: Colors.white)),
                      onPressed: _reconnect,
                    ),
                    const SizedBox(width: 16),

                    // 연결 종료 버튼
                    TextButton.icon(
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: const Text('연결 종료', style: TextStyle(color: Colors.white)),
                      onPressed: () {
                        _disposeResources();
                        setState(() {
                          _isConnected = false;
                          _connectionStatus = '연결 종료됨';
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
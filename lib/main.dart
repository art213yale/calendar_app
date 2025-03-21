import 'package:flutter/material.dart';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// 커스텀 날짜 형식 함수들
String formatMonth(DateTime date) {
  return '${date.year}년 ${date.month}월';
}

String formatDate(DateTime date) {
  return '${date.year}년 ${date.month}월 ${date.day}일';
}

// 날짜를 키로 사용하기 위한 형식 (yyyy-MM-dd)
String formatDateKey(DateTime date) {
  String month = date.month.toString().padLeft(2, '0');
  String day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

// 문자열에서 날짜 파싱 (yyyy-MM-dd)
DateTime parseDateKey(String dateStr) {
  List<String> parts = dateStr.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

void main() async {
  // 중요: 플러그인 초기화를 위해 필요
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '달력 일기장',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Pretendard', // 기본 폰트 변경
      ),
      home: const CalendarApp(),
    );
  }
}

// 이미지 데이터를 저장하기 위한 클래스
class DiaryImage {
  final String id;
  final Uint8List bytes;

  DiaryImage({
    required this.id,
    required this.bytes,
  });

  // JSON 변환을 위한 메서드
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bytes': base64Encode(bytes), // 바이트 데이터를 Base64 문자열로 변환
    };
  }

  // JSON에서 객체로 변환하는 팩토리 생성자
  factory DiaryImage.fromJson(Map<String, dynamic> json) {
    return DiaryImage(
      id: json['id'] as String,
      bytes: base64Decode(json['bytes'] as String), // Base64 문자열을 바이트 데이터로 변환
    );
  }
}

// 일기 데이터 모델
class DiaryEntry {
  String content;
  List<DiaryImage> images;

  DiaryEntry({
    required this.content,
    required this.images,
  });

  // JSON 변환을 위한 메서드
  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'images': images.map((img) => img.toJson()).toList(),
    };
  }

  // JSON에서 객체로 변환하는 팩토리 생성자
  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    List<DiaryImage> imagesList = [];
    if (json['images'] != null) {
      imagesList = (json['images'] as List)
          .map((img) => DiaryImage.fromJson(img as Map<String, dynamic>))
          .toList();
    }

    return DiaryEntry(
      content: json['content'] as String,
      images: imagesList,
    );
  }
}

// 데이터 저장 및 로드 기능을 위한 클래스
class DiaryStorage {
  static const String _diariesKey = 'diaries_data';

  // 모든 일기 저장
  static Future<void> saveDiaries(Map<String, DiaryEntry> diaries) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // HashMap을 직렬화 가능한 Map으로 변환
      final Map<String, dynamic> serializableDiaries = {};
      diaries.forEach((key, value) {
        serializableDiaries[key] = value.toJson();
      });

      final String encodedData = jsonEncode(serializableDiaries);
      await prefs.setString(_diariesKey, encodedData);
      print('일기 데이터 저장 완료: ${diaries.length}개 항목');
    } catch (e) {
      print('일기 데이터 저장 오류: $e');
      throw e;
    }
  }

  // 모든 일기 로드
  static Future<Map<String, DiaryEntry>> loadDiaries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? encodedData = prefs.getString(_diariesKey);

      if (encodedData == null) {
        print('저장된 일기 데이터 없음');
        return {};
      }

      final Map<String, dynamic> decodedData = jsonDecode(encodedData) as Map<String, dynamic>;
      final Map<String, DiaryEntry> diaries = {};

      decodedData.forEach((key, value) {
        diaries[key] = DiaryEntry.fromJson(value as Map<String, dynamic>);
      });

      print('일기 데이터 로드 완료: ${diaries.length}개 항목');
      return diaries;
    } catch (e) {
      print('일기 데이터 로드 오류: $e');
      return {};
    }
  }
}

class CalendarApp extends StatefulWidget {
  const CalendarApp({Key? key}) : super(key: key);

  @override
  _CalendarAppState createState() => _CalendarAppState();
}

class _CalendarAppState extends State<CalendarApp> {
  DateTime _selectedDate = DateTime.now(); // 선택된 날짜
  DateTime _currentMonth = DateTime.now(); // 현재 표시된 월

  // 일기 데이터를 저장할 맵 (키: 날짜 문자열, 값: 일기 객체)
  final HashMap<String, DiaryEntry> _diaries = HashMap<String, DiaryEntry>();

  // 검색어 controller
  final TextEditingController _searchController = TextEditingController();

  // 검색 결과
  List<MapEntry<DateTime, DiaryEntry>> _searchResults = [];

  // 검색 모드 여부
  bool _isSearching = false;

  // 데이터 로딩 상태
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // 앱 시작 시 저장된 데이터 로드
    _loadSavedDiaries();
  }

  // 저장된 일기 데이터 로드
  Future<void> _loadSavedDiaries() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final savedDiaries = await DiaryStorage.loadDiaries();
      setState(() {
        _diaries.clear();
        _diaries.addAll(savedDiaries);
        _isLoading = false;
      });
    } catch (e) {
      print('일기 데이터 로드 오류: $e');
      setState(() {
        _isLoading = false;
      });

      // 오류 메시지 표시
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('일기 데이터를 불러오는 중 오류가 발생했습니다.'),
            backgroundColor: Colors.red,
          ),
        );
      });
    }
  }

  // 날짜별 일기 작성 여부를 확인하는 함수
  bool _hasDiary(DateTime date) {
    final dateStr = formatDateKey(date);
    return _diaries.containsKey(dateStr) &&
        (_diaries[dateStr]!.content.isNotEmpty || _diaries[dateStr]!.images.isNotEmpty);
  }

  // 일기 내용을 가져오는 함수
  DiaryEntry _getDiary(DateTime date) {
    final dateStr = formatDateKey(date);
    return _diaries[dateStr] ?? DiaryEntry(content: '', images: []);
  }

  // 일기 저장 함수
  Future<void> _saveDiary(DateTime date, DiaryEntry diary) async {
    final dateStr = formatDateKey(date);
    setState(() {
      _diaries[dateStr] = diary;
    });

    // 변경된 데이터를 영구 저장
    try {
      await DiaryStorage.saveDiaries(_diaries);

      // 성공 메시지는 DiaryDetailPage에서 표시하므로 여기서는 필요 없음
    } catch (e) {
      print('일기 저장 오류: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('일기 저장 중 오류가 발생했습니다.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 검색 기능
  void _searchDiaries(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    final List<MapEntry<DateTime, DiaryEntry>> results = [];

    _diaries.forEach((dateStr, diary) {
      if (diary.content.toLowerCase().contains(query.toLowerCase())) {
        final date = parseDateKey(dateStr);
        results.add(MapEntry(date, diary));
      }
    });

    setState(() {
      _searchResults = results;
      _isSearching = true;
    });
  }

  // 한 달의 날짜들을 생성하는 함수
  List<DateTime> _getDaysInMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final daysBefore = first.weekday % 7;
    final firstToDisplay = first.subtract(Duration(days: daysBefore));

    final last = DateTime(month.year, month.month + 1, 0);
    final daysAfter = 6 - last.weekday % 7;
    final lastToDisplay = last.add(Duration(days: daysAfter));

    final daysToDisplay = lastToDisplay.difference(firstToDisplay).inDays + 1;

    return List.generate(
        daysToDisplay,
            (index) => firstToDisplay.add(Duration(days: index))
    );
  }

  // 이전 달로 이동
  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  // 다음 달로 이동
  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
  }

  // 오늘로 이동
  void _resetToToday() {
    setState(() {
      _currentMonth = DateTime.now();
      _selectedDate = DateTime.now();
    });
  }

  // 일기 상세 화면으로 이동
  void _showDiaryDetail(DateTime date) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiaryDetailPage(
          date: date,
          diary: _getDiary(date),
          onSave: (diary) async {
            await _saveDiary(date, diary);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 앱이 종료되기 전에 모든 데이터 저장
        try {
          await DiaryStorage.saveDiaries(_diaries);
        } catch (e) {
          print('앱 종료 시 데이터 저장 오류: $e');
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isSearching
              ? TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '일기 내용 검색...',
              hintStyle: TextStyle(color: Colors.white70),
              border: InputBorder.none,
            ),
            style: TextStyle(color: Colors.white),
            cursorColor: Colors.white,
            autofocus: true,
            onChanged: _searchDiaries,
          )
              : const Text('달력 일기장'),
          actions: [
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  if (_isSearching) {
                    _isSearching = false;
                    _searchController.clear();
                    _searchResults = [];
                  } else {
                    _isSearching = true;
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.today),
              onPressed: _resetToToday,
              tooltip: '오늘',
            ),
          ],
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator())
            : (_isSearching && _searchResults.isNotEmpty
            ? _buildSearchResults()
            : _buildCalendar()),
      ),
    );
  }

  // 검색 결과 화면 빌드
  Widget _buildSearchResults() {
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final date = _searchResults[index].key;
        final diary = _searchResults[index].value;
        final dateStr = formatDate(date);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: ListTile(
            title: Text(dateStr, style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  diary.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (diary.images.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        Icon(Icons.image, size: 16, color: Colors.grey),
                        SizedBox(width: 4),
                        Text('${diary.images.length}개의 이미지',
                            style: TextStyle(color: Colors.grey, fontSize: 12)
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            onTap: () {
              _showDiaryDetail(date);
            },
          ),
        );
      },
    );
  }

  // 달력 화면 빌드
  Widget _buildCalendar() {
    return Column(
      children: [
        // 달력 헤더
        Container(
          color: Color(0xFFF5F5DC), // 베이지색 배경색 추가
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _previousMonth,
              ),
              Text(
                formatMonth(_currentMonth),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Pretendard', // 헤더 폰트 변경
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _nextMonth,
              ),
            ],
          ),
        ),
        // 요일 헤더
        Container(
          color: Color(0xFFF5F5DC), // 베이지색 배경색 추가
          child: Row(
            children: const [
              Expanded(child: Text('일', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontFamily: 'Pretendard'))),
              Expanded(child: Text('월', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Pretendard'))),
              Expanded(child: Text('화', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Pretendard'))),
              Expanded(child: Text('수', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Pretendard'))),
              Expanded(child: Text('목', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Pretendard'))),
              Expanded(child: Text('금', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Pretendard'))),
              Expanded(child: Text('토', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontFamily: 'Pretendard'))),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 달력 그리드
        Expanded(
          child: Container(
            color: Color(0xFFF5F5DC), // 베이지색 배경색 추가
            child: GridView.count(
              crossAxisCount: 7,
              childAspectRatio: 1.0,
              children: _getDaysInMonth(_currentMonth).map((date) {
                final isSameMonth = date.month == _currentMonth.month;
                final isSelectedDate = date.year == _selectedDate.year &&
                    date.month == _selectedDate.month &&
                    date.day == _selectedDate.day;
                final isToday = date.year == DateTime.now().year &&
                    date.month == DateTime.now().month &&
                    date.day == DateTime.now().day;
                final hasDiary = _hasDiary(date);

                // 요일별 색상 설정
                Color textColor = Colors.black;
                if (date.weekday == DateTime.sunday) {
                  textColor = Colors.red;
                } else if (date.weekday == DateTime.saturday) {
                  textColor = Colors.blue;
                }

                if (!isSameMonth) {
                  textColor = textColor.withOpacity(0.3);
                }

                return GestureDetector(
                  onTap: () {
                    if (isSameMonth) {
                      setState(() {
                        _selectedDate = date;
                      });

                      // 날짜 선택 시 일기 상세 화면으로 이동
                      _showDiaryDetail(date);
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.all(4.0),
                    decoration: BoxDecoration(
                      color: isSelectedDate ? Colors.blue.withOpacity(0.2) : Colors.white.withOpacity(0.7), // 날짜 셀 배경색 추가
                      border: isToday ? Border.all(color: Colors.blue, width: 2) : Border.all(color: Colors.grey.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(12), // 테두리 둥글게
                      boxShadow: isSelectedDate ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        )
                      ] : null,
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: isSelectedDate || isToday ? FontWeight.bold : FontWeight.normal,
                              fontSize: 16,
                              fontFamily: 'Pretendard', // 날짜 폰트 변경
                            ),
                          ),
                        ),
                        if (hasDiary)
                          Positioned(
                            top: 5,
                            right: 5,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // 선택된 날짜 정보
        Container(
          padding: const EdgeInsets.all(16.0),
          color: Color(0xFFF5F5DC), // 베이지색 배경색 추가
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    formatDate(_selectedDate),
                    style: const TextStyle(
                      fontSize: 16,
                      fontFamily: 'Pretendard', // 폰트 변경
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                icon: Icon(Icons.edit),
                label: Text('일기 작성', style: TextStyle(fontFamily: 'Pretendard')), // 폰트 변경
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () {
                  _showDiaryDetail(_selectedDate);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 일기 상세 화면
class DiaryDetailPage extends StatefulWidget {
  final DateTime date;
  final DiaryEntry diary;
  final Function(DiaryEntry) onSave;

  const DiaryDetailPage({
    Key? key,
    required this.date,
    required this.diary,
    required this.onSave,
  }) : super(key: key);

  @override
  _DiaryDetailPageState createState() => _DiaryDetailPageState();
}

class _DiaryDetailPageState extends State<DiaryDetailPage> {
  late TextEditingController _contentController;
  late List<DiaryImage> _images;
  bool _isEdited = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.diary.content);
    _images = List.from(widget.diary.images);

    // 텍스트 변경 리스너
    _contentController.addListener(() {
      if (_contentController.text != widget.diary.content) {
        setState(() {
          _isEdited = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  // 이미지 추가 함수 - 메모리에 이미지 저장
  Future<void> _addImage() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200, // 이미지 크기 제한으로 메모리 사용량 감소
        maxHeight: 1200,
        imageQuality: 85, // 이미지 품질 조정 (1-100)
      );

      if (image == null) {
        setState(() {
          _isSaving = false;
        });
        return;
      }

      // 이미지 파일을 바이트로 읽기
      final bytes = await image.readAsBytes();

      // 메모리 내에 이미지 데이터 저장
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final diaryImage = DiaryImage(
        id: timestamp,
        bytes: bytes,
      );

      setState(() {
        _images.add(diaryImage);
        _isEdited = true;
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('이미지가 성공적으로 추가되었습니다.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      print('이미지 추가 오류: $e');

      setState(() {
        _isSaving = false;
      });

      // 사용자에게 오류 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('이미지를 추가하는 중 오류가 발생했습니다.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 이미지 삭제 함수
  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
      _isEdited = true;
    });
  }

  // 일기 저장 함수
  Future<void> _saveDiary() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final DiaryEntry newDiary = DiaryEntry(
        content: _contentController.text,
        images: _images,
      );

      await widget.onSave(newDiary);

      setState(() {
        _isSaving = false;
        _isEdited = false;
      });

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('일기가 저장되었습니다.'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('일기 저장 오류: $e');

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('일기 저장 중 오류가 발생했습니다.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isEdited) {
          // 변경 사항이 있으면 사용자에게 저장할지 물어봄
          final shouldSave = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('저장하지 않은 변경사항'),
              content: Text('작성 중인 일기를 저장하시겠습니까?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('저장'),
                ),
              ],
            ),
          );

          if (shouldSave == true) {
            await _saveDiary();
            return false; // 저장 후 navigation은 _saveDiary에서 처리하므로 여기서는 false 반환
          }
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(formatDate(widget.date)),
          actions: [
            if (_isEdited)
              IconButton(
                icon: Icon(Icons.save),
                onPressed: _isSaving ? null : _saveDiary,
                tooltip: '저장',
              ),
          ],
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 일기 내용 입력 필드
                  TextField(
                    controller: _contentController,
                    maxLines: 10,
                    decoration: InputDecoration(
                      hintText: '오늘의 일기를 작성해보세요...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 16),

                  // 이미지 섹션 헤더
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '사진 첨부',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.add_photo_alternate),
                        onPressed: _isSaving ? null : _addImage,
                        tooltip: '사진 추가',
                      ),
                    ],
                  ),
                  SizedBox(height: 8),

                  // 첨부된 이미지 목록
                  if (_images.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32.0),
                        child: Text(
                          '첨부된 사진이 없습니다',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                            fontFamily: 'Pretendard',
                          ),
                        ),
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _images.length,
                      itemBuilder: (context, index) {
                        final image = _images[index];
                        return Stack(
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => Scaffold(
                                      appBar: AppBar(
                                        title: Text('이미지 보기'),
                                      ),
                                      body: Center(
                                        child: InteractiveViewer(
                                          child: Image.memory(
                                            image.bytes,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    image.bytes,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () => _removeImage(index),
                                child: Container(
                                  padding: EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),

            // 로딩 인디케이터
            if (_isSaving)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveDiary,
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Text(
                _isSaving ? '저장 중...' : '저장하기',
                style: TextStyle(fontSize: 16, fontFamily: 'Pretendard'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
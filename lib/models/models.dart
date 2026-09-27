// 数据模型定义 - 复刻 doubao2api 的 UploadedFile / 消息结构

class UploadedFile {
  String uri;
  String name;
  int size;
  String fileType;

  UploadedFile({
    this.uri = '',
    this.name = '',
    this.size = 0,
    this.fileType = '',
  });

  factory UploadedFile.fromJson(Map<String, dynamic> j) => UploadedFile(
        uri: j['uri']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        size: (j['size'] is int) ? j['size'] : int.tryParse('${j['size']}') ?? 0,
        fileType: j['file_type']?.toString() ?? j['fileType']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'name': name,
        'size': size,
        'file_type': fileType,
      };
}

class ChatMessage {
  final String role;
  String content;
  String thinking;
  bool isStreaming;
  List<String> imageUrls;
  List<UploadedFile> files;
  List<SearchResult> searchResults;

  ChatMessage({
    required this.role,
    this.content = '',
    this.thinking = '',
    this.isStreaming = false,
    List<String>? imageUrls,
    List<UploadedFile>? files,
    List<SearchResult>? searchResults,
  })  : imageUrls = imageUrls ?? [],
        files = files ?? [],
        searchResults = searchResults ?? [];
}

class SearchResult {
  final String summary;
  final List<String> queries;
  final List<Map<String, String>> results;

  SearchResult({
    this.summary = '',
    List<String>? queries,
    List<Map<String, String>>? results,
  })  : queries = queries ?? [],
        results = results ?? [];
}

class GeneratedImage {
  final String url;
  final String revisedPrompt;
  GeneratedImage({required this.url, this.revisedPrompt = ''});
}

class GeneratedVideo {
  final String videoUrl;
  final String coverUrl;
  final double duration;
  final int width;
  final int height;
  GeneratedVideo({
    required this.videoUrl,
    this.coverUrl = '',
    this.duration = 0,
    this.width = 0,
    this.height = 0,
  });
}

class GeneratedMusic {
  final String audioUrl;
  final String title;
  final double duration;
  final String lyrics;
  final String coverUrl;
  GeneratedMusic({
    required this.audioUrl,
    this.title = '',
    this.duration = 0,
    this.lyrics = '',
    this.coverUrl = '',
  });
}

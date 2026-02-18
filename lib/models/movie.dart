import 'dart:convert';

/// 样本预览图
class SampleImage {
  final String id;
  final String thumbnail;
  final String? src;  // 大图URL，可能为null
  final String? alt;

  SampleImage({
    required this.id,
    required this.thumbnail,
    this.src,
    this.alt,
  });

  factory SampleImage.fromJson(Map<String, dynamic> json) {
    return SampleImage(
      id: json['id'] as String? ?? '',
      thumbnail: json['thumbnail'] as String? ?? '',
      src: json['src'] as String?,
      alt: json['alt'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'thumbnail': thumbnail,
      'src': src,
      'alt': alt,
    };
  }
}

/// 磁力链接信息
class MagnetInfo {
  final String id;        // BTIH hash
  final String link;      // magnet: URI
  final bool isHD;
  final String title;
  final String size;      // 如 "3.5GB"
  final int numberSize;   // 字节数
  final String shareDate;
  final bool hasSubtitle;

  MagnetInfo({
    required this.id,
    required this.link,
    required this.isHD,
    required this.title,
    required this.size,
    required this.numberSize,
    required this.shareDate,
    required this.hasSubtitle,
  });

  factory MagnetInfo.fromJson(Map<String, dynamic> json) {
    return MagnetInfo(
      id: json['id'] as String? ?? '',
      link: json['link'] as String? ?? '',
      isHD: json['isHD'] as bool? ?? false,
      title: json['title'] as String? ?? '',
      size: json['size'] as String? ?? '',
      numberSize: json['numberSize'] as int? ?? 0,
      shareDate: json['shareDate'] as String? ?? '',
      hasSubtitle: json['hasSubtitle'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'link': link,
      'isHD': isHD,
      'title': title,
      'size': size,
      'numberSize': numberSize,
      'shareDate': shareDate,
      'hasSubtitle': hasSubtitle,
    };
  }
}

/// 用户评论
class MovieComment {
  final String id;
  final String? user;       // 用户名
  final String? avatar;     // 用户头像
  final String content;     // 评论内容
  final String? date;       // 评论日期
  final int? rating;        // 评分 (1-5)

  MovieComment({
    required this.id,
    this.user,
    this.avatar,
    required this.content,
    this.date,
    this.rating,
  });

  factory MovieComment.fromJson(Map<String, dynamic> json) {
    return MovieComment(
      id: json['id'] as String? ?? '',
      user: json['user'] as String?,
      avatar: json['avatar'] as String?,
      content: json['content'] as String? ?? '',
      date: json['date'] as String?,
      rating: json['rating'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user': user,
      'avatar': avatar,
      'content': content,
      'date': date,
      'rating': rating,
    };
  }
}

/// 影片数据模型
class Movie {
  final String id;
  final String? title;
  final String? cover;
  final String? date;
  final String? publisher;
  final String? producer;      // 制作商
  final int? lastUpdated;
  final List<ActorInfo>? actors;
  final List<String>? genres;
  final String? description;
  final String? director;
  final String? series;
  final int? duration;
  final List<String>? magnets;     // 兼容旧版本，简单字符串列表
  final List<MagnetInfo>? magnetInfo;  // 详细磁力链接信息
  final List<SampleImage>? samples;    // 样本预览图
  final String? translation;
  final List<MovieComment>? comments;  // 用户评论

  // 内部字段，用于 AJAX 请求
  final String? gid;
  final String? uc;

  Movie({
    required this.id,
    this.title,
    this.cover,
    this.date,
    this.publisher,
    this.producer,
    this.lastUpdated,
    this.actors,
    this.genres,
    this.description,
    this.director,
    this.series,
    this.duration,
    this.magnets,
    this.magnetInfo,
    this.samples,
    this.translation,
    this.comments,
    this.gid,
    this.uc,
  });

  /// 从 JSON 创建
  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      id: json['id'] as String? ?? '',
      title: json['title'] as String?,
      cover: json['cover'] as String?,
      date: json['date'] as String?,
      publisher: json['publisher'] as String?,
      producer: json['producer'] as String?,
      lastUpdated: json['last_updated'] as int?,
      actors: (json['actors'] as List<dynamic>?)
          ?.map((e) => ActorInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      genres: (json['genres'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      description: json['description'] as String?,
      director: json['director'] as String?,
      series: json['series'] as String?,
      duration: json['duration'] as int?,
      magnets: (json['magnets'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      magnetInfo: (json['magnetInfo'] as List<dynamic>?)
          ?.map((e) => MagnetInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      samples: (json['samples'] as List<dynamic>?)
          ?.map((e) => SampleImage.fromJson(e as Map<String, dynamic>))
          .toList(),
      translation: json['translation'] as String?,
      comments: (json['comments'] as List<dynamic>?)
          ?.map((e) => MovieComment.fromJson(e as Map<String, dynamic>))
          .toList(),
      gid: json['gid'] as String?,
      uc: json['uc'] as String?,
    );
  }

  /// 从数据库 Map 创建
  factory Movie.fromDbMap(Map<String, dynamic> map) {
    // 反序列化 JSON 字符串字段
    final actorsJson = map['actors_json'] as String?;
    final genresJson = map['genres_json'] as String?;
    final samplesJson = map['samples_json'] as String?;
    final magnetsJson = map['magnets_json'] as String?;

    final List<ActorInfo>? actors = actorsJson != null && actorsJson.isNotEmpty
        ? (jsonDecode(actorsJson) as List).map((e) => ActorInfo.fromJson(e as Map<String, dynamic>)).toList()
        : null;

    final List<String>? genres = genresJson != null && genresJson.isNotEmpty
        ? (jsonDecode(genresJson) as List).cast<String>()
        : null;

    final List<SampleImage>? samples = samplesJson != null && samplesJson.isNotEmpty
        ? (jsonDecode(samplesJson) as List).map((e) => SampleImage.fromJson(e as Map<String, dynamic>)).toList()
        : null;

    final List<MagnetInfo>? magnetInfo = magnetsJson != null && magnetsJson.isNotEmpty
        ? (jsonDecode(magnetsJson) as List).map((e) => MagnetInfo.fromJson(e as Map<String, dynamic>)).toList()
        : null;

    return Movie(
      id: map['id'] as String? ?? '',
      title: map['title'] as String?,
      cover: map['cover'] as String?,
      date: map['date'] as String?,
      publisher: map['publisher'] as String?,
      producer: map['producer'] as String?,
      lastUpdated: map['last_updated'] as int?,
      actors: actors,
      genres: genres,
      description: map['description'] as String?,
      director: map['director'] as String?,
      series: map['series'] as String?,
      duration: map['duration'] as int?,
      samples: samples,
      magnetInfo: magnetInfo,
      magnets: magnetInfo?.map((m) => m.link).toList(),
      translation: map['translation'] as String?,
      gid: map['gid'] as String?,
      uc: map['uc'] as String?,
    );
  }

  /// 转换为数据库 Map（将复杂类型序列化为 JSON 字符串）
  Map<String, dynamic> toDbMap() {
    final map = <String, dynamic>{
      'id': id,
      'title': title,
      'cover': cover,
      'date': date,
      'publisher': publisher,
      'producer': producer,
      'last_updated': lastUpdated ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'description': description,
      'director': director,
      'series': series,
      'duration': duration,
      'translation': translation,
      'gid': gid,
      'uc': uc,
    };

    // 将复杂类型序列化为 JSON 字符串（仅非空值）
    if (actors != null) {
      map['actors_json'] = jsonEncode(actors!.map((e) => e.toJson()).toList());
    }
    if (genres != null) {
      map['genres_json'] = jsonEncode(genres);
    }
    if (samples != null) {
      map['samples_json'] = jsonEncode(samples!.map((e) => e.toJson()).toList());
    }
    if (magnetInfo != null) {
      map['magnets_json'] = jsonEncode(magnetInfo!.map((e) => e.toJson()).toList());
    }

    return map;
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'cover': cover,
      'date': date,
      'publisher': publisher,
      'producer': producer,
      'last_updated': lastUpdated,
      'actors': actors?.map((e) => e.toJson()).toList(),
      'genres': genres,
      'description': description,
      'director': director,
      'series': series,
      'duration': duration,
      'magnets': magnets,
      'magnetInfo': magnetInfo?.map((e) => e.toJson()).toList(),
      'samples': samples?.map((e) => e.toJson()).toList(),
      'translation': translation,
      'comments': comments?.map((e) => e.toJson()).toList(),
      'gid': gid,
      'uc': uc,
    };
  }

  /// 复制并修改部分属性
  Movie copyWith({
    String? id,
    String? title,
    String? cover,
    String? date,
    String? publisher,
    String? producer,
    int? lastUpdated,
    List<ActorInfo>? actors,
    List<String>? genres,
    String? description,
    String? director,
    String? series,
    int? duration,
    List<String>? magnets,
    List<MagnetInfo>? magnetInfo,
    List<SampleImage>? samples,
    String? translation,
    List<MovieComment>? comments,
    String? gid,
    String? uc,
  }) {
    return Movie(
      id: id ?? this.id,
      title: title ?? this.title,
      cover: cover ?? this.cover,
      date: date ?? this.date,
      publisher: publisher ?? this.publisher,
      producer: producer ?? this.producer,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      actors: actors ?? this.actors,
      genres: genres ?? this.genres,
      description: description ?? this.description,
      director: director ?? this.director,
      series: series ?? this.series,
      duration: duration ?? this.duration,
      magnets: magnets ?? this.magnets,
      magnetInfo: magnetInfo ?? this.magnetInfo,
      samples: samples ?? this.samples,
      translation: translation ?? this.translation,
      comments: comments ?? this.comments,
      gid: gid ?? this.gid,
      uc: uc ?? this.uc,
    );
  }
}

/// 演员信息（简化版）
class ActorInfo {
  final String id;
  final String? name;
  final String? avatar;

  ActorInfo({
    required this.id,
    this.name,
    this.avatar,
  });

  factory ActorInfo.fromJson(Map<String, dynamic> json) {
    return ActorInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String?,
      avatar: json['avatar'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
    };
  }
}

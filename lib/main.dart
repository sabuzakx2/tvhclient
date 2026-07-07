import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const TvhStreamApp());
}

const _bg = Color(0xFF070709);
const _panel = Color(0xFF121217);
const _panel2 = Color(0xFF1B1B22);
const _panel3 = Color(0xFF25252D);
const _accent = Color(0xFFE50914);
const _muted = Color(0xFFAAAAB5);

class TvhStreamApp extends StatelessWidget {
  const TvhStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TVH Stream',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          secondary: _accent,
          surface: _panel,
        ),
        fontFamilyFallback: const ['Noto Sans KR', 'Roboto', 'sans-serif'],
        appBarTheme: const AppBarTheme(
          backgroundColor: _bg,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const BootstrapPage(),
    );
  }
}

class AppSettings {
  final String baseUrl;
  final String username;
  final String password;
  final String profile;

  const AppSettings({
    this.baseUrl = '',
    this.username = '',
    this.password = '',
    this.profile = '',
  });

  bool get configured => baseUrl.trim().isNotEmpty;
}

class SettingsStore {
  static const _baseUrl = 'server_url';
  static const _username = 'username';
  static const _password = 'password';
  static const _profile = 'stream_profile';
  static const _favorites = 'favorites';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      baseUrl: _trimUrl(prefs.getString(_baseUrl) ?? ''),
      username: prefs.getString(_username) ?? '',
      password: prefs.getString(_password) ?? '',
      profile: prefs.getString(_profile) ?? '',
    );
  }

  static Future<void> save(AppSettings value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrl, _trimUrl(value.baseUrl));
    await prefs.setString(_username, value.username);
    await prefs.setString(_password, value.password);
    await prefs.setString(_profile, value.profile);
  }

  static Future<Set<String>> favorites() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_favorites) ?? <String>[]).toSet();
  }

  static Future<void> saveFavorites(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favorites, ids.toList()..sort());
  }

  static String _trimUrl(String value) => value.trim().replaceFirst(RegExp(r'/+$'), '');
}

class TvhApi {
  final AppSettings settings;
  TvhApi(this.settings);

  Map<String, String> get _headers {
    final basic = base64Encode(utf8.encode('${settings.username}:${settings.password}'));
    return <String, String>{'Authorization': 'Basic $basic', 'Accept': 'application/json'};
  }

  Uri _uri(String endpoint, [Map<String, String>? params]) {
    return Uri.parse('${settings.baseUrl}/api/$endpoint').replace(queryParameters: params);
  }

  Future<Map<String, dynamic>> _get(String endpoint, [Map<String, String>? params]) async {
    final response = await http.get(_uri(endpoint, params), headers: _headers).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw TvhException('TVHeadend 응답 오류: HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw TvhException('TVHeadend 응답 형식이 예상과 다릅니다.');
    return Map<String, dynamic>.from(decoded);
  }

  Future<List<TvhTag>> tags() async {
    final json = await _get('channeltag/grid', <String, String>{'limit': '999'});
    final list = _entries(json).map(TvhTag.fromJson).where((e) => e.name.isNotEmpty).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<List<TvhChannel>> channels() async {
    final json = await _get('channel/grid', <String, String>{'limit': '999', 'sort': 'number', 'dir': 'ASC'});
    return _entries(json).map(TvhChannel.fromJson).where((e) => e.uuid.isNotEmpty && e.name.isNotEmpty).toList();
  }

  Future<List<StreamProfile>> profiles() async {
    final json = await _get('profile/list');
    final list = _entries(json).map(StreamProfile.fromJson).where((e) => e.key.isNotEmpty && e.name.isNotEmpty).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<List<EpgEvent>> now() async {
    final json = await _get('epg/events/grid', <String, String>{'limit': '999', 'mode': 'now'});
    return _entries(json).map(EpgEvent.fromJson).where((e) => e.channelUuid.isNotEmpty).toList();
  }

  Future<List<EpgEvent>> epgForChannel(String channelUuid) async {
    final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final json = await _get('epg/events/grid', <String, String>{
      'limit': '32',
      'channel': channelUuid,
      'start': '${seconds - 3600}',
      'end': '${seconds + 12 * 3600}',
    });
    return _entries(json).map(EpgEvent.fromJson).toList()..sort((a, b) => a.start.compareTo(b.start));
  }

  String streamUrl(TvhChannel channel) {
    final params = <String, String>{};
    if (settings.profile.trim().isNotEmpty) params['profile'] = settings.profile.trim();
    return Uri.parse('${settings.baseUrl}/stream/channel/${channel.uuid}').replace(queryParameters: params).toString();
  }

  List<Map<String, dynamic>> _entries(Map<String, dynamic> map) {
    final raw = map['entries'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}

class TvhException implements Exception {
  final String message;
  const TvhException(this.message);
  @override
  String toString() => message;
}

class TvhTag {
  final String uuid;
  final String name;
  const TvhTag(this.uuid, this.name);
  factory TvhTag.fromJson(Map<String, dynamic> json) => TvhTag('${json['uuid'] ?? ''}', '${json['name'] ?? ''}');
}

class StreamProfile {
  /// TVHeadend profile/list returns { key: UUID, val: profile-name }.
  final String key;
  final String name;
  const StreamProfile({required this.key, required this.name});
  factory StreamProfile.fromJson(Map<String, dynamic> json) => StreamProfile(
    key: '${json['key'] ?? ''}',
    name: '${json['val'] ?? ''}',
  );
}

class TvhChannel {
  final String uuid;
  final String name;
  final int number;
  final String icon;
  final Set<String> tags;

  const TvhChannel({required this.uuid, required this.name, required this.number, required this.icon, required this.tags});

  factory TvhChannel.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final tags = <String>{};
    if (rawTags is List) tags.addAll(rawTags.map((e) => '$e'));
    return TvhChannel(
      uuid: '${json['uuid'] ?? ''}',
      name: '${json['name'] ?? ''}',
      number: json['number'] is num ? (json['number'] as num).toInt() : int.tryParse('${json['number'] ?? '0'}') ?? 0,
      icon: '${json['icon_public_url'] ?? json['icon'] ?? ''}',
      tags: tags,
    );
  }
}

class EpgEvent {
  final String channelUuid;
  final String title;
  final String subtitle;
  final String description;
  final DateTime start;
  final DateTime stop;

  const EpgEvent({required this.channelUuid, required this.title, required this.subtitle, required this.description, required this.start, required this.stop});

  factory EpgEvent.fromJson(Map<String, dynamic> json) {
    DateTime parse(dynamic value) {
      if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);
      final numeric = int.tryParse('$value');
      if (numeric != null) return DateTime.fromMillisecondsSinceEpoch(numeric * 1000);
      return DateTime.tryParse('$value') ?? DateTime.now();
    }

    return EpgEvent(
      channelUuid: '${json['channelUuid'] ?? json['channel_uuid'] ?? json['channel'] ?? ''}',
      title: '${json['title'] ?? '프로그램 정보 없음'}',
      subtitle: '${json['subtitle'] ?? ''}',
      description: '${json['description'] ?? ''}',
      start: parse(json['start']),
      stop: parse(json['stop']),
    );
  }

  bool get isLive => DateTime.now().isAfter(start) && DateTime.now().isBefore(stop);
  double get progress {
    final whole = stop.difference(start).inSeconds;
    if (whole <= 0) return 0;
    return (DateTime.now().difference(start).inSeconds / whole).clamp(0, 1).toDouble();
  }
}

class BootstrapPage extends StatefulWidget {
  const BootstrapPage({super.key});
  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    SettingsStore.load().then((value) {
      if (mounted) setState(() => _settings = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) return const Scaffold(body: Center(child: CircularProgressIndicator(color: _accent)));
    if (!settings.configured) {
      return SettingsPage(
        initial: settings,
        firstRun: true,
        onSaved: (value) => setState(() => _settings = value),
      );
    }
    return MainShell(settings: settings);
  }
}

class MainShell extends StatefulWidget {
  final AppSettings settings;
  const MainShell({super.key, required this.settings});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late AppSettings _settings;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ChannelPage(settings: _settings),
      NowPage(settings: _settings),
      ProfilePage(settings: _settings, onSelected: (value) => setState(() => _settings = value)),
      FavoritesPage(settings: _settings),
      SettingsPage(initial: _settings, onSaved: (value) => setState(() => _settings = value)),
    ];
    final labels = <String>['채널', 'Now', '프로파일', '즐겨찾기', '설정'];
    final icons = <IconData>[Icons.tv_rounded, Icons.play_circle_outline_rounded, Icons.tune_rounded, Icons.star_rounded, Icons.settings_rounded];

    return LayoutBuilder(
      builder: (context, constraints) {
        final tvLayout = constraints.maxWidth >= 900;
        return Scaffold(
          body: Row(
            children: [
              if (tvLayout)
                _SideNavigation(
                  selected: _index,
                  labels: labels,
                  icons: icons,
                  onSelected: (index) => setState(() => _index = index),
                ),
              Expanded(child: SafeArea(child: IndexedStack(index: _index, children: pages))),
            ],
          ),
          bottomNavigationBar: tvLayout
              ? null
              : NavigationBar(
                  height: 68,
                  selectedIndex: _index,
                  backgroundColor: const Color(0xFF0D0D12),
                  indicatorColor: _accent.withValues(alpha: .22),
                  onDestinationSelected: (index) => setState(() => _index = index),
                  destinations: List.generate(labels.length, (index) => NavigationDestination(icon: Icon(icons[index]), label: labels[index])),
                ),
        );
      },
    );
  }
}

class _SideNavigation extends StatelessWidget {
  final int selected;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelected;
  const _SideNavigation({required this.selected, required this.labels, required this.icons, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      decoration: const BoxDecoration(color: Color(0xFF0C0C10), border: Border(right: BorderSide(color: Color(0xFF1A1A20)))),
      child: Column(
        children: [
          const SizedBox(height: 30),
          const Text('TVH', style: TextStyle(color: _accent, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -1)),
          const Text('STREAM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.7)),
          const SizedBox(height: 38),
          ...List.generate(labels.length, (index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: _TvFocusButton(
              onTap: () => onSelected(index),
              borderRadius: 12,
              child: Ink(
                height: 72,
                decoration: BoxDecoration(color: selected == index ? _accent.withValues(alpha: .92) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icons[index]), const SizedBox(height: 4), Text(labels[index], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))]),
              ),
            ),
          )),
          const Spacer(),
          const Padding(padding: EdgeInsets.only(bottom: 24), child: Text('LIVE TV', style: TextStyle(fontSize: 10, color: _muted, letterSpacing: 1.2))),
        ],
      ),
    );
  }
}

class DataLoader extends StatefulWidget {
  final AppSettings settings;
  final Widget Function(BuildContext context, AppData data, VoidCallback reload, void Function(String id) toggleFavorite) builder;
  const DataLoader({super.key, required this.settings, required this.builder});

  @override
  State<DataLoader> createState() => _DataLoaderState();
}

class _DataLoaderState extends State<DataLoader> {
  late Future<AppData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant DataLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.baseUrl != widget.settings.baseUrl || oldWidget.settings.username != widget.settings.username || oldWidget.settings.password != widget.settings.password) {
      _future = _load();
    }
  }

  Future<AppData> _load() async {
    final api = TvhApi(widget.settings);
    final values = await Future.wait<dynamic>([api.tags(), api.channels(), api.now(), SettingsStore.favorites()]);
    final tags = values[0] as List<TvhTag>;
    final channels = values[1] as List<TvhChannel>;
    final nowEvents = values[2] as List<EpgEvent>;
    final favorites = values[3] as Set<String>;
    return AppData(tags: tags, channels: channels, now: {for (final event in nowEvents) event.channelUuid: event}, favorites: favorites);
  }

  void _reload() => setState(() => _future = _load());

  void _toggle(AppData data, String id) {
    setState(() {
      if (!data.favorites.add(id)) data.favorites.remove(id);
    });
    unawaited(SettingsStore.saveFavorites(data.favorites));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator(color: _accent));
        if (snapshot.hasError) return ErrorPanel(error: '${snapshot.error}', retry: _reload);
        final data = snapshot.requireData;
        return widget.builder(context, data, _reload, (id) => _toggle(data, id));
      },
    );
  }
}

class AppData {
  final List<TvhTag> tags;
  final List<TvhChannel> channels;
  final Map<String, EpgEvent> now;
  final Set<String> favorites;
  const AppData({required this.tags, required this.channels, required this.now, required this.favorites});
}

class HomePage extends StatelessWidget {
  final AppSettings settings;
  const HomePage({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return DataLoader(
      settings: settings,
      builder: (context, data, reload, toggle) {
        final starred = data.channels.where((e) => data.favorites.contains(e.uuid)).toList();
        final live = data.channels.where((e) => data.now.containsKey(e.uuid)).toList();
        final hero = starred.isNotEmpty ? starred.first : (live.isNotEmpty ? live.first : (data.channels.isNotEmpty ? data.channels.first : null));
        return RefreshIndicator(
          color: _accent,
          onRefresh: () async => reload(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _TopBar(onRefresh: reload)),
              if (hero != null) SliverToBoxAdapter(child: _HeroLiveCard(channel: hero, event: data.now[hero.uuid], settings: settings, isFavorite: data.favorites.contains(hero.uuid), onFavorite: () => toggle(hero.uuid))),
              if (starred.isNotEmpty) SliverToBoxAdapter(child: ChannelRail(title: '즐겨찾기', subtitle: '내가 바로 보는 채널', channels: starred, data: data, settings: settings, toggle: toggle)),
              SliverToBoxAdapter(child: ChannelRail(title: '지금 계속 시청하기', subtitle: '방송 진행 중인 채널', channels: live.take(24).toList(), data: data, settings: settings, toggle: toggle)),
              ...data.tags.where((tag) => data.channels.any((channel) => channel.tags.contains(tag.uuid))).take(8).map((tag) {
                final list = data.channels.where((channel) => channel.tags.contains(tag.uuid)).toList();
                return SliverToBoxAdapter(child: ChannelRail(title: tag.name, subtitle: '${list.length}개 채널', channels: list, data: data, settings: settings, toggle: toggle));
              }),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onRefresh;
  const _TopBar({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 14),
      child: Row(children: [
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('TVH Stream', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.8)), SizedBox(height: 2), Text('내 TVHeadend 라이브러리', style: TextStyle(color: _muted, fontSize: 13))])),
        _CircleAction(icon: Icons.refresh_rounded, tooltip: '새로고침', onTap: onRefresh),
        const SizedBox(width: 10),
        const _CircleAction(icon: Icons.cast_rounded, tooltip: '캐스트 준비 중'),
      ]),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _CircleAction({required this.icon, required this.tooltip, this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: _TvFocusButton(
          onTap: onTap ?? () {},
          child: Ink(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(color: _panel2, shape: BoxShape.circle),
            child: Icon(icon, size: 20),
          ),
        ),
      );
}

class _HeroLiveCard extends StatelessWidget {
  final TvhChannel channel;
  final EpgEvent? event;
  final AppSettings settings;
  final bool isFavorite;
  final VoidCallback onFavorite;
  const _HeroLiveCard({required this.channel, required this.event, required this.settings, required this.isFavorite, required this.onFavorite});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
      child: _TvFocusButton(
        onTap: () => _openPlayer(context, settings, channel, event),
        borderRadius: 20,
        child: Container(
          constraints: const BoxConstraints(minHeight: 220),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(colors: [Color(0xFF333642), Color(0xFF111116), Color(0xFF0A0A0E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Stack(children: [
            Positioned(right: -30, top: -18, bottom: -18, width: 240, child: Opacity(opacity: .88, child: ChannelVisual(channel: channel, large: true))),
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(colors: [Colors.black.withValues(alpha: .2), _bg.withValues(alpha: .94)], begin: Alignment.centerRight, end: Alignment.centerLeft)))),
            Padding(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  const _LiveBadge(),
                  const SizedBox(height: 15),
                  Text(channel.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(event?.title ?? '현재 방송 정보를 불러오는 중입니다.', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 7),
                  Text(event == null ? '채널을 선택해 시청하세요' : '${_time(event!.start)} - ${_time(event!.stop)} · ${_progressText(event!.progress)}', style: const TextStyle(color: _muted)),
                  if (event != null) Padding(padding: const EdgeInsets.only(top: 14), child: _ProgressBar(value: event!.progress, height: 5)),
                  const SizedBox(height: 18),
                  Row(children: [
                    FilledButton.icon(onPressed: () => _openPlayer(context, settings, channel, event), style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13)), icon: const Icon(Icons.play_arrow_rounded), label: const Text('재생', style: TextStyle(fontWeight: FontWeight.w800))),
                    const SizedBox(width: 10),
                    _TvFocusButton(onTap: onFavorite, child: Ink(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(11)), child: Icon(isFavorite ? Icons.star_rounded : Icons.star_outline_rounded, color: isFavorite ? Colors.amber : Colors.white))),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(5)),
        child: const Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8)),
      );
}

class ChannelRail extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<TvhChannel> channels;
  final AppData data;
  final AppSettings settings;
  final void Function(String id) toggle;
  const ChannelRail({super.key, required this.title, required this.subtitle, required this.channels, required this.data, required this.settings, required this.toggle});

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 15, 22, 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), const SizedBox(height: 2), Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12))])),
          const Icon(Icons.chevron_right_rounded, color: _muted),
        ]),
      ),
      SizedBox(
        height: 190,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          itemCount: channels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final channel = channels[index];
            return ChannelCard(channel: channel, event: data.now[channel.uuid], settings: settings, isFavorite: data.favorites.contains(channel.uuid), onFavorite: () => toggle(channel.uuid));
          },
        ),
      ),
    ]);
  }
}

class NowPage extends StatelessWidget {
  final AppSettings settings;
  const NowPage({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return DataLoader(
      settings: settings,
      builder: (context, data, reload, toggle) {
        final items = data.now.entries.map((entry) => _NowItem(data.channels.firstWhereOrNull((e) => e.uuid == entry.key), entry.value)).where((e) => e.channel != null).cast<_NowItem>().toList()..sort((a, b) => a.channel!.number.compareTo(b.channel!.number));
        return RefreshIndicator(
          color: _accent,
          onRefresh: () async => reload(),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [
            const _SectionHeading(title: 'Now', subtitle: '지금 방송 중인 프로그램'),
            const SizedBox(height: 4),
            if (items.isEmpty) const _EmptyPanel(icon: Icons.live_tv_outlined, message: '현재 방송 정보를 찾지 못했습니다.\nTVHeadend의 EPG 설정을 확인하세요.'),
            ...items.map((item) => NowProgramTile(channel: item.channel!, event: item.event, settings: settings, isFavorite: data.favorites.contains(item.channel!.uuid), onFavorite: () => toggle(item.channel!.uuid))),
          ]),
        );
      },
    );
  }
}

class _NowItem {
  final TvhChannel? channel;
  final EpgEvent event;
  const _NowItem(this.channel, this.event);
}

class ChannelPage extends StatefulWidget {
  final AppSettings settings;
  const ChannelPage({super.key, required this.settings});
  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  String? _selectedTag;

  @override
  Widget build(BuildContext context) {
    return DataLoader(
      settings: widget.settings,
      builder: (context, data, reload, toggle) {
        final shown = _selectedTag == null
            ? data.channels
            : data.channels.where((e) => e.tags.contains(_selectedTag)).toList();
        return RefreshIndicator(
          color: _accent,
          onRefresh: () async => reload(),
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: _SectionHeading(title: '채널', subtitle: '현재 방송과 다음 프로그램을 한눈에 확인하세요'),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      TagPill(label: '전체', active: _selectedTag == null, onTap: () => setState(() => _selectedTag = null)),
                      ...data.tags.map((tag) => TagPill(label: tag.name, active: _selectedTag == tag.uuid, onTap: () => setState(() => _selectedTag = tag.uuid))),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                sliver: SliverList.separated(
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final channel = shown[index];
                    return ChannelListTile(
                      channel: channel,
                      event: data.now[channel.uuid],
                      settings: widget.settings,
                      isFavorite: data.favorites.contains(channel.uuid),
                      onFavorite: () => toggle(channel.uuid),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 9),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ProfilePage extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSelected;
  const ProfilePage({super.key, required this.settings, required this.onSelected});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<List<StreamProfile>> _future;

  @override
  void initState() {
    super.initState();
    _future = TvhApi(widget.settings).profiles();
  }

  void _reload() => setState(() => _future = TvhApi(widget.settings).profiles());

  Future<void> _select(StreamProfile profile) async {
    final next = AppSettings(
      baseUrl: widget.settings.baseUrl,
      username: widget.settings.username,
      password: widget.settings.password,
      profile: profile.name,
    );
    await SettingsStore.save(next);
    widget.onSelected(next);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('스트림 프로파일: ${profile.name}')));
  }

  Future<void> _useDefault() async {
    final next = AppSettings(
      baseUrl: widget.settings.baseUrl,
      username: widget.settings.username,
      password: widget.settings.password,
      profile: '',
    );
    await SettingsStore.save(next);
    widget.onSelected(next);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('TVHeadend 기본 프로파일을 사용합니다.')));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StreamProfile>>(
      future: _future,
      builder: (context, snapshot) {
        return RefreshIndicator(
          color: _accent,
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Row(children: [
                const Expanded(child: _SectionHeading(title: '스트림 프로파일', subtitle: 'TVHeadend 서버에서 조회한 프로파일입니다')),
                IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), tooltip: '새로고침'),
              ]),
              const SizedBox(height: 12),
              _TvFocusButton(
                onTap: _useDefault,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: widget.settings.profile.isEmpty ? _accent.withValues(alpha: .20) : _panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: widget.settings.profile.isEmpty ? _accent : Colors.white.withValues(alpha: .08))),
                  child: const Row(children: [Icon(Icons.auto_awesome_rounded), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('TVHeadend 기본값', style: TextStyle(fontWeight: FontWeight.w900)), SizedBox(height: 3), Text('서버에서 기본으로 지정한 스트림 프로파일 사용', style: TextStyle(color: _muted, fontSize: 12))]))]),
                ),
              ),
              const SizedBox(height: 10),
              if (snapshot.connectionState == ConnectionState.waiting) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: _accent)))
              else if (snapshot.hasError) _EmptyPanel(icon: Icons.error_outline_rounded, message: '프로파일을 불러오지 못했습니다.\n${snapshot.error}\n\nTVHeadend 사용자 권한에 스트리밍 권한이 있는지 확인하세요.')
              else if ((snapshot.data ?? const <StreamProfile>[]).isEmpty) const _EmptyPanel(icon: Icons.tune_rounded, message: '서버에서 사용 가능한 스트림 프로파일이 없습니다.')
              else ...snapshot.data!.map((profile) {
                final selected = widget.settings.profile == profile.name;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TvFocusButton(
                    onTap: () => _select(profile),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: selected ? _accent.withValues(alpha: .20) : _panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? _accent : Colors.white.withValues(alpha: .08))),
                      child: Row(children: [
                        Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? _accent : _muted),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Expanded(child: Text(profile.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))), ]),
                                                    Padding(padding: const EdgeInsets.only(top: 5), child: Text('프로파일 ID: ${profile.key}', style: const TextStyle(color: _muted, fontSize: 10))),
                        ])),
                      ]),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class TagPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const TagPill({super.key, required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: _TvFocusButton(
          onTap: onTap,
          borderRadius: 99,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(color: active ? _accent : _panel2, borderRadius: BorderRadius.circular(99), border: Border.all(color: active ? _accent : Colors.white.withValues(alpha: .08))),
            child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ),
      );
}

class FavoritesPage extends StatelessWidget {
  final AppSettings settings;
  const FavoritesPage({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return DataLoader(
      settings: settings,
      builder: (context, data, reload, toggle) {
        final channels = data.channels.where((e) => data.favorites.contains(e.uuid)).toList();
        return RefreshIndicator(
          color: _accent,
          onRefresh: () async => reload(),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [
            const _SectionHeading(title: '즐겨찾기', subtitle: '앱에서 저장한 채널'),
            const SizedBox(height: 12),
            if (channels.isEmpty) const _EmptyPanel(icon: Icons.star_outline_rounded, message: '아직 즐겨찾기 채널이 없습니다.\n채널 카드의 별 버튼을 눌러 추가하세요.'),
            ...channels.map((channel) => ChannelListTile(channel: channel, event: data.now[channel.uuid], settings: settings, isFavorite: true, onFavorite: () => toggle(channel.uuid))),
          ]),
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeading({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.8)), const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: _muted, fontSize: 14))]);
}

class _EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyPanel({required this.icon, required this.message});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 22),
        padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 20),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: .06))),
        child: Column(children: [Icon(icon, size: 48, color: _muted), const SizedBox(height: 16), Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.55))]),
      );
}

class _TvFocusButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double borderRadius;
  const _TvFocusButton({required this.child, required this.onTap, this.borderRadius = 12});
  @override
  State<_TvFocusButton> createState() => _TvFocusButtonState();
}

class _TvFocusButtonState extends State<_TvFocusButton> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      onFocusChange: (value) => setState(() => _focused = value),
      actions: <Type, Action<Intent>>{ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) { widget.onTap(); return null; })},
      child: AnimatedScale(
        scale: _focused ? 1.045 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(widget.borderRadius), border: _focused ? Border.all(color: Colors.white, width: 3) : null, boxShadow: _focused ? const [BoxShadow(color: Colors.black87, blurRadius: 20, spreadRadius: 2)] : null),
          child: InkWell(borderRadius: BorderRadius.circular(widget.borderRadius), onTap: widget.onTap, child: widget.child),
        ),
      ),
    );
  }
}

class ChannelCard extends StatelessWidget {
  final TvhChannel channel;
  final EpgEvent? event;
  final AppSettings settings;
  final bool isFavorite;
  final VoidCallback onFavorite;
  const ChannelCard({super.key, required this.channel, required this.event, required this.settings, required this.isFavorite, required this.onFavorite});

  @override
  Widget build(BuildContext context) {
    return _TvFocusButton(
      onTap: () => _openPlayer(context, settings, channel, event),
      borderRadius: 14,
      child: SizedBox(
        width: 205,
        child: DecoratedBox(
          decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: .055))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(14)), child: ChannelVisual(channel: channel))),
                const Positioned(left: 9, top: 9, child: _LiveBadge()),
                Positioned(right: 2, top: 1, child: IconButton(onPressed: onFavorite, icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_border_rounded, color: isFavorite ? Colors.amber : Colors.white), tooltip: '즐겨찾기')),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 3),
              child: Text('${channel.number > 0 ? '${channel.number} · ' : ''}${channel.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Text(event?.title ?? '프로그램 정보 없음', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12)),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(11, 8, 11, 12), child: _ProgressBar(value: event?.progress ?? 0, height: 3)),
          ]),
        ),
      ),
    );
  }
}

class ChannelGridCard extends StatelessWidget {
  final TvhChannel channel;
  final EpgEvent? event;
  final AppSettings settings;
  final bool isFavorite;
  final VoidCallback onFavorite;
  const ChannelGridCard({super.key, required this.channel, required this.event, required this.settings, required this.isFavorite, required this.onFavorite});

  @override
  Widget build(BuildContext context) => _TvFocusButton(
        onTap: () => _openPlayer(context, settings, channel, event),
        borderRadius: 14,
        child: DecoratedBox(
          decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: .055))),
          child: Stack(children: [
            Padding(padding: const EdgeInsets.all(12), child: Column(children: [Expanded(child: ChannelVisual(channel: channel)), const SizedBox(height: 8), Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(event?.title ?? 'EPG 정보 없음', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11)), const SizedBox(height: 8), _ProgressBar(value: event?.progress ?? 0, height: 3)])),
            Positioned(right: 0, top: 0, child: IconButton(onPressed: onFavorite, icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_border_rounded, color: isFavorite ? Colors.amber : Colors.white), tooltip: '즐겨찾기')),
          ]),
        ),
      );
}

class ChannelVisual extends StatelessWidget {
  final TvhChannel channel;
  final bool large;
  const ChannelVisual({super.key, required this.channel, this.large = false});

  @override
  Widget build(BuildContext context) {
    final text = _initials(channel.name);
    if (channel.icon.trim().isNotEmpty) {
      return Image.network(channel.icon, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _FallbackLogo(text: text, large: large));
    }
    return _FallbackLogo(text: text, large: large);
  }
}

class _FallbackLogo extends StatelessWidget {
  final String text;
  final bool large;
  const _FallbackLogo({required this.text, required this.large});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [_panel3, Color(0xFF101015)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.center,
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: large ? 42 : 26, fontWeight: FontWeight.w900, letterSpacing: -1)),
      );
}

class _ProgressBar extends StatelessWidget {
  final double value;
  final double height;
  const _ProgressBar({required this.value, required this.height});
  @override
  Widget build(BuildContext context) => ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: height, color: _accent, backgroundColor: Colors.white.withValues(alpha: .13)));
}

class NowProgramTile extends StatelessWidget {
  final TvhChannel channel;
  final EpgEvent event;
  final AppSettings settings;
  final bool isFavorite;
  final VoidCallback onFavorite;
  const NowProgramTile({super.key, required this.channel, required this.event, required this.settings, required this.isFavorite, required this.onFavorite});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _TvFocusButton(
          onTap: () => _openPlayer(context, settings, channel, event),
          child: Container(
            constraints: const BoxConstraints(minHeight: 92),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: .055))),
            child: Row(children: [
              SizedBox(width: 88, height: 70, child: ClipRRect(borderRadius: BorderRadius.circular(9), child: ChannelVisual(channel: channel))),
              const SizedBox(width: 13),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${channel.number > 0 ? '${channel.number} · ' : ''}${channel.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 4),
                Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 5),
                Text('${_time(event.start)} - ${_time(event.stop)}', style: const TextStyle(color: _muted, fontSize: 12)),
                const SizedBox(height: 7),
                _ProgressBar(value: event.progress, height: 4),
              ])),
              IconButton(onPressed: onFavorite, icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_border_rounded, color: isFavorite ? Colors.amber : Colors.white), tooltip: '즐겨찾기'),
              const Icon(Icons.play_circle_fill_rounded, color: Colors.white70),
            ]),
          ),
        ),
      );
}

class ChannelListTile extends StatelessWidget {
  final TvhChannel channel;
  final EpgEvent? event;
  final AppSettings settings;
  final bool isFavorite;
  final VoidCallback onFavorite;
  const ChannelListTile({super.key, required this.channel, required this.event, required this.settings, required this.isFavorite, required this.onFavorite});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _TvFocusButton(
          onTap: () => _openPlayer(context, settings, channel, event),
          child: Container(
            height: 86,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: .055))),
            child: Row(children: [
              SizedBox(width: 92, child: ClipRRect(borderRadius: BorderRadius.circular(9), child: ChannelVisual(channel: channel))),
              const SizedBox(width: 13),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${channel.number > 0 ? '${channel.number} · ' : ''}${channel.name}', style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(event?.title ?? 'EPG 정보 없음', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted)), const SizedBox(height: 7), _ProgressBar(value: event?.progress ?? 0, height: 3)])),
              IconButton(onPressed: onFavorite, icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_border_rounded, color: isFavorite ? Colors.amber : Colors.white), tooltip: '즐겨찾기'),
            ]),
          ),
        ),
      );
}

class PlayerPage extends StatefulWidget {
  final AppSettings settings;
  final TvhChannel channel;
  final EpgEvent? event;
  const PlayerPage({super.key, required this.settings, required this.channel, required this.event});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  List<EpgEvent> _epg = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _open();
    _loadEpg();
  }

  Future<void> _open() async {
    try {
      await _player.open(Media(TvhApi(widget.settings).streamUrl(widget.channel)));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _loadEpg() async {
    try {
      final events = await TvhApi(widget.settings).epgForChannel(widget.channel.uuid);
      if (mounted) setState(() => _epg = events);
    } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final details = _PlayerDetails(channel: widget.channel, event: widget.event, epg: _epg);
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              children: [
                Row(children: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)), const SizedBox(width: 4), Expanded(child: Text(widget.channel.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))), const Icon(Icons.more_vert_rounded)]),
                const SizedBox(height: 10),
                if (wide)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 7, child: _VideoPane(controller: _controller, error: _error)), const SizedBox(width: 20), Expanded(flex: 4, child: details)])
                else ...[_VideoPane(controller: _controller, error: _error), const SizedBox(height: 18), details],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VideoPane extends StatelessWidget {
  final VideoController controller;
  final String? error;
  const _VideoPane({required this.controller, required this.error});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(color: Colors.black, child: error == null ? Video(controller: controller, controls: MaterialVideoControls) : Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('재생을 시작하지 못했습니다.\n\n$error', textAlign: TextAlign.center, style: const TextStyle(color: _muted))))),
        ),
      );
}

class _PlayerDetails extends StatelessWidget {
  final TvhChannel channel;
  final EpgEvent? event;
  final List<EpgEvent> epg;
  const _PlayerDetails({required this.channel, required this.event, required this.epg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: .06))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [SizedBox(width: 50, height: 40, child: ChannelVisual(channel: channel)), const SizedBox(width: 10), Expanded(child: Text(channel.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))), const _LiveBadge()]),
          const SizedBox(height: 18),
          Text(event?.title ?? '현재 방송 정보 없음', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          if (event != null) ...[const SizedBox(height: 6), Text('${_time(event!.start)} - ${_time(event!.stop)} · ${_progressText(event!.progress)}', style: const TextStyle(color: _muted)), const SizedBox(height: 12), _ProgressBar(value: event!.progress, height: 5)],
          const SizedBox(height: 24),
          const Text('오늘의 편성표', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (epg.isEmpty) const Text('EPG를 불러오는 중입니다.', style: TextStyle(color: _muted)),
          ...epg.map((item) => Container(margin: const EdgeInsets.only(top: 5), padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 9), decoration: BoxDecoration(color: item.isLive ? _accent.withValues(alpha: .75) : Colors.transparent, borderRadius: BorderRadius.circular(8)), child: Row(children: [SizedBox(width: 48, child: Text(_time(item.start), style: const TextStyle(color: Colors.white70, fontFeatures: [FontFeature.tabularFigures()]))), Expanded(child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: item.isLive ? FontWeight.w800 : FontWeight.w500)))]))),
        ]),
      );
}

class SettingsPage extends StatefulWidget {
  final AppSettings initial;
  final bool firstRun;
  final ValueChanged<AppSettings> onSaved;
  const SettingsPage({super.key, required this.initial, required this.onSaved, this.firstRun = false});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _password;
  bool _saving = false;
  bool _hidden = true;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.initial.baseUrl);
    _user = TextEditingController(text: widget.initial.username);
    _password = TextEditingController(text: widget.initial.password);
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = AppSettings(baseUrl: _url.text.trim(), username: _user.text.trim(), password: _password.text, profile: widget.initial.profile);
    if (value.baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('TVHeadend 서버 주소를 입력하세요.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await SettingsStore.save(value);
      widget.onSaved(value);
      if (mounted && !widget.firstRun) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('서버 설정을 저장했습니다.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      _SettingsField(label: '서버 주소', hint: 'http://192.168.0.10:9981', controller: _url, keyboardType: TextInputType.url),
      const SizedBox(height: 14),
      _SettingsField(label: '사용자명', controller: _user),
      const SizedBox(height: 14),
      _SettingsField(label: '비밀번호', controller: _password, obscure: _hidden, suffix: IconButton(onPressed: () => setState(() => _hidden = !_hidden), icon: Icon(_hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded))),
      const SizedBox(height: 22),
      FilledButton.icon(onPressed: _saving ? null : _save, style: FilledButton.styleFrom(backgroundColor: _accent, minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded), label: Text(_saving ? '저장 중...' : widget.firstRun ? '저장하고 시작' : '설정 저장', style: const TextStyle(fontWeight: FontWeight.w800))),
    ];

    return Scaffold(
      appBar: widget.firstRun ? null : AppBar(title: const Text('설정', style: TextStyle(fontWeight: FontWeight.w900))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.all(24), children: [
              if (widget.firstRun) ...[
                const SizedBox(height: 36),
                const Text('TVH Stream', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: _accent)),
                const SizedBox(height: 8),
                const Text('TVHeadend 서버를 연결하면 바로 라이브 TV를 볼 수 있습니다.', style: TextStyle(color: _muted, height: 1.5)),
                const SizedBox(height: 32),
              ],
              Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: .06))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('TVHeadend 연결', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), const SizedBox(height: 18), ...fields])),
              const SizedBox(height: 18),
              const Text('서버 주소는 예: http://192.168.0.10:9981 형식으로 입력합니다. TVHeadend 웹 화면에 로그인할 수 있는 계정을 사용하세요.', style: TextStyle(color: _muted, fontSize: 12, height: 1.55)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;
  const _SettingsField({required this.label, this.hint, required this.controller, this.keyboardType, this.obscure = false, this.suffix});
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label, hintText: hint, suffixIcon: suffix, filled: true, fillColor: _panel2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withValues(alpha: .06))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _accent, width: 2))),
      );
}

class ErrorPanel extends StatelessWidget {
  final String error;
  final VoidCallback retry;
  const ErrorPanel({super.key, required this.error, required this.retry});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 110),
        const Icon(Icons.cloud_off_rounded, size: 58, color: _muted),
        const SizedBox(height: 18),
        const Center(child: Text('TVHeadend 데이터를 불러오지 못했습니다.', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
        const SizedBox(height: 10),
        Center(child: Text(error, textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.5))),
        const SizedBox(height: 22),
        Center(child: FilledButton.icon(onPressed: retry, style: FilledButton.styleFrom(backgroundColor: _accent), icon: const Icon(Icons.refresh_rounded), label: const Text('다시 시도'))),
      ]);
}

void _openPlayer(BuildContext context, AppSettings settings, TvhChannel channel, EpgEvent? event) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerPage(settings: settings, channel: channel, event: event)));
}

String _time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _progressText(double value) => '${(value * 100).round()}% 진행';
String _initials(String name) {
  final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9가-힣]'), '');
  if (cleaned.isEmpty) return 'TV';
  return cleaned.length <= 4 ? cleaned.toUpperCase() : cleaned.substring(0, 4).toUpperCase();
}

extension FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}

import 'dart:async';

import 'package:anytime/bloc/discovery/discovery_bloc.dart';
import 'package:anytime/bloc/discovery/discovery_state_event.dart';
import 'package:anytime/bloc/podcast/podcast_bloc.dart';
import 'package:anytime/entities/podcast.dart';
import 'package:anytime/l10n/L.dart';
import 'package:anytime/state/bloc_state.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';
import 'package:podcast_search/podcast_search.dart' show Country;
import 'package:podcast_search/podcast_search.dart' as search;
import 'package:provider/provider.dart';

const podcastGalleryExploreHeroTag = 'podcast-gallery-explore';

class PodcastGallery extends StatefulWidget {
  const PodcastGallery({super.key});

  @override
  State<PodcastGallery> createState() => _PodcastGalleryState();
}

class _PodcastGalleryState extends State<PodcastGallery> {
  static const _columns = 3;
  static const _spacing = 16.0;
  static const _swipeThreshold = 30.0;
  static const _swipeDuration = Duration(milliseconds: 260);
  static const _previewDuration = Duration(seconds: 20);
  static const _focusedScale = 1.10;
  static const _unfocusedScale = 0.90;

  final _log = Logger('PodcastGallery');
  final Set<String> _followingInProgress = {};
  late final DiscoveryBloc _discoveryBloc;
  Offset? _swipeStart;
  Offset? _swipeEnd;
  Offset _lastSwipeDirection = Offset.zero;
  bool _swipeTriggered = false;
  int? _focusedIndex;
  String? _previewPodcastUrl;
  AudioPlayer? _previewPlayer;
  StreamSubscription<PlayerState>? _previewStateSubscription;
  Timer? _previewTimer;
  int _previewGeneration = 0;
  bool _previewIsLoading = false;
  bool _previewIsPlaying = false;

  @override
  void initState() {
    super.initState();
    _discoveryBloc = Provider.of<DiscoveryBloc>(context, listen: false);
    _loadDiscoverPodcasts();
  }

  void _loadDiscoverPodcasts() {
    _discoveryBloc.discover(
      DiscoveryChartEvent(
        count: 20,
        genre: _discoveryBloc.selectedGenre.genre,
        countryCode: Country.philippines.code,
        languageCode: PlatformDispatcher.instance.locale.languageCode,
      ),
    );
  }

  void _requestPreview(Podcast podcast) {
    if (_previewPodcastUrl == podcast.url) return;
    _previewPodcastUrl = podcast.url;
    if (podcast.url.isEmpty) {
      _previewGeneration++;
      _previewTimer?.cancel();
      _previewTimer = null;
      final subscription = _previewStateSubscription;
      _previewStateSubscription = null;
      final player = _previewPlayer;
      _previewPlayer = null;
      setState(() {
        _previewIsLoading = false;
        _previewIsPlaying = false;
      });
      unawaited(_disposePreview(subscription, player));
      return;
    }
    unawaited(_loadPreview(podcast));
  }

  Future<void> _disposePreview(
    StreamSubscription<PlayerState>? subscription,
    AudioPlayer? player,
  ) async {
    try {
      await subscription?.cancel();
      await player?.dispose();
    } catch (error, stackTrace) {
      _log.warning(
          'Unable to dispose podcast preview player', error, stackTrace);
    }
  }

  void _syncPreviewFocus(Podcast podcast) {
    if (_previewPodcastUrl == podcast.url) return;

    _previewPodcastUrl = podcast.url;
    _previewGeneration++;
    _previewTimer?.cancel();
    _previewTimer = null;
    final subscription = _previewStateSubscription;
    _previewStateSubscription = null;
    final player = _previewPlayer;
    _previewPlayer = null;
    if (_previewIsLoading || _previewIsPlaying) {
      setState(() {
        _previewIsLoading = false;
        _previewIsPlaying = false;
      });
    }
    unawaited(_disposePreview(subscription, player));
  }

  Future<void> _loadPreview(Podcast podcast) async {
    final generation = ++_previewGeneration;
    _previewTimer?.cancel();
    _previewTimer = null;
    final previousSubscription = _previewStateSubscription;
    _previewStateSubscription = null;
    final previousPlayer = _previewPlayer;
    _previewPlayer = null;

    setState(() {
      _previewIsLoading = true;
      _previewIsPlaying = false;
    });

    try {
      await previousSubscription?.cancel();
      await previousPlayer?.dispose();
      if (!mounted || generation != _previewGeneration) return;

      final podcastBloc = Provider.of<PodcastBloc>(context, listen: false);
      final loadedPodcast =
          await podcastBloc.podcastService.loadPodcast(podcast: podcast);
      if (!mounted || generation != _previewGeneration) return;

      final episodes = loadedPodcast?.episodes
          .where((episode) => episode.contentUrl?.isNotEmpty == true)
          .toList()
        ?..sort(
          (a, b) => (b.publicationDate ?? DateTime(1970))
              .compareTo(a.publicationDate ?? DateTime(1970)),
        );
      if (episodes == null || episodes.isEmpty) {
        throw StateError('No playable episode was found for ${podcast.url}.');
      }

      final episode = episodes.first;
      final player = AudioPlayer();
      _previewPlayer = player;
      await player.setUrl(episode.contentUrl!);
      if (!mounted || generation != _previewGeneration) return;

      setState(() {
        _previewIsLoading = false;
        _previewIsPlaying = true;
      });
      _previewStateSubscription = player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _finishPreview(generation, player);
        }
      });
      _startPreviewTimer(generation, player, podcast);
      unawaited(
        player.play().catchError(
              (Object error, StackTrace stackTrace) =>
                  _handlePreviewError(podcast, generation, error, stackTrace),
            ),
      );
    } catch (error, stackTrace) {
      _handlePreviewError(podcast, generation, error, stackTrace);
    }
  }

  Future<void> _togglePreview(Podcast podcast) async {
    final player = _previewPlayer;
    final generation = _previewGeneration;
    if (player == null || _previewPodcastUrl != podcast.url) {
      _previewPodcastUrl = null;
      _requestPreview(podcast);
      return;
    }

    try {
      if (_previewIsPlaying) {
        _previewTimer?.cancel();
        _previewTimer = null;
        await player.pause();
        if (mounted && identical(player, _previewPlayer)) {
          setState(() => _previewIsPlaying = false);
        }
      } else {
        if (player.processingState == ProcessingState.completed) {
          await player.seek(Duration.zero);
        }
        if (!mounted ||
            generation != _previewGeneration ||
            !identical(player, _previewPlayer)) {
          return;
        }
        setState(() => _previewIsPlaying = true);
        _startPreviewTimer(generation, player, podcast);
        unawaited(
          player.play().catchError(
                (Object error, StackTrace stackTrace) => _handlePreviewError(
                  podcast,
                  generation,
                  error,
                  stackTrace,
                ),
              ),
        );
      }
    } catch (error, stackTrace) {
      _handlePreviewError(
        podcast,
        generation,
        error,
        stackTrace,
      );
    }
  }

  void _startPreviewTimer(
    int generation,
    AudioPlayer player,
    Podcast podcast,
  ) {
    _previewTimer?.cancel();
    _previewTimer = Timer(_previewDuration, () async {
      if (!mounted ||
          generation != _previewGeneration ||
          !identical(player, _previewPlayer)) {
        return;
      }
      try {
        await player.pause();
        await player.seek(Duration.zero);
        _finishPreview(generation, player);
      } catch (error, stackTrace) {
        _handlePreviewError(
          podcast,
          generation,
          error,
          stackTrace,
        );
      }
    });
  }

  void _finishPreview(int generation, AudioPlayer player) {
    if (!mounted ||
        generation != _previewGeneration ||
        !identical(player, _previewPlayer)) {
      return;
    }
    _previewTimer?.cancel();
    _previewTimer = null;
    if (_previewIsPlaying) {
      setState(() => _previewIsPlaying = false);
    }
  }

  void _handlePreviewError(
    Podcast podcast,
    int generation,
    Object error,
    StackTrace stackTrace,
  ) {
    _log.warning(
      'Unable to play preview for podcast ${podcast.url}',
      error,
      stackTrace,
    );
    if (!mounted || generation != _previewGeneration) return;
    _previewTimer?.cancel();
    _previewTimer = null;
    unawaited(_previewStateSubscription?.cancel());
    _previewStateSubscription = null;
    final player = _previewPlayer;
    _previewPlayer = null;
    setState(() {
      _previewIsLoading = false;
      _previewIsPlaying = false;
    });
    if (player != null) unawaited(player.dispose());
  }

  Future<void> _follow(Podcast podcast) async {
    setState(() => _followingInProgress.add(podcast.url));
    try {
      await Provider.of<PodcastBloc>(context, listen: false)
          .followFromDiscovery(podcast);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.of(context)!.podcast_gallery_follow_success)),
      );
    } catch (error, stackTrace) {
      _log.warning(
          'Unable to follow podcast ${podcast.url}', error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.of(context)!.podcast_gallery_follow_error)),
      );
    } finally {
      if (mounted) {
        setState(() => _followingInProgress.remove(podcast.url));
      }
    }
  }

  Future<void> _unfollow(Podcast podcast) async {
    final strings = L.of(context)!;
    final shouldUnfollow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.unsubscribe_button_label),
        content: Text(strings.unsubscribe_message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel_button_label),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.unsubscribe_button_label),
          ),
        ],
      ),
    );
    if (shouldUnfollow != true || !mounted) return;

    setState(() => _followingInProgress.add(podcast.url));
    try {
      await Provider.of<PodcastBloc>(context, listen: false)
          .unfollowFromDiscovery(podcast);
    } catch (error, stackTrace) {
      _log.warning(
        'Unable to unfollow podcast ${podcast.url}',
        error,
        stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.of(context)!.podcast_gallery_follow_error)),
      );
    } finally {
      if (mounted) {
        setState(() => _followingInProgress.remove(podcast.url));
      }
    }
  }

  void _handleSwipeUpdate(Offset position, int itemCount) {
    _swipeEnd = position;
    if (_swipeTriggered) return;

    final start = _swipeStart;
    final end = _swipeEnd;
    if (start == null || end == null) return;

    final delta = end - start;
    if (delta.distance < _swipeThreshold) return;

    _swipeTriggered = true;
    _moveFocusForSwipe(delta, itemCount);
  }

  void _handleSwipeEnd(int itemCount) {
    if (!_swipeTriggered && _swipeStart != null && _swipeEnd != null) {
      _handleSwipeUpdate(_swipeEnd!, itemCount);
    }
    _swipeStart = null;
    _swipeEnd = null;
    _swipeTriggered = false;
  }

  void _moveFocusForSwipe(Offset delta, int itemCount) {
    final direction = Offset(
      (delta.dx / delta.distance).roundToDouble(),
      (delta.dy / delta.distance).roundToDouble(),
    );
    if (direction == Offset.zero) return;

    setState(() {
      final index = _focusedIndex;
      if (index == null) return;

      final row = index ~/ _columns;
      final column = index % _columns;
      final nextColumn = column +
          (direction.dx > 0
              ? -1
              : direction.dx < 0
                  ? 1
                  : 0);
      final nextRow = row +
          (direction.dy > 0
              ? -1
              : direction.dy < 0
                  ? 1
                  : 0);
      if (nextColumn < 0 ||
          nextColumn >= _columns ||
          nextRow < 0 ||
          nextRow * _columns + nextColumn >= itemCount) {
        return;
      }

      _lastSwipeDirection = direction;
      _focusedIndex = nextRow * _columns + nextColumn;
    });
  }

  @override
  void dispose() {
    _previewGeneration++;
    _previewTimer?.cancel();
    unawaited(_previewStateSubscription?.cancel());
    unawaited(_previewPlayer?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = L.of(context)!;
    final brightness = Theme.of(context).brightness;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
        systemNavigationBarIconBrightness:
            brightness == Brightness.dark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            StreamBuilder<DiscoveryState>(
              stream: _discoveryBloc.results,
              builder: (context, snapshot) {
                final state = snapshot.data;
                if (snapshot.hasError || state is BlocErrorState) {
                  return _GalleryMessage(
                    icon: Icons.wifi_off_rounded,
                    message: strings.no_search_results_message,
                    action: TextButton(
                      onPressed: _loadDiscoverPodcasts,
                      child: Text(strings.retry_button_label),
                    ),
                  );
                }

                if (state is DiscoveryPopulatedState &&
                    state.results is search.SearchResult) {
                  final results = state.results as search.SearchResult;
                  if (results.items.isEmpty) {
                    return _GalleryMessage(
                      icon: Icons.podcasts_rounded,
                      message: strings.no_search_results_message,
                    );
                  }

                  return StreamBuilder<List<Podcast>>(
                    stream: Provider.of<PodcastBloc>(context).subscriptions,
                    initialData: const [],
                    builder: (context, subscriptionsSnapshot) {
                      return _buildGallery(
                        results,
                        subscriptionsSnapshot.data ?? const [],
                      );
                    },
                  );
                }

                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        strings.podcast_gallery_loading_message,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                );
              },
            ),
            SafeArea(
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Hero(
                        tag: podcastGalleryExploreHeroTag,
                        child: Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(24),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.explore_outlined, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  strings.explore_podcasts_label,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Material(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        shape: const CircleBorder(),
                        elevation: 4,
                        child: IconButton(
                          tooltip: strings.go_back_button_label,
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGallery(
    search.SearchResult results,
    List<Podcast> subscriptions,
  ) {
    if (_focusedIndex == null || _focusedIndex! >= results.items.length) {
      final middleRow = ((results.items.length / _columns).ceil() - 1) ~/ 2;
      _focusedIndex = (middleRow * _columns + _columns ~/ 2)
          .clamp(0, results.items.length - 1);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth * 0.70).clamp(210.0, 280.0);
        final cardHeight = (constraints.maxHeight * 0.64).clamp(300.0, 390.0);
        final rowCount = (results.items.length / _columns).ceil();
        final gridWidth = _columns * cardWidth + (_columns - 1) * _spacing;
        final gridHeight = rowCount * cardHeight + (rowCount - 1) * _spacing;
        final focusIndex = _focusedIndex!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _focusedIndex != focusIndex) return;
          _syncPreviewFocus(
            Podcast.fromSearchResultItem(results.items[focusIndex]),
          );
        });
        final focusedRow = focusIndex ~/ _columns;
        final focusedColumn = focusIndex % _columns;
        final cellWidth = cardWidth + _spacing;
        final cellHeight = cardHeight + _spacing;
        final gridOffset = Offset(
          (cellWidth * (_columns / 2).floor()) - cellWidth * focusedColumn,
          (cellHeight * (rowCount / 2).floor()) - cellHeight * focusedRow,
        );

        return _AnimatedCutoutOverlay(
          animationKey: ValueKey(focusIndex),
          cutoutSize: Size(
            cardWidth * _focusedScale,
            cardHeight * _focusedScale,
          ),
          swipeDirection: _lastSwipeDirection,
          duration: _swipeDuration,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) {
              _swipeStart = details.localPosition;
              _swipeEnd = details.localPosition;
              _swipeTriggered = false;
            },
            onPanUpdate: (details) =>
                _handleSwipeUpdate(details.localPosition, results.items.length),
            onPanEnd: (_) => _handleSwipeEnd(results.items.length),
            onPanCancel: () {
              _swipeStart = null;
              _swipeEnd = null;
              _swipeTriggered = false;
            },
            child: ClipRect(
              child: OverflowBox(
                maxWidth: gridWidth,
                maxHeight: gridHeight,
                alignment: Alignment.center,
                child: TweenAnimationBuilder<Offset>(
                  tween: Tween<Offset>(end: gridOffset),
                  duration: _swipeDuration,
                  curve: Curves.easeInOutCubic,
                  builder: (context, offset, child) =>
                      Transform.translate(offset: offset, child: child),
                  child: SizedBox(
                    width: gridWidth,
                    height: gridHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: List.generate(results.items.length, (index) {
                        final rowDistance =
                            (index ~/ _columns - focusedRow).abs();
                        final columnDistance =
                            (index % _columns - focusedColumn).abs();
                        if (rowDistance > 1 || columnDistance > 1) {
                          return const SizedBox.shrink();
                        }

                        final item = results.items[index];
                        final podcast = Podcast.fromSearchResultItem(item);
                        final isFollowing = _isFollowing(
                          podcast,
                          subscriptions,
                        );
                        final isLoading =
                            _followingInProgress.contains(podcast.url);
                        final isFocused = index == focusIndex;

                        return Positioned(
                          left: (index % _columns) * cellWidth,
                          top: (index ~/ _columns) * cellHeight,
                          width: cardWidth,
                          height: cardHeight,
                          child: AnimatedScale(
                            duration: _swipeDuration,
                            curve: Curves.easeInOutCubic,
                            scale: isFocused ? _focusedScale : _unfocusedScale,
                            child: AnimatedOpacity(
                              duration: _swipeDuration,
                              curve: Curves.easeInOutCubic,
                              opacity: isFocused ? 1 : 0.56,
                              child: _PodcastGalleryCard(
                                podcast: podcast,
                                creator: item.artistName,
                                isFollowing: isFollowing,
                                isLoading: isLoading,
                                isFocused: isFocused,
                                previewIsLoading: isFocused &&
                                    _previewPodcastUrl == podcast.url &&
                                    _previewIsLoading,
                                previewIsPlaying: isFocused &&
                                    _previewPodcastUrl == podcast.url &&
                                    _previewIsPlaying,
                                onTogglePreview: () => _togglePreview(podcast),
                                onFollow: podcast.url.isEmpty || isLoading
                                    ? null
                                    : isFollowing
                                        ? () => _unfollow(podcast)
                                        : () => _follow(podcast),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isFollowing(Podcast podcast, List<Podcast> subscriptions) {
    return subscriptions.any((subscription) {
      final sameUrl = podcast.url.isNotEmpty &&
          subscription.url.toLowerCase() == podcast.url.toLowerCase();
      final sameGuid = podcast.guid?.isNotEmpty == true &&
          subscription.guid?.isNotEmpty == true &&
          subscription.guid == podcast.guid;
      return sameUrl || sameGuid;
    });
  }
}

class _PodcastGalleryCard extends StatefulWidget {
  const _PodcastGalleryCard({
    required this.podcast,
    required this.creator,
    required this.isFollowing,
    required this.isLoading,
    required this.isFocused,
    required this.previewIsLoading,
    required this.previewIsPlaying,
    required this.onTogglePreview,
    required this.onFollow,
  });

  final Podcast podcast;
  final String? creator;
  final bool isFollowing;
  final bool isLoading;
  final bool isFocused;
  final bool previewIsLoading;
  final bool previewIsPlaying;
  final VoidCallback onTogglePreview;
  final VoidCallback? onFollow;

  @override
  State<_PodcastGalleryCard> createState() => _PodcastGalleryCardState();
}

class _PodcastGalleryCardState extends State<_PodcastGalleryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.previewIsPlaying) {
      _pulseController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _PodcastGalleryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.previewIsPlaying == oldWidget.previewIsPlaying) return;
    if (widget.previewIsPlaying) {
      _pulseController.repeat();
    } else {
      _pulseController
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = L.of(context)!;
    final artworkUrl = widget.podcast.imageUrl ?? widget.podcast.thumbImageUrl;
    final accentColor = Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (widget.previewIsPlaying)
              for (var beat = 0; beat < 3; beat++)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Transform.scale(
                      scale: 1.025 + _beatProgress(beat) * 0.22,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: accentColor.withValues(
                              alpha: 0.85 * (1 - _beatProgress(beat)),
                            ),
                            width: 2.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(
                                alpha: 0.20 * (1 - _beatProgress(beat)),
                              ),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            child!,
          ],
        );
      },
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        clipBehavior: Clip.antiAlias,
        elevation: widget.isFocused ? 12 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: widget.isFocused
                ? Theme.of(context).colorScheme.outlineVariant
                : Colors.transparent,
            width: widget.isFocused ? 2 : 0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (artworkUrl == null || artworkUrl.isEmpty)
                    ColoredBox(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.podcasts_rounded, size: 48),
                    )
                  else
                    CachedNetworkImage(
                      imageUrl: artworkUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context, url, error) => ColoredBox(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: const Icon(Icons.podcasts_rounded, size: 48),
                      ),
                    ),
                  if (widget.isFocused)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: widget.previewIsPlaying
                              ? strings.pause_button_label
                              : strings.play_button_label,
                          onPressed: widget.previewIsLoading ||
                                  widget.podcast.url.isEmpty
                              ? null
                              : widget.onTogglePreview,
                          color: Colors.white,
                          icon: widget.previewIsLoading
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  widget.previewIsPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.podcast.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: Text(
                        widget.creator?.trim().isNotEmpty == true
                            ? widget.creator!.trim()
                            : strings.discover,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                    SizedBox(
                      height: 38,
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: widget.onFollow,
                        style: _followButtonStyle(
                          context,
                          widget.isFollowing,
                        ),
                        icon: widget.isLoading
                            ? SizedBox.square(
                                dimension: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: widget.isFollowing
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer
                                      : Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                ),
                              )
                            : Icon(
                                widget.isFollowing
                                    ? Icons.remove_rounded
                                    : Icons.add_rounded,
                                size: 17,
                              ),
                        label: Text(
                          widget.isFollowing
                              ? strings.unsubscribe_button_label
                              : strings.subscribe_button_label,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _beatProgress(int beat) {
    final phase = (_pulseController.value + beat / 3) % 1;
    return Curves.easeOutCubic.transform(phase);
  }

  ButtonStyle _followButtonStyle(BuildContext context, bool isFollowing) {
    final colors = Theme.of(context).colorScheme;
    final backgroundColor =
        isFollowing ? colors.secondaryContainer : colors.primaryContainer;
    final foregroundColor =
        isFollowing ? colors.onSecondaryContainer : colors.onPrimaryContainer;

    return FilledButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      disabledBackgroundColor: backgroundColor,
      disabledForegroundColor: foregroundColor,
      side: BorderSide(color: colors.outlineVariant),
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: foregroundColor,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _GalleryMessage extends StatelessWidget {
  const _GalleryMessage({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (action != null) ...[
              const SizedBox(height: 8),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _AnimatedCutoutOverlay extends StatefulWidget {
  const _AnimatedCutoutOverlay({
    required this.child,
    required this.cutoutSize,
    required this.animationKey,
    required this.swipeDirection,
    required this.duration,
  });

  final Widget child;
  final Size cutoutSize;
  final Key animationKey;
  final Offset swipeDirection;
  final Duration duration;

  @override
  State<_AnimatedCutoutOverlay> createState() => _AnimatedCutoutOverlayState();
}

class _AnimatedCutoutOverlayState extends State<_AnimatedCutoutOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration ~/ 2,
      reverseDuration: widget.duration ~/ 2,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller.reverse();
      }
    });
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _AnimatedCutoutOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animationKey != oldWidget.animationKey) {
      _controller
        ..duration = widget.duration ~/ 2
        ..reverseDuration = widget.duration ~/ 2
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            const scaleAmount = 0.25;
            final progress = Curves.easeInOutCubic.transform(_controller.value);
            final cutoutSize = Size(
              widget.cutoutSize.width *
                  (1 - scaleAmount * progress * widget.swipeDirection.dx.abs()),
              widget.cutoutSize.height *
                  (1 - scaleAmount * progress * widget.swipeDirection.dy.abs()),
            );

            return IgnorePointer(
              child: ClipPath(
                clipper: _GalleryCutoutClipper(cutoutSize),
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.56),
                  child: const SizedBox.expand(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _GalleryCutoutClipper extends CustomClipper<Path> {
  const _GalleryCutoutClipper(this.cutoutSize);

  final Size cutoutSize;

  @override
  Path getClip(Size size) {
    final left = (size.width - cutoutSize.width) / 2;
    final top = (size.height - cutoutSize.height) / 2;
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, cutoutSize.width, cutoutSize.height),
            const Radius.circular(20),
          ),
        ),
    );
  }

  @override
  bool shouldReclip(_GalleryCutoutClipper oldClipper) =>
      cutoutSize != oldClipper.cutoutSize;
}

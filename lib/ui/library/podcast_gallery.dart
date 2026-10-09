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
  static const _swipeDuration = Duration(milliseconds: 160);
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
                                  style:
                                      Theme.of(context).textTheme.titleSmall,
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
        final focusedRow = focusIndex ~/ _columns;
        final focusedColumn = focusIndex % _columns;
        final cellWidth = cardWidth + _spacing;
        final cellHeight = cardHeight + _spacing;
        final gridOffset = Offset(
          (cellWidth * (_columns / 2).floor()) - cellWidth * focusedColumn,
          (cellHeight * (rowCount / 2).floor()) - cellHeight * focusedRow,
        );

        return _AnimatedCutoutOverlay(
          key: ValueKey(focusIndex),
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
                  curve: Curves.easeOut,
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
                            curve: Curves.easeOut,
                            scale: isFocused ? _focusedScale : _unfocusedScale,
                            child: AnimatedOpacity(
                              duration: _swipeDuration,
                              opacity: isFocused ? 1 : 0.56,
                              child: _PodcastGalleryCard(
                                podcast: podcast,
                                creator: item.artistName,
                                isFollowing: isFollowing,
                                isLoading: isLoading,
                                isFocused: isFocused,
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

class _PodcastGalleryCard extends StatelessWidget {
  const _PodcastGalleryCard({
    required this.podcast,
    required this.creator,
    required this.isFollowing,
    required this.isLoading,
    required this.isFocused,
    required this.onFollow,
  });

  final Podcast podcast;
  final String? creator;
  final bool isFollowing;
  final bool isLoading;
  final bool isFocused;
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    final strings = L.of(context)!;
    final artworkUrl = podcast.imageUrl ?? podcast.thumbImageUrl;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      elevation: isFocused ? 12 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isFocused
              ? Theme.of(context).colorScheme.outlineVariant
              : Colors.transparent,
          width: isFocused ? 2 : 0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 6,
            child: artworkUrl == null || artworkUrl.isEmpty
                ? ColoredBox(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.podcasts_rounded, size: 48),
                  )
                : CachedNetworkImage(
                    imageUrl: artworkUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    errorWidget: (context, url, error) => ColoredBox(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.podcasts_rounded, size: 48),
                    ),
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
                    podcast.title,
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
                      creator?.trim().isNotEmpty == true
                          ? creator!.trim()
                          : strings.discover,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  SizedBox(
                    height: 38,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onFollow,
                      style: _followButtonStyle(context, isFollowing),
                      icon: isLoading
                          ? SizedBox.square(
                              dimension: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isFollowing
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer
                                    : Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                              ),
                            )
                          : Icon(
                              isFollowing
                                  ? Icons.remove_rounded
                                  : Icons.add_rounded,
                              size: 17,
                            ),
                      label: Text(
                        isFollowing
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
    );
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
    super.key,
    required this.child,
    required this.cutoutSize,
    required this.swipeDirection,
    required this.duration,
  });

  final Widget child;
  final Size cutoutSize;
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
      duration: widget.duration,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller.reverse();
      }
    });
    _controller.forward();
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
            final progress = Curves.easeOut.transform(_controller.value);
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

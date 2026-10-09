// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/entities/episode.dart';
import 'package:anytime/l10n/L.dart';
import 'package:anytime/services/audio/audio_player_service.dart';
import 'package:anytime/ui/podcast/now_playing.dart';
import 'package:anytime/ui/widgets/placeholder_builder.dart';
import 'package:anytime/ui/widgets/podcast_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Displays a mini podcast player widget if a podcast is playing or paused.
///
/// If stopped a zero height box is built instead. Tapping on the mini player
/// will open the main player window.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);

    return StreamBuilder<AudioState>(
        stream: audioBloc.playingState,
        initialData: AudioState.stopped,
        builder: (context, snapshot) {
          return snapshot.data != AudioState.stopped &&
                  snapshot.data != AudioState.none &&
                  snapshot.data != AudioState.error
              ? _MiniPlayerBuilder()
              : const SizedBox(
                  height: 0.0,
                );
        });
  }
}

class _MiniPlayerBuilder extends StatefulWidget {
  @override
  _MiniPlayerBuilderState createState() => _MiniPlayerBuilderState();
}

class _MiniPlayerBuilderState extends State<_MiniPlayerBuilder>
    with SingleTickerProviderStateMixin {
  late AnimationController _playPauseController;
  late StreamSubscription<AudioState> _audioStateSubscription;

  @override
  void initState() {
    super.initState();

    _playPauseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _playPauseController.value = 1;

    _audioStateListener();
  }

  @override
  void dispose() {
    _audioStateSubscription.cancel();
    _playPauseController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final placeholderBuilder = PlaceholderBuilder.of(context);
    final colors = Theme.of(context).colorScheme;
    final miniPlayerColor = Theme.of(context).brightness == Brightness.light
        ? colors.surfaceContainerLow
        : colors.surfaceContainerHigh;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Dismissible(
        key: UniqueKey(),
        confirmDismiss: (direction) async {
          await _audioStateSubscription.cancel();
          audioBloc.transitionState(TransitionState.stop);
          return true;
        },
        direction: DismissDirection.startToEnd,
        background: DecoratedBox(
          decoration: BoxDecoration(
            color: miniPlayerColor,
            borderRadius: BorderRadius.circular(36),
          ),
        ),
        child: GestureDetector(
          key: const Key('miniplayergesture'),
          onTap: () async {
            await _audioStateSubscription.cancel();

            if (context.mounted) {
              showModalBottomSheet<void>(
                context: context,
                routeSettings: const RouteSettings(name: 'nowplaying'),
                isScrollControlled: true,
                builder: (BuildContext modalContext) {
                  return Padding(
                    padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top),
                    child: const NowPlaying(),
                  );
                },
              ).then((_) {
                _audioStateListener();
              });
            }
          },
          child: Semantics(
            header: true,
            label: L.of(context)!.semantics_mini_player_header,
            child: Container(
              height: 66,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: miniPlayerColor,
                borderRadius: BorderRadius.circular(36),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.14),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4.0, right: 4.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StreamBuilder<Episode?>(
                            stream: audioBloc.nowPlaying,
                            initialData: audioBloc.nowPlaying?.valueOrNull,
                            builder: (context, snapshot) {
                              return StreamBuilder<AudioState>(
                                  stream: audioBloc.playingState,
                                  builder: (context, stateSnapshot) {
                                    var playing = stateSnapshot.data ==
                                        AudioState.playing;

                                    return Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      children: <Widget>[
                                        SizedBox(
                                          height: 58.0,
                                          width: 58.0,
                                          child: ExcludeSemantics(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              child: snapshot.hasData
                                                  ? PodcastImage(
                                                      key: Key(
                                                          'mini${snapshot.data!.imageUrl}'),
                                                      url: snapshot
                                                          .data!.imageUrl!,
                                                      width: 58.0,
                                                      height: 58.0,
                                                      borderRadius: 30.0,
                                                      placeholder: placeholderBuilder !=
                                                              null
                                                          ? placeholderBuilder
                                                                  .builder()(
                                                              context)
                                                          : const Image(
                                                              image: AssetImage(
                                                                  'assets/images/anytime-placeholder-logo.png')),
                                                      errorPlaceholder: placeholderBuilder !=
                                                              null
                                                          ? placeholderBuilder
                                                                  .errorBuilder()(
                                                              context)
                                                          : const Image(
                                                              image: AssetImage(
                                                                  'assets/images/anytime-placeholder-logo.png')),
                                                    )
                                                  : Container(),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                            flex: 1,
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: <Widget>[
                                                Text(
                                                  snapshot.data?.title ?? '',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: textTheme.bodyMedium,
                                                ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4.0),
                                                  child: Text(
                                                    snapshot.data?.author ?? '',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: textTheme.bodySmall,
                                                  ),
                                                ),
                                              ],
                                            )),
                                        const SizedBox(width: 12),
                                        SizedBox(
                                          height: 56.0,
                                          width: 56.0,
                                          child: TextButton(
                                            style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              shape: CircleBorder(
                                                  side: BorderSide(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .surface,
                                                      width: 0.0)),
                                            ),
                                            onPressed: () {
                                              if (playing) {
                                                audioBloc.transitionState(
                                                    TransitionState
                                                        .fastforward);
                                              }
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(
                                                Icons.forward_30,
                                                semanticLabel: L
                                                    .of(context)!
                                                    .fast_forward_button_label,
                                                size: 32.0,
                                                color: Theme.of(context)
                                                    .iconTheme
                                                    .color,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        SizedBox(
                                          height: 56.0,
                                          width: 56.0,
                                          child: TextButton(
                                            style: TextButton.styleFrom(
                                              padding: EdgeInsets.zero,
                                              shape: CircleBorder(
                                                  side: BorderSide(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .surface,
                                                      width: 0.0)),
                                            ),
                                            onPressed: () {
                                              if (playing) {
                                                _pause(audioBloc);
                                              } else {
                                                _play(audioBloc);
                                              }
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: AnimatedIcon(
                                                semanticLabel: playing
                                                    ? L
                                                        .of(context)!
                                                        .pause_button_label
                                                    : L
                                                        .of(context)!
                                                        .play_button_label,
                                                size: 40.0,
                                                icon: AnimatedIcons.play_pause,
                                                color: Theme.of(context)
                                                    .iconTheme
                                                    .color,
                                                progress: _playPauseController,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  });
                            }),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 25,
                    right: 25,
                    bottom: 0,
                    child: StreamBuilder<PositionState>(
                      stream: audioBloc.playPosition,
                      initialData: audioBloc.playPosition?.valueOrNull,
                      builder: (context, snapshot) {
                        final position = snapshot.data?.position ??
                            const Duration(seconds: 0);
                        final length =
                            snapshot.data?.length ?? const Duration(seconds: 0);
                        final progress = length.inMilliseconds > 0
                            ? (position.inMilliseconds / length.inMilliseconds)
                                .clamp(0.0, 1.0)
                            : 0.0;

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            return SizedBox(
                              height: 3,
                              child: Stack(
                                children: [
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: colors.onSurface
                                          .withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: SizedBox(
                                      width: constraints.maxWidth * progress,
                                      height: 2,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).primaryColor,
                                          borderRadius:
                                              BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// We call this method to setup a listener for changing [AudioState]. This in turns calls upon the [_pauseController]
  /// to animate the play/pause icon. The [AudioBloc] playingState method is backed by a [BehaviorSubject] so we'll
  /// always get the current state when we subscribe. This, however, has a side effect causing the play/pause icon to
  /// animate when returning from the full-size player, which looks a little odd. Therefore, on the first event we move
  /// the controller to the correct state without animating. This feels a little hacky, but stops the UI from looking a
  /// little odd.
  void _audioStateListener() {
    if (mounted) {
      final audioBloc = Provider.of<AudioBloc>(context, listen: false);
      var firstEvent = true;

      _audioStateSubscription = audioBloc.playingState!.listen((event) {
        if (event == AudioState.playing || event == AudioState.buffering) {
          if (firstEvent) {
            _playPauseController.value = 1;
            firstEvent = false;
          } else {
            _playPauseController.forward();
          }
        } else {
          if (firstEvent) {
            _playPauseController.value = 0;
            firstEvent = false;
          } else {
            _playPauseController.reverse();
          }
        }
      });
    }
  }

  void _play(AudioBloc audioBloc) {
    audioBloc.transitionState(TransitionState.play);
  }

  void _pause(AudioBloc audioBloc) {
    audioBloc.transitionState(TransitionState.pause);
  }
}

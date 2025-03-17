// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:anytime/bloc/bloc.dart';
import 'package:anytime/entities/downloadable.dart';
import 'package:anytime/entities/episode.dart';
import 'package:anytime/entities/podcast.dart';
import 'package:anytime/services/audio/audio_player_service.dart';
import 'package:anytime/services/download/download_service.dart';
import 'package:anytime/services/download/mobile_download_service.dart';
import 'package:anytime/services/podcast/podcast_service.dart';
import 'package:anytime/state/bloc_state.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:collection/collection.dart' show IterableExtension;

/// The BLoC provides access to [Episode] details outside the direct scope
/// of a [Podcast].
class EpisodeBloc extends Bloc {
  final log = Logger('EpisodeBloc');
  final PodcastService podcastService;
  final AudioPlayerService audioPlayerService;
  final DownloadService downloadService;

  /// Add to sink to start an Episode download
  final PublishSubject<Episode?> _downloadEpisode = PublishSubject<Episode?>();

  /// Add to sink to fetch list of current downloaded episodes.
  final BehaviorSubject<bool> _downloadsInput = BehaviorSubject<bool>();

  /// Add to sink to fetch list of current episodes.
  final BehaviorSubject<bool> _episodesInput = BehaviorSubject<bool>();

  /// Add to sink to delete the passed [Episode] from storage.
  final PublishSubject<Episode?> _deleteDownload = PublishSubject<Episode>();

  /// Add to sink to toggle played status of the [Episode].
  final PublishSubject<Episode?> _togglePlayed = PublishSubject<Episode>();

  /// Stream of currently downloaded episodes
  Stream<BlocState<List<Episode>>>? _downloadsOutput;

  /// A separate stream that allows us to listen to changes in the podcast's episodes.
  final BehaviorSubject<List<Episode?>?> _episodesStream =
      BehaviorSubject<List<Episode?>?>();

  /// Stream of current episodes
  Stream<BlocState<List<Episode>>>? _episodesOutput;

  /// Listen to this subject's stream to obtain list of current subscriptions.
  late PublishSubject<List<Podcast>> _subscriptions;

  /// Cache of our currently downloaded episodes.
  List<Episode>? _episodes = <Episode>[];
  String _searchTerm = '';

  EpisodeBloc({
    required this.podcastService,
    required this.audioPlayerService,
    required this.downloadService,
  }) {
    _init();
  }

  void _init() {
    _downloadsOutput = _downloadsInput.switchMap<BlocState<List<Episode>>>(
        (bool silent) => _loadDownloads(silent));
    _episodesOutput = _episodesInput.switchMap<BlocState<List<Episode>>>(
        (bool silent) => _loadEpisodes(silent));

    /// When someone starts listening for subscriptions, load them.
    _subscriptions =
        PublishSubject<List<Podcast>>(onListen: _loadSubscriptions);

    _handleDeleteDownloads();
    _handleMarkAsPlayed();
    _listenEpisodeEvents();

    /// Listen to an Episode download request
    _listenDownloadRequest();

    /// Listen to active downloads
    _listenDownloads();

    /// Listen to episode change events sent by the [Repository]
    _listenEpisodeRepositoryEvents();
  }

  void _handleDeleteDownloads() async {
    _deleteDownload.stream.listen((episode) async {
      var nowPlaying = audioPlayerService.nowPlaying?.guid == episode?.guid;

      /// If we are attempting to delete the episode we are currently playing, we need to stop the audio.
      if (nowPlaying) {
        await audioPlayerService.stop();
      }

      await podcastService.deleteDownload(episode!);

      fetchDownloads(true);
    });
  }

  void _handleMarkAsPlayed() async {
    _togglePlayed.stream.listen((episode) async {
      await podcastService.toggleEpisodePlayed(episode!);

      fetchDownloads(true);
    });
  }

  void _listenEpisodeEvents() {
    // Listen for episode updates. If the episode is downloaded, we need to update.
    podcastService.episodeListener!
        .where((event) => event.episode.downloaded || event.episode.played)
        .listen((event) => fetchDownloads(true));
  }

  void applySearchFilter() {
    if (_searchTerm.isEmpty) {
      _episodesStream.add(_episodes);
    } else {
      var searchFilteredEpisodes = _episodes
          ?.where((e) =>
              e.title!.toLowerCase().contains(_searchTerm.trim().toLowerCase()))
          .toList();
      _episodesStream.add(searchFilteredEpisodes);
    }
  }

  void _refresh() {
    applySearchFilter();
  }

  @override
  void detach() {
    downloadService.dispose();
  }

  /// Sets up a listener to handle requests to download an episode.
  void _listenDownloadRequest() {
    _downloadEpisode.listen((Episode? e) async {
      log.fine('testtt');
      log.fine('Received download request for ${e!.title}');
      print('Full details: $e');

      // To prevent a pause between the user tapping the download icon and
      // the UI showing some sort of progress, set it to queued now.
      var episode = _episodes!.firstWhereOrNull((ep) => ep.guid == e.guid);
      print('Searching to: $_episodes');
      if (episode != null) {
        print('Download Episode Not Null');
        episode.downloadState = e.downloadState = DownloadState.queued;

        _refresh();

        var result = await downloadService.downloadEpisode(e);

        // If there was an error downloading the episode, push an error state
        // and then restore to none.
        if (!result) {
          episode.downloadState = e.downloadState = DownloadState.failed;
          _refresh();
          episode.downloadState = e.downloadState = DownloadState.none;
          _refresh();
        }
      } else {
        print('Download Episode ');
        e.downloadState = e.downloadState = DownloadState.queued;

        _episodesStream.add(_episodes);

        var result = await downloadService.downloadEpisode(e);

        // If there was an error downloading the episode, push an error state
        // and then restore to none.
        if (!result) {
          e.downloadState = e.downloadState = DownloadState.failed;
          _episodesStream.add(_episodes);
          e.downloadState = e.downloadState = DownloadState.none;
          _episodesStream.add(_episodes);
        }
      }
    });
  }

  /// Sets up a listener to listen for status updates from any currently downloading episode.
  ///
  /// If the ID of a current download matches that of an episode currently in
  /// use, we update the status of the episode and push it back into the episode stream.
  void _listenDownloads() {
    // Listen to download progress
    MobileDownloadService.downloadProgress.listen((downloadProgress) {
      downloadService
          .findEpisodeByTaskId(downloadProgress.id)
          .then((downloadable) {
        if (downloadable != null) {
          // If the download matches a current episode push the update back into the stream.
          var episode = _episodes?.firstWhereOrNull(
              (e) => e.downloadTaskId == downloadProgress.id);

          if (episode != null) {
            // Update the stream.
            _refresh();
          }
        } else {
          log.severe('Downloadable not found with id ${downloadProgress.id}');
        }
      });
    });
  }

  /// Listen to episode change events sent by the [Repository]
  void _listenEpisodeRepositoryEvents() {
    podcastService.episodeListener!.listen((state) {
      // Do we have this episode?
      var eidx = _episodes!.indexWhere((e) =>
          e.guid == state.episode.guid && e.pguid == state.episode.pguid);

      if (eidx != -1) {
        _episodes![eidx] = state.episode;
        _refresh();
      }
    });
  }

  Stream<BlocState<List<Episode>>> _loadDownloads(bool silent) async* {
    if (!silent) {
      yield BlocLoadingState();
    }

    _episodes = await podcastService.loadDownloads();

    yield BlocPopulatedState<List<Episode>>(results: _episodes);
  }

  Stream<BlocState<List<Episode>>> _loadEpisodes(bool silent) async* {
    if (!silent) {
      yield BlocLoadingState();
    }

    _episodes = await podcastService.loadEpisodes();

    // Ensure that _episodesStream receives updates
    _episodesStream.add(List<Episode>.from(_episodes ?? []));

    yield BlocPopulatedState<List<Episode>>(results: _episodes);
  }

  void _loadSubscriptions() async {
    _subscriptions.add(await podcastService.subscriptions());
  }

  @override
  void dispose() {
    _downloadsInput.close();
    _deleteDownload.close();
    _togglePlayed.close();
    _downloadEpisode.close();
    _subscriptions.close();
    _episodesStream.close();
    MobileDownloadService.downloadProgress.close();
    downloadService.dispose();
    super.dispose();
  }

  void Function(bool) get fetchDownloads => _downloadsInput.add;

  void Function(bool) get fetchEpisodes => _episodesInput.add;

  Stream<BlocState<List<Episode>>>? get downloads => _downloadsOutput;

  Stream<BlocState<List<Episode>>>? get episodes => _episodesOutput;

  /// Stream containing the current list of Podcast episodes.
  Stream<List<Episode?>?> get episodesStream => _episodesStream;

  void Function(Episode?) get deleteDownload => _deleteDownload.add;

  void Function(Episode?) get togglePlayed => _togglePlayed.add;
}

// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/bloc/podcast/episode_bloc.dart';
import 'package:anytime/bloc/podcast/podcast_bloc.dart';
import 'package:anytime/entities/episode.dart';
import 'package:anytime/entities/feed.dart';
import 'package:anytime/entities/podcast.dart';
import 'package:anytime/ui/podcast/podcast_details.dart';
import 'package:anytime/ui/widgets/episode_tile.dart';
import 'package:anytime/ui/widgets/tile_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PodcastTileEpisode extends StatelessWidget {
  final Podcast podcast;

  const PodcastTileEpisode({
    super.key,
    required this.podcast,
  });

  @override
  Widget build(BuildContext context) {
    final podcastBloc = Provider.of<PodcastBloc>(context, listen: false);
    final episodeBloc = Provider.of<EpisodeBloc>(context, listen: false);
    episodeBloc.fetchEpisodes(true);
    // // Ensure the podcast feed is loaded whenever the widget is built
    // podcastBloc.load(Feed(
    //   podcast: podcast,
    //   backgroundFresh: true,
    //   silently: true,
    // ));
    // // Listen to the episodes stream and print out the episodes whenever they are updated
    // podcastBloc.episodes.listen((episodes) {
    //   if (episodes != null) {
    //     print('All Episodes:');
    //     for (var episode in episodes) {
    //       print('Title: ${episode?.title}, GUID: ${episode?.guid}');
    //       // Add more properties if you want to print them
    //     }
    //   } else {
    //     print('No episodes available.');
    //   }
    // });
    return Column(
      children: [
        ListTile(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'podcastdetails'),
                builder: (context) => PodcastDetails(podcast, podcastBloc),
              ),
            );
          },
          minVerticalPadding: 9,
          leading: ExcludeSemantics(
            child: Hero(
              key: Key('tilehero${podcast.imageUrl}:${podcast.link}'),
              tag: '${podcast.imageUrl}:${podcast.link}',
              child: TileImage(
                url: podcast.imageUrl!,
                size: 60,
              ),
            ),
          ),
          title: Text(
            podcast.title,
            maxLines: 1,
          ),

          /// A ListTile's density changes depending upon whether we have 2 or more lines of text. We
          /// manually add a newline character here to ensure the density is consistent whether the
          /// podcast subtitle spans 1 or more lines. Bit of a hack, but a simple solution.
          subtitle: Text(
            '${podcast.copyright ?? ''}\n',
            maxLines: 2,
          ),
          isThreeLine: false,
        ),
        Container(
          width: 100,
          height: 100,
          color: Colors.red,
          child: ListView.builder(
            itemCount: 10,
            itemBuilder: (context, index) {
              return Container(
                child: Text('Test'),
              );
            },
          ),
        )
      ],
    );
  }
}

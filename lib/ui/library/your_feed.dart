import 'package:anytime/bloc/discovery/discovery_bloc.dart';
import 'package:anytime/bloc/discovery/discovery_state_event.dart';
import 'package:anytime/bloc/podcast/podcast_bloc.dart';
import 'package:anytime/entities/podcast.dart';
import 'package:anytime/ui/library/discovery.dart';
import 'package:anytime/ui/library/episodes.dart';
import 'package:anytime/ui/widgets/tile_image.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:sliver_tools/sliver_tools.dart';


class YourFeed extends StatefulWidget {
  static const fetchSize = 20;
  final bool categories;
  final bool inlineSearch;
  const YourFeed({  super.key,
    this.categories = false,
    this.inlineSearch = false,});

  @override
  State<YourFeed> createState() => _YourFeedState();
}

class _YourFeedState extends State<YourFeed> {
  @override
  void initState() {
    super.initState();

    final bloc = Provider.of<DiscoveryBloc>(context, listen: false);

    bloc.discover(DiscoveryChartEvent(
      count: Discovery.fetchSize,
      genre: bloc.selectedGenre.genre,
      countryCode:
      PlatformDispatcher.instance.locale.countryCode?.toLowerCase() ?? '',
      languageCode: PlatformDispatcher.instance.locale.languageCode,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bloc = Provider.of<DiscoveryBloc>(context);

    return  MultiSliver(children: [
      Padding(
        padding: const EdgeInsets.only(left:15.0,right: 12.0),
        child: Row(
          children: [
            Text('Subscription', style: Theme.of(context).textTheme.titleMedium,),
            Spacer(),
            TextButton(
              onPressed: (){},

              child: Text('More', )),
          ],
        ),
      ),

      SliverPersistentHeader(
        delegate: MyHeaderDelegateSubscription(bloc),
        pinned: true,
        floating: true,
      ),
      Divider(),
      const Episodes()]);;
  }
}


class MyHeaderDelegateSubscription extends SliverPersistentHeaderDelegate {
  final DiscoveryBloc discoveryBloc;

  MyHeaderDelegateSubscription(this.discoveryBloc);

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SubscriptionSelectorWidget();
  }

  @override
  double get maxExtent => 70.0;

  @override
  double get minExtent => 70.0;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      true;
}


class SubscriptionSelectorWidget extends StatefulWidget {
  final ItemScrollController itemScrollController = ItemScrollController();

  SubscriptionSelectorWidget({
    super.key,
  //  required this.discoveryBloc,
  });

 // final DiscoveryBloc discoveryBloc;

  @override
  State<SubscriptionSelectorWidget> createState() => _SubsciprionSelectorWidgetState();
}

class _SubsciprionSelectorWidgetState extends State<SubscriptionSelectorWidget> {
  @override
  Widget build(BuildContext context) {
    //String selectedCategory = widget.discoveryBloc.selectedGenre.genre;
    final podcastBloc = Provider.of<PodcastBloc>(context);

    return Container(
      width: double.infinity,
      color: Theme.of(context).canvasColor,
      child: StreamBuilder<List<Podcast>>(
          stream: podcastBloc.subscriptions,
          initialData: const [],
          builder: (context, snapshot) {
          //  var i = podcastBloc.selectedGenre.index;

            return snapshot.hasData && snapshot.data!.isNotEmpty
                ? ScrollablePositionedList.builder(
              //  initialScrollIndex: (i > 0) ? i : 0,
                itemScrollController: widget.itemScrollController,
                itemCount: snapshot.data!.length,
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, i) {
                  final item = snapshot.data![i];
                  final padding = i == 0 ? 14.0 : 2.0;

                  return Container(
                    margin: EdgeInsets.only(left: padding),
                    child: Card(
                      // color: item == selectedCategory ||
                      //     (selectedCategory.isEmpty && i == 0)
                      //     ? Theme.of(context).cardTheme.shadowColor
                      //     : Theme.of(context).cardTheme.color,
                      // child: TextButton(
                      //   style: TextButton.styleFrom(
                      //     foregroundColor: const Color(0xffffffff),
                      //     visualDensity: VisualDensity.compact,
                      //   ),
                      //   onPressed: () {
                      //     setState(() {
                      //     //  selectedCategory = item;
                      //     });
                      //
                      //     widget.discoveryBloc.discover(DiscoveryChartEvent(
                      //       count: Discovery.fetchSize,
                      //       genre: item,
                      //       countryCode: PlatformDispatcher
                      //           .instance.locale.countryCode
                      //           ?.toLowerCase() ??
                      //           '',
                      //       languageCode: PlatformDispatcher
                      //           .instance.locale.languageCode,
                      //     ));
                      //   },
                        child: Column(
                          children: [

                            ClipRRect(
                              borderRadius: BorderRadius.all(Radius.circular(15)),
                              child: TileImage(
                                url: item.imageUrl!,
                                size: 60,
                              ),
                            )
                          ],
                        ),
                      //),
                    ),
                  );
                })
                : Container();
          }),
    );
  }
}



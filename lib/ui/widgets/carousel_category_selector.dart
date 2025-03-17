import 'dart:ui';

import 'package:anytime/bloc/discovery/discovery_bloc.dart';
import 'package:anytime/bloc/discovery/discovery_state_event.dart';
import 'package:anytime/ui/library/discovery.dart';

import 'package:flutter/material.dart';

/// This delegate is responsible for rendering the horizontal scrolling list of categories
/// that can optionally be displayed at the top of the Discovery results page.

class CarouselExample extends StatefulWidget {
  const CarouselExample({super.key, required this.discoveryBloc});

  final DiscoveryBloc discoveryBloc;

  @override
  State<CarouselExample> createState() => _CarouselExampleState();
}

class _CarouselExampleState extends State<CarouselExample> {
  final CarouselController controller = CarouselController(initialItem: 1);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String selectedCategory = widget.discoveryBloc.selectedGenre.genre;

    return StreamBuilder<List<String>>(
        stream: widget.discoveryBloc.genres,
        initialData: const [],
        builder: (context, snapshot) {
          return snapshot.hasData && snapshot.data!.isNotEmpty
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 50),
                  child: CarouselView.weighted(
                      onTap: (value) {
                        final item = snapshot.data![value];

                        setState(() {
                          selectedCategory = item;
                        });

                        widget.discoveryBloc.discover(DiscoveryChartEvent(
                          count: Discovery.fetchSize,
                          genre: item,
                          countryCode: PlatformDispatcher
                                  .instance.locale.countryCode
                                  ?.toLowerCase() ??
                              '',
                          languageCode:
                              PlatformDispatcher.instance.locale.languageCode,
                        ));
                      },
                      flexWeights: const <int>[1, 2, 3, 2, 1],
                      consumeMaxWeight: false,
                      children: List.generate(snapshot.data!.length, (index) {
                        final item = snapshot.data![index];
                        return ColoredBox(
                          color: item == selectedCategory ||
                                  (selectedCategory.isEmpty && index == 0)
                              ? Theme.of(context).colorScheme.secondary
                              : Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withAlpha(200),
                          child: SizedBox.expand(
                            child: Center(
                              child: Text(
                                snapshot.data![index].toString(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 20),
                                overflow: TextOverflow.clip,
                                softWrap: false,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        );
                      })),
                )
              : Container();
        });
  }
}

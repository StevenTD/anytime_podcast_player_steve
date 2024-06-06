// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:percent_indicator/percent_indicator.dart';

class PlayPauseButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String title;
  final double? radius;
  final double? size;

  const PlayPauseButton({
    super.key,
    required this.icon,
    required this.label,
    required this.title,
    this.radius,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $title',
      child: CircularPercentIndicator(
        radius: radius ?? 19.0,
        lineWidth: 1.5,
        backgroundColor: Theme.of(context).primaryColor,
        percent: 0.0,
        center: Icon(
          icon,
          size: size ?? 22.0,

          /// Why is this not picking up the theme like other widgets?!?!?!
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }
}

class PlayPauseBusyButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String title;
  final double? radius;
  final double? size;

  const PlayPauseBusyButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.title,
      this.radius,
      this.size});

  @override
  Widget build(BuildContext context) {
    return Semantics(
        label: '$label $title',
        child: Stack(
          children: <Widget>[
            Center(
              child: Container(
                height: (size != null) ? 33.0 : 48,
                width: (size != null) ? 30.0 : 48,
                child: Icon(
                  icon,
                  size: size ?? 22.0,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
            SpinKitRing(
              lineWidth: 1.5,
              color: Theme.of(context).primaryColor,
              size: () {
                if (size == null) {
                  return 38.0;
                } else {
                  return size! + 10;
                }
              }(),
            ),
          ],
        ));
  }
}

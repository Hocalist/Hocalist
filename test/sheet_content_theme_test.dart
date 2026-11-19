import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hocalist/components/account_role_components.dart';
import 'package:hocalist/main.dart' show HocalistTheme;
import 'package:hocalist/theme/buyer_ui_foundation.dart';
import 'package:hocalist/theme/seller_ui_foundation.dart';

void main() {
  for (final seller in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'Popup body and options use role typography, seller=$seller dark=$dark',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? HocalistTheme.dark : HocalistTheme.light,
              home: Scaffold(
                body: AccountModalSheet(
                  seller: seller,
                  title: 'Title',
                  icon: Icons.info_outline,
                  onClose: () {},
                  child: const Column(
                    children: [
                      Text('Body'),
                      ListTile(
                        title: Text('Option'),
                        subtitle: Text('Description'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          final context = tester.element(find.text('Body'));
          final metrics = ApprovedReplicaMetrics.resolve(
            brightness: Theme.of(context).brightness,
            availableWidth: MediaQuery.sizeOf(context).width,
            textScaler: MediaQuery.textScalerOf(context),
          );
          final approved = seller
              ? sellerText(
                  metrics,
                  12,
                  color: SellerUiColors.body,
                  height: 1.45,
                )
              : BuyerTypography.style(
                  context,
                  metrics,
                  BuyerTextRole.primaryBody,
                );
          final style = DefaultTextStyle.of(context).style;
          expect(style.fontSize, approved.fontSize);
          expect(style.color, approved.color);
          expect(style.height, approved.height);
          final label = DefaultTextStyle.of(
            tester.element(find.text('Option')),
          ).style;
          final caption = DefaultTextStyle.of(
            tester.element(find.text('Description')),
          ).style;
          expect(label.fontWeight, FontWeight.w800);
          expect(label.fontSize, greaterThan(caption.fontSize!));
          expect(
            style.fontFamily,
            Theme.of(context).textTheme.bodyMedium?.fontFamily,
          );
        },
      );
    }
  }
}
